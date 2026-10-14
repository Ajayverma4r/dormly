// modules/tenant-portal/tenant-statement.service.ts
//
// Payment history across every stay of the signed-in tenant (current and
// ended). Every row is scoped by tenancies.user_id = the token's user, so a
// client-supplied property id can only narrow the caller's own records.

import { query } from '@config/db';
import {
  calendarDateInTimeZone,
  hostelBillingTimeZone,
} from '@modules/billing/hostel-billing-cycle';

export class StatementRequestError extends Error {
  constructor(message: string, readonly status: number) {
    super(message);
  }
}

export type StatementFilter = {
  propertyId?: string;
  from?: string;
  to?: string;
};

export type TenantStay = {
  tenancy_id: string;
  property_id: string;
  property_name: string;
  property_city: string | null;
  node_name: string | null;
  parent_node_name: string | null;
  node_level_key: string | null;
  move_in_at: string | null;
  move_out_at: string | null;
  status: string;
  is_current: boolean;
};

export type StatementPayment = {
  id: string;
  amount: number;
  method: string | null;
  paid_at: string;
  /** Property-local calendar date of the payment (YYYY-MM-DD). */
  paid_on: string;
  invoice_id: string;
  period_start: string | null;
  period_end: string | null;
  invoice_total: number;
  /** Current remaining balance of the invoice this payment went to. */
  invoice_balance: number;
  property_id: string;
  property_name: string;
  tenancy_id: string;
};

export type StatementResult = {
  filter: { propertyId: string | null; from: string | null; to: string | null };
  summary: {
    total_received: number;
    payment_count: number;
    invoice_count: number;
    /** Outstanding now on sent invoices in the property scope; not date-limited. */
    current_outstanding: number;
  };
  payments: StatementPayment[];
};

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const DATE_RE = /^(\d{4})-(\d{2})-(\d{2})$/;

function validDate(raw: string): boolean {
  const m = DATE_RE.exec(raw);
  if (!m) return false;
  const d = new Date(Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3])));
  return d.getUTCFullYear() === Number(m[1])
    && d.getUTCMonth() === Number(m[2]) - 1
    && d.getUTCDate() === Number(m[3]);
}

function money(v: unknown): number {
  const n = Number(v ?? 0);
  return Number.isFinite(n) ? Math.round(n * 100) / 100 : 0;
}

function iso(v: unknown): string | null {
  if (v == null) return null;
  return v instanceof Date ? v.toISOString() : String(v);
}

export class TenantStatementService {
  /** Current and ended stays of the user; pending (not yet started) are left out. */
  async listStays(userId: string, currentTenancyId?: string): Promise<TenantStay[]> {
    const rows = await query<any>(
      `SELECT t.id AS tenancy_id, t.property_id, t.status::text AS status,
              t.move_in_at, t.move_out_at,
              p.name AS property_name, p.city AS property_city,
              n.name AS node_name, parent_n.name AS parent_node_name,
              hl.internal_key AS node_level_key
       FROM tenancies t
       JOIN properties p ON p.id = t.property_id
       LEFT JOIN hierarchy_nodes n ON n.id = t.node_id
       LEFT JOIN hierarchy_nodes parent_n ON parent_n.id = n.parent_node_id
       LEFT JOIN hierarchy_levels hl ON hl.id = n.level_id
       WHERE t.user_id = $1::uuid AND t.status::text IN ('active', 'ended')
       ORDER BY t.move_in_at DESC NULLS LAST`,
      [userId],
    );
    return rows.map((r) => ({
      tenancy_id: String(r.tenancy_id),
      property_id: String(r.property_id),
      property_name: r.property_name ?? 'Property',
      property_city: r.property_city ?? null,
      node_name: r.node_name ?? null,
      parent_node_name: r.parent_node_name ?? null,
      node_level_key: r.node_level_key ?? null,
      move_in_at: iso(r.move_in_at),
      move_out_at: iso(r.move_out_at),
      status: r.status,
      is_current: r.status === 'active' && String(r.tenancy_id) === currentTenancyId,
    }));
  }

  /** Validates the filter; an unknown or foreign property is reported as not found. */
  async resolveFilter(userId: string, raw: StatementFilter) {
    const from = raw.from?.trim() || undefined;
    const to = raw.to?.trim() || undefined;
    if (from && !validDate(from)) throw new StatementRequestError('Invalid from date.', 400);
    if (to && !validDate(to)) throw new StatementRequestError('Invalid to date.', 400);
    if (from && to && from > to) {
      throw new StatementRequestError('From date must be on or before the to date.', 400);
    }

    const propertyId = raw.propertyId?.trim() || undefined;
    if (propertyId) {
      if (!UUID_RE.test(propertyId)) throw new StatementRequestError('Property not found.', 404);
      const own = await query(
        `SELECT 1 FROM tenancies
         WHERE user_id = $1::uuid AND property_id = $2::uuid
           AND status::text IN ('active', 'ended')
         LIMIT 1`,
        [userId, propertyId],
      );
      if (own.length === 0) throw new StatementRequestError('Property not found.', 404);
    }
    return { propertyId: propertyId ?? null, from: from ?? null, to: to ?? null };
  }

  async getHistory(userId: string, raw: StatementFilter): Promise<StatementResult> {
    const filter = await this.resolveFilter(userId, raw);
    const params: unknown[] = [userId];
    let propertyClause = '';
    if (filter.propertyId) {
      params.push(filter.propertyId);
      propertyClause = `AND i.property_id = $2::uuid`;
    }

    const rows = await query<any>(
      `SELECT pay.id::text AS id, pay.amount, pay.method, pay.paid_at,
              i.id AS invoice_id,
              to_char(i.period_start, 'YYYY-MM-DD') AS period_start,
              to_char(i.period_end, 'YYYY-MM-DD') AS period_end,
              i.total_amount,
              i.total_amount - COALESCE(
                (SELECT SUM(p2.amount) FROM payments p2 WHERE p2.invoice_id = i.id), 0
              ) AS invoice_balance,
              pr.id AS property_id, pr.name AS property_name, pr.timezone,
              t.id AS tenancy_id
       FROM payments pay
       JOIN invoices i ON i.id = pay.invoice_id
       JOIN tenancies t ON t.id = i.tenancy_id
       JOIN properties pr ON pr.id = i.property_id
       WHERE t.user_id = $1::uuid
         AND t.status::text IN ('active', 'ended')
         AND i.sent_at IS NOT NULL
         ${propertyClause}
       ORDER BY pay.paid_at DESC`,
      params,
    );

    const payments: StatementPayment[] = [];
    for (const r of rows) {
      const paidAt = r.paid_at instanceof Date ? r.paid_at : new Date(r.paid_at);
      const paidOn = calendarDateInTimeZone(paidAt, hostelBillingTimeZone(r.timezone));
      if (filter.from && paidOn < filter.from) continue;
      if (filter.to && paidOn > filter.to) continue;
      payments.push({
        id: String(r.id),
        amount: money(r.amount),
        method: r.method ?? null,
        paid_at: paidAt.toISOString(),
        paid_on: paidOn,
        invoice_id: String(r.invoice_id),
        period_start: r.period_start ?? null,
        period_end: r.period_end ?? null,
        invoice_total: money(r.total_amount),
        invoice_balance: Math.max(0, money(r.invoice_balance)),
        property_id: String(r.property_id),
        property_name: r.property_name ?? 'Property',
        tenancy_id: String(r.tenancy_id),
      });
    }

    const [outstanding] = await query<{ total: string | null }>(
      `SELECT COALESCE(SUM(GREATEST(
                i.total_amount - COALESCE(
                  (SELECT SUM(p2.amount) FROM payments p2 WHERE p2.invoice_id = i.id), 0
                ), 0)), 0) AS total
       FROM invoices i
       JOIN tenancies t ON t.id = i.tenancy_id
       WHERE t.user_id = $1::uuid
         AND t.status::text IN ('active', 'ended')
         AND i.sent_at IS NOT NULL
         ${propertyClause}`,
      params,
    );

    return {
      filter,
      summary: {
        total_received: money(payments.reduce((s, p) => s + p.amount, 0)),
        payment_count: payments.length,
        invoice_count: new Set(payments.map((p) => p.invoice_id)).size,
        current_outstanding: money(outstanding?.total),
      },
      payments,
    };
  }

  /** Name and phone of the statement holder, from their own records only. */
  async statementHolder(userId: string, currentTenancyId?: string) {
    const [row] = await query<{ full_name: string | null; phone: string | null }>(
      `SELECT t.full_name, u.phone
       FROM users u
       LEFT JOIN tenancies t ON t.user_id = u.id
       WHERE u.id = $1::uuid
       ORDER BY (t.id::text = $2) DESC, t.move_in_at DESC NULLS LAST
       LIMIT 1`,
      [userId, currentTenancyId ?? ''],
    );
    return { name: row?.full_name ?? 'Tenant', phone: row?.phone ?? null };
  }
}
