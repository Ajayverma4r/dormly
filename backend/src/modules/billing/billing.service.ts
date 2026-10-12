// modules/billing/billing.service.ts
import { query } from '@config/db';
import {
  calendarDateInTimeZone,
  compareYmd,
  hostelBillingTimeZone,
  hostelCyclesDue,
} from './hostel-billing-cycle';
import {
  createNotification,
  notifyPropertyOwners,
} from '@modules/notifications/notify';

/** A regular invoice already exists for this tenancy's billing cycle. */
export class InvoiceConflictError extends Error {
  readonly code = 'invoice_exists';
  constructor(
    message: string,
    readonly invoiceId: string,
    readonly isDraft: boolean,
  ) {
    super(message);
  }
}

export type ChargeKind =
  | 'rent'
  | 'electricity'
  | 'maintenance'
  | 'previous_dues'
  | 'other';

interface LineItemInput {
  chargeTypeId?: string;
  description: string;
  amount: number;
  chargeKind?: ChargeKind;
}

interface CreateInvoiceInput {
  tenancyId: string;
  propertyId: string;
  periodStart: string;
  periodEnd: string;
  dueDate: string;
  lineItems: LineItemInput[];
  /** Append unbilled past-rent arrears as a Previous Dues line item. */
  includeArrears?: boolean;
  /** Attach pending meter/utility charges after insert. */
  includePendingCharges?: boolean;
}

interface UpdateInvoiceInput {
  periodStart: string;
  periodEnd: string;
  dueDate: string;
  lineItems: LineItemInput[];
}

export type ArrearsPreview = {
  monthlyRent: number;
  moveInAt: string | null;
  unbilledMonths: string[]; // YYYY-MM
  amount: number;
  description: string | null;
  includePastRentArrears: boolean;
};

const MONTH_SHORT = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

let billingSchemaReady: Promise<void> | null = null;

export async function ensureBillingSchema(): Promise<void> {
  if (!billingSchemaReady) {
    billingSchemaReady = (async () => {
      try {
        await query(`
          DO $$ BEGIN
            CREATE TYPE invoice_charge_kind AS ENUM (
              'rent', 'electricity', 'maintenance', 'previous_dues', 'other'
            );
          EXCEPTION WHEN duplicate_object THEN NULL;
          END $$;
        `);
      } catch (err) {
        console.warn('[billing] charge_kind enum ensure:', err);
      }

      await query(
        `ALTER TABLE invoice_line_items
           ADD COLUMN IF NOT EXISTS charge_kind invoice_charge_kind`,
      ).catch((err) => console.warn('[billing] charge_kind column:', err));

      await query(
        `ALTER TABLE tenancies
           ADD COLUMN IF NOT EXISTS include_past_rent_arrears BOOLEAN NOT NULL DEFAULT true`,
      ).catch((err) =>
        console.warn('[billing] include_past_rent_arrears column:', err),
      );

      // Review workflow (see migration 025). NULL sent_at = draft.
      // The temporary default back-fills existing invoices as already sent.
      await query(
        `ALTER TABLE invoices ADD COLUMN IF NOT EXISTS sent_at TIMESTAMPTZ DEFAULT now()`,
      ).catch((err) => console.warn('[billing] sent_at column:', err));
      await query(
        `ALTER TABLE invoices ALTER COLUMN sent_at DROP DEFAULT`,
      ).catch((err) => console.warn('[billing] sent_at default:', err));
      await query(
        `ALTER TABLE invoices
           ADD COLUMN IF NOT EXISTS is_auto_generated BOOLEAN NOT NULL DEFAULT false`,
      ).catch((err) => console.warn('[billing] is_auto_generated column:', err));
      const [overdueCol] = await query<{ exists: boolean }>(
        `SELECT EXISTS (
           SELECT 1 FROM information_schema.columns
           WHERE table_name = 'invoices' AND column_name = 'overdue_notified_at'
         ) AS exists`,
      ).catch(() => [{ exists: true }]);
      if (!overdueCol?.exists) {
        await query(
          `ALTER TABLE invoices ADD COLUMN IF NOT EXISTS overdue_notified_at TIMESTAMPTZ`,
        ).catch((err) => console.warn('[billing] overdue_notified_at column:', err));
        // Invoices already past due before this feature shipped are not re-announced.
        await query(
          `UPDATE invoices SET overdue_notified_at = now()
           WHERE due_date < CURRENT_DATE AND overdue_notified_at IS NULL`,
        ).catch((err) => console.warn('[billing] overdue_notified_at backfill:', err));
      }
      await query(
        `CREATE UNIQUE INDEX IF NOT EXISTS invoices_tenancy_period_start_uniq
           ON invoices (tenancy_id, period_start)`,
      ).catch((err) =>
        console.warn(
          '[billing] unique (tenancy_id, period_start) not created — existing duplicates?',
          err,
        ),
      );
    })();
  }
  return billingSchemaReady;
}

function isoDate(d: Date): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

function dbDateToYmd(value: Date | string): string {
  if (value instanceof Date) return value.toISOString().slice(0, 10);
  return String(value).slice(0, 10);
}

function monthKey(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
}

function parseDateOnly(raw: string): Date {
  const [y, m, day] = raw.slice(0, 10).split('-').map(Number);
  return new Date(y, m - 1, day || 1);
}

function formatMonthLabel(ym: string): string {
  const [y, m] = ym.split('-').map(Number);
  return `${MONTH_SHORT[(m ?? 1) - 1]} ${y}`;
}

/** "2026-11-15" → "15 Nov 2026" */
function formatShortDate(ymd: string): string {
  const [y, m, d] = ymd.slice(0, 10).split('-').map(Number);
  return `${d} ${MONTH_SHORT[(m ?? 1) - 1]} ${y}`;
}

function formatArrearsDescription(months: string[]): string {
  if (months.length === 0) return 'Previous Dues';
  if (months.length === 1) {
    return `Previous Dues (${formatMonthLabel(months[0])})`;
  }
  const first = formatMonthLabel(months[0]);
  const last = formatMonthLabel(months[months.length - 1]);
  return `Previous Dues (${first}–${last})`;
}

function inferChargeKind(
  description: string,
  chargeTypeName?: string | null,
): ChargeKind {
  const blob = `${description} ${chargeTypeName ?? ''}`.toLowerCase();
  if (
    blob.includes('previous dues') ||
    blob.includes('arrears') ||
    blob.includes('prior dues')
  ) {
    return 'previous_dues';
  }
  if (blob.includes('electric')) return 'electricity';
  if (blob.includes('maintenance') || blob.includes('cam')) return 'maintenance';
  if (blob.includes('rent')) return 'rent';
  return 'other';
}

export class BillingService {
  // ---- Charge Types ----

  async listChargeTypes(propertyId: string) {
    return query(
      `SELECT * FROM charge_types WHERE property_id = $1 AND is_active = true ORDER BY order_index`,
      [propertyId],
    );
  }

  async createChargeType(
    propertyId: string,
    name: string,
    defaultAmount: number,
    isRecurring: boolean,
  ) {
    const existing = await query<{ count: string }>(
      `SELECT COUNT(*)::text AS count FROM charge_types WHERE property_id = $1`,
      [propertyId],
    );
    const [row] = await query(
      `INSERT INTO charge_types (property_id, name, default_amount, is_recurring, order_index)
       VALUES ($1,$2,$3,$4,$5) RETURNING *`,
      [propertyId, name, defaultAmount, isRecurring, Number(existing[0].count)],
    );
    return row;
  }

  async deleteChargeType(chargeTypeId: string) {
    await query(`UPDATE charge_types SET is_active = false WHERE id = $1`, [
      chargeTypeId,
    ]);
  }

  // ---- Arrears engine ----

  /**
   * Months from move-in month up to (but not including) the billing cycle month
   * that have no overlapping invoice — billed as a single Previous Dues line.
   */
  async computeUnbilledArrears(
    tenancyId: string,
    periodStart: string,
    monthlyRentOverride?: number,
  ): Promise<ArrearsPreview> {
    await ensureBillingSchema();

    const [tenancy] = await query<{
      move_in_at: Date | string | null;
      monthly_rent: string | number | null;
      include_past_rent_arrears: boolean | null;
    }>(
      `SELECT move_in_at, monthly_rent, include_past_rent_arrears
       FROM tenancies WHERE id = $1`,
      [tenancyId],
    );

    const monthlyRent =
      monthlyRentOverride != null && monthlyRentOverride > 0
        ? monthlyRentOverride
        : Number(tenancy?.monthly_rent ?? 0);
    const includePast =
      tenancy?.include_past_rent_arrears !== false;
    const moveInRaw = tenancy?.move_in_at
      ? String(tenancy.move_in_at)
      : null;

    const empty: ArrearsPreview = {
      monthlyRent,
      moveInAt: moveInRaw,
      unbilledMonths: [],
      amount: 0,
      description: null,
      includePastRentArrears: includePast,
    };

    if (!tenancy || !moveInRaw || monthlyRent <= 0) return empty;

    const moveIn = new Date(moveInRaw);
    if (Number.isNaN(moveIn.getTime())) return empty;

    const cycleStart = parseDateOnly(periodStart);
    const startMonth = new Date(moveIn.getFullYear(), moveIn.getMonth(), 1);
    const endExclusive = new Date(
      cycleStart.getFullYear(),
      cycleStart.getMonth(),
      1,
    );

    if (startMonth >= endExclusive) return empty;

    const invoices = await query<{
      period_start: Date | string;
      period_end: Date | string;
    }>(
      `SELECT period_start, period_end FROM invoices WHERE tenancy_id = $1`,
      [tenancyId],
    );

    const billedKeys = new Set<string>();
    for (const inv of invoices) {
      const ps = new Date(inv.period_start);
      const pe = new Date(inv.period_end);
      if (Number.isNaN(ps.getTime()) || Number.isNaN(pe.getTime())) continue;
      const cursor = new Date(ps.getFullYear(), ps.getMonth(), 1);
      const last = new Date(pe.getFullYear(), pe.getMonth(), 1);
      while (cursor <= last) {
        billedKeys.add(monthKey(cursor));
        cursor.setMonth(cursor.getMonth() + 1);
      }
    }

    const unbilledMonths: string[] = [];
    const cursor = new Date(startMonth);
    while (cursor < endExclusive) {
      const key = monthKey(cursor);
      if (!billedKeys.has(key)) unbilledMonths.push(key);
      cursor.setMonth(cursor.getMonth() + 1);
    }

    if (unbilledMonths.length === 0) return empty;

    const amount = Number(
      (unbilledMonths.length * monthlyRent).toFixed(2),
    );
    return {
      monthlyRent,
      moveInAt: moveInRaw,
      unbilledMonths,
      amount,
      description: formatArrearsDescription(unbilledMonths),
      includePastRentArrears: includePast,
    };
  }

  /**
   * Pending meter / utility charges not yet attached to any invoice.
   */
  async listPendingUtilityCharges(tenancyId: string) {
    await ensureBillingSchema();
    return query<{
      id: string;
      amount: string;
      billing_cycle: string;
      units_consumed: string | null;
      rate_per_unit: string | null;
      description: string;
    }>(
      `SELECT mr.id,
              mr.amount::text AS amount,
              mr.billing_cycle,
              mr.units_consumed::text AS units_consumed,
              mr.rate_per_unit::text AS rate_per_unit,
              ('Electricity (' || mr.billing_cycle || ')') AS description
       FROM meter_readings mr
       WHERE mr.tenancy_id = $1
         AND mr.invoice_id IS NULL
         AND COALESCE(mr.amount, 0) > 0
       ORDER BY mr.created_at ASC`,
      [tenancyId],
    );
  }

  /**
   * Attach unpaid utility meter charges (and similar) as line items on an invoice.
   */
  async addPendingChargesToInvoice(
    tenancyId: string,
    invoiceId: string,
  ): Promise<{ added: number; amount: number }> {
    await ensureBillingSchema();

    const [invoice] = await query<{
      id: string;
      tenancy_id: string;
      property_id: string;
    }>(`SELECT id, tenancy_id, property_id FROM invoices WHERE id = $1`, [
      invoiceId,
    ]);
    if (!invoice || invoice.tenancy_id !== tenancyId) {
      throw new Error('Invoice does not belong to this tenancy');
    }

    const pending = await this.listPendingUtilityCharges(tenancyId);
    if (pending.length === 0) return { added: 0, amount: 0 };

    const chargeTypes = await this.listChargeTypes(invoice.property_id);
    const electricity = chargeTypes.find((c: any) =>
      String(c.name).toLowerCase().includes('electric'),
    ) as any;

    let totalAdded = 0;
    for (const row of pending) {
      const amount = Number(row.amount);
      if (!(amount > 0)) continue;

      const [li] = await query<{ id: string }>(
        `INSERT INTO invoice_line_items
           (invoice_id, charge_type_id, description, amount, charge_kind)
         VALUES ($1, $2, $3, $4, 'electricity'::invoice_charge_kind)
         RETURNING id`,
        [
          invoiceId,
          electricity?.id ?? null,
          (() => {
            const units = row.units_consumed != null ? Number(row.units_consumed) : null;
            const rate = row.rate_per_unit != null ? Number(row.rate_per_unit) : null;
            if (units != null && rate != null) {
              return `Electricity (${row.billing_cycle}): ${units} units @ ₹${rate}`;
            }
            return row.description || `Electricity (${row.billing_cycle})`;
          })(),
          amount,
        ],
      );

      await query(
        `UPDATE meter_readings
         SET invoice_id = $1, invoice_line_item_id = $2
         WHERE id = $3`,
        [invoiceId, li.id, row.id],
      );
      totalAdded += amount;
    }

    if (totalAdded > 0) {
      await query(
        `UPDATE invoices
         SET total_amount = total_amount + $1, updated_at = now()
         WHERE id = $2`,
        [totalAdded, invoiceId],
      );
      await this.recomputeStatus(invoiceId);
    }

    return { added: pending.length, amount: totalAdded };
  }

  // ---- Invoices ----

  async createInvoice(input: CreateInvoiceInput) {
    await ensureBillingSchema();

    const periodStartYmd = input.periodStart.slice(0, 10);
    const [duplicate] = await query<{ id: string; sent_at: Date | null }>(
      `SELECT id, sent_at FROM invoices
       WHERE tenancy_id = $1 AND period_start = $2::date
       LIMIT 1`,
      [input.tenancyId, periodStartYmd],
    );
    if (duplicate) {
      const isDraft = duplicate.sent_at == null;
      throw new InvoiceConflictError(
        isDraft
          ? 'A draft invoice for this billing cycle is waiting for your review. Open it from Payments to edit and send it.'
          : 'An invoice for this billing cycle already exists. Open it from Payments to edit it.',
        duplicate.id,
        isDraft,
      );
    }

    const lineItems = [...input.lineItems];

    if (input.includeArrears) {
      const arrears = await this.computeUnbilledArrears(
        input.tenancyId,
        input.periodStart,
      );
      if (arrears.amount > 0 && arrears.description) {
        const already = lineItems.some(
          (li) =>
            li.chargeKind === 'previous_dues' ||
            /previous dues|arrears/i.test(li.description),
        );
        if (!already) {
          lineItems.unshift({
            description: arrears.description,
            amount: arrears.amount,
            chargeKind: 'previous_dues',
          });
        }
      }
    }

    const positiveItems = lineItems.filter((li) => li.amount > 0);
    const willAttachPending = input.includePendingCharges !== false;
    if (positiveItems.length === 0 && !willAttachPending) {
      throw new Error('Add at least one charge with an amount above 0.');
    }

    const totalAmount = positiveItems.reduce((sum, li) => sum + li.amount, 0);

    // Owner-created invoices are confirmed on save, so they go straight to the tenant.
    // Status is corrected by the timezone-aware refresh in getById below.
    let invoice: { id: string };
    try {
      [invoice] = await query<{ id: string }>(
        `INSERT INTO invoices
           (tenancy_id, property_id, period_start, period_end, due_date, total_amount,
            status, sent_at, is_auto_generated)
         VALUES ($1,$2,$3,$4,$5,$6,'pending',now(),false) RETURNING *`,
        [
          input.tenancyId,
          input.propertyId,
          input.periodStart,
          input.periodEnd,
          input.dueDate,
          totalAmount,
        ],
      );
    } catch (err: any) {
      if (err?.code === '23505') {
        throw new Error(
          'An invoice for this billing cycle already exists. Open it from Payments to edit it.',
        );
      }
      throw err;
    }

    const chargeTypes = await this.listChargeTypes(input.propertyId);
    const typeNameById = new Map(
      chargeTypes.map((c: any) => [String(c.id), String(c.name)]),
    );

    for (const li of positiveItems) {
      const kind =
        li.chargeKind ??
        inferChargeKind(
          li.description,
          li.chargeTypeId ? typeNameById.get(li.chargeTypeId) : null,
        );
      await query(
        `INSERT INTO invoice_line_items
           (invoice_id, charge_type_id, description, amount, charge_kind)
         VALUES ($1,$2,$3,$4,$5::invoice_charge_kind)`,
        [
          (invoice as any).id,
          li.chargeTypeId ?? null,
          li.description,
          li.amount,
          kind,
        ],
      );
    }

    if (willAttachPending) {
      await this.addPendingChargesToInvoice(
        input.tenancyId,
        (invoice as any).id,
      ).catch((err) =>
        console.warn('[billing] addPendingChargesToInvoice:', err),
      );
    }

    const finalized = await this.getById((invoice as any).id);
    if (
      finalized &&
      Number((finalized as any).total_amount) <= 0 &&
      (!((finalized as any).lineItems as any[])?.length)
    ) {
      await query(`DELETE FROM invoices WHERE id = $1`, [(invoice as any).id]);
      throw new Error('Add at least one charge with an amount above 0.');
    }
    if (finalized) {
      await this.notifyTenantInvoiceSent(finalized).catch((err) =>
        console.warn('[billing] invoice_sent notification:', err),
      );
    }
    return finalized;
  }

  /**
   * Build the current-cycle invoice: rent + optional arrears + pending utilities.
   */
  async generateMonthlyInvoice(opts: {
    propertyId: string;
    tenancyId: string;
    includeArrears?: boolean;
    includePendingCharges?: boolean;
    periodStart?: string;
    periodEnd?: string;
    dueDate?: string;
  }) {
    await ensureBillingSchema();

    const [tenancy] = await query<{
      id: string;
      property_id: string;
      monthly_rent: string | number | null;
      move_in_at: Date | string | null;
      include_past_rent_arrears: boolean | null;
    }>(
      `SELECT id, property_id, monthly_rent, move_in_at, include_past_rent_arrears
       FROM tenancies WHERE id = $1`,
      [opts.tenancyId],
    );
    if (!tenancy || tenancy.property_id !== opts.propertyId) {
      throw new Error('Tenancy not found in this property');
    }

    const explicitDates = Boolean(
      opts.periodStart && opts.periodEnd && opts.dueDate,
    );
    if (!explicitDates) {
      await this.ensureHostelPgAnniversaryInvoices(
        opts.propertyId,
        opts.tenancyId,
      );
      const [latest] = await query<{ id: string }>(
        `SELECT id FROM invoices
         WHERE tenancy_id = $1 AND property_id = $2
         ORDER BY period_start DESC
         LIMIT 1`,
        [opts.tenancyId, opts.propertyId],
      );
      if (!latest) {
        throw new Error(
          'No billing cycle is due yet. The first bill is generated on the check-in anniversary.',
        );
      }
      return this.getById(latest.id);
    }

    const periodStart = opts.periodStart!.slice(0, 10);
    const periodEnd = opts.periodEnd!.slice(0, 10);
    const dueDate = opts.dueDate!.slice(0, 10);

    const existing = await query<{ id: string }>(
      `SELECT id FROM invoices
       WHERE tenancy_id = $1
         AND period_start = $2::date
         AND period_end = $3::date
       LIMIT 1`,
      [opts.tenancyId, periodStart, periodEnd],
    );
    if (existing[0]) {
      return this.getById(existing[0].id);
    }

    const chargeTypes = await this.listChargeTypes(opts.propertyId);
    const rentType = chargeTypes.find((c: any) => {
      const n = String(c.name).toLowerCase();
      return n === 'rent' || n.includes('rent');
    }) as any;

    const monthlyRent = Number(tenancy.monthly_rent ?? 0);
    const lineItems: LineItemInput[] = [];
    if (monthlyRent > 0) {
      const label = formatMonthLabel(periodStart.slice(0, 7));
      lineItems.push({
        chargeTypeId: rentType?.id,
        description: `${label} Rent`,
        amount: monthlyRent,
        chargeKind: 'rent',
      });
    }

    const includeArrears =
      opts.includeArrears ?? tenancy.include_past_rent_arrears !== false;
    const includePending = opts.includePendingCharges !== false;

    if (lineItems.length === 0) {
      const arrears = includeArrears
        ? await this.computeUnbilledArrears(opts.tenancyId, periodStart)
        : null;
      const pending = includePending
        ? await this.listPendingUtilityCharges(opts.tenancyId)
        : [];
      if ((!arrears || arrears.amount <= 0) && pending.length === 0) {
        throw new Error(
          'Nothing to invoice: set monthly rent, or wait for utility charges.',
        );
      }
    }

    return this.createInvoice({
      tenancyId: opts.tenancyId,
      propertyId: opts.propertyId,
      periodStart,
      periodEnd,
      dueDate,
      lineItems,
      includeArrears,
      includePendingCharges: includePending,
    });
  }

  async updateInvoice(
    invoiceId: string,
    propertyId: string,
    input: UpdateInvoiceInput,
  ) {
    await ensureBillingSchema();

    const [existing] = await query<{ id: string; property_id: string }>(
      `SELECT id, property_id FROM invoices WHERE id = $1`,
      [invoiceId],
    );
    if (!existing) return null;
    if (existing.property_id !== propertyId) return null;

    const totalAmount = input.lineItems.reduce((sum, li) => sum + li.amount, 0);

    try {
      await query(
        `UPDATE invoices
         SET period_start = $1,
             period_end = $2,
             overdue_notified_at = CASE
               WHEN due_date IS DISTINCT FROM $3::date THEN NULL
               ELSE overdue_notified_at
             END,
             due_date = $3,
             total_amount = $4,
             updated_at = now()
         WHERE id = $5 AND property_id = $6`,
        [
          input.periodStart,
          input.periodEnd,
          input.dueDate,
          totalAmount,
          invoiceId,
          propertyId,
        ],
      );
    } catch (err: any) {
      if (err?.code === '23505') {
        throw new Error(
          'Another invoice already covers a billing cycle starting on this date.',
        );
      }
      throw err;
    }

    await query(`DELETE FROM invoice_line_items WHERE invoice_id = $1`, [
      invoiceId,
    ]);

    const chargeTypes = await this.listChargeTypes(propertyId);
    const typeNameById = new Map(
      chargeTypes.map((c: any) => [String(c.id), String(c.name)]),
    );

    for (const li of input.lineItems) {
      const kind =
        li.chargeKind ??
        inferChargeKind(
          li.description,
          li.chargeTypeId ? typeNameById.get(li.chargeTypeId) : null,
        );
      await query(
        `INSERT INTO invoice_line_items
           (invoice_id, charge_type_id, description, amount, charge_kind)
         VALUES ($1,$2,$3,$4,$5::invoice_charge_kind)`,
        [invoiceId, li.chargeTypeId ?? null, li.description, li.amount, kind],
      );
    }

    await this.recomputeStatus(invoiceId);
    return this.getById(invoiceId);
  }

  /**
   * Persist an owner-edited due date. Does not rewrite line items.
   * Later automatic generation will not overwrite this row
   * (invoices are inserted once per cycle).
   */
  async updateDueDate(invoiceId: string, propertyId: string, dueDate: string) {
    const due = dueDate.slice(0, 10);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(due)) {
      throw new Error('Due date must be YYYY-MM-DD.');
    }

    const [existing] = await query<{ id: string }>(
      `SELECT id FROM invoices WHERE id = $1 AND property_id = $2`,
      [invoiceId, propertyId],
    );
    if (!existing) return null;

    await query(
      `UPDATE invoices
       SET overdue_notified_at = CASE
             WHEN due_date IS DISTINCT FROM $1::date THEN NULL
             ELSE overdue_notified_at
           END,
           due_date = $1::date,
           updated_at = now()
       WHERE id = $2 AND property_id = $3`,
      [due, invoiceId, propertyId],
    );
    await this.refreshHostelInvoiceStatuses(propertyId, invoiceId);
    return this.getById(invoiceId);
  }

  /**
   * Create missing rent invoices for completed check-in anniversaries.
   * Applies to every property type.
   * Existing invoices (including owner-edited due dates) are left unchanged.
   */
  async ensureHostelPgAnniversaryInvoices(
    propertyId: string,
    onlyTenancyId?: string,
  ): Promise<number> {
    await ensureBillingSchema();

    const [property] = await query<{ timezone: string | null }>(
      `SELECT timezone FROM properties WHERE id = $1`,
      [propertyId],
    );
    const timeZone = hostelBillingTimeZone(property?.timezone);
    let today: string;
    try {
      today = calendarDateInTimeZone(new Date(), timeZone);
    } catch {
      today = calendarDateInTimeZone(new Date(), 'Asia/Kolkata');
    }

    const tenancies = await query<{
      id: string;
      full_name: string | null;
      monthly_rent: string | number | null;
      move_in_at: Date | string | null;
      move_out_at: Date | string | null;
      status: string | null;
    }>(
      `SELECT id, full_name, monthly_rent, move_in_at, move_out_at, status
       FROM tenancies
       WHERE property_id = $1
         AND ($2::uuid IS NULL OR id = $2::uuid)`,
      [propertyId, onlyTenancyId ?? null],
    );

    const chargeTypes = await this.listChargeTypes(propertyId);
    const rentType = chargeTypes.find((c: any) => {
      const n = String(c.name).toLowerCase();
      return n === 'rent' || n.includes('rent');
    }) as { id?: string } | undefined;

    let created = 0;
    for (const tenancy of tenancies) {
      if (String(tenancy.status ?? 'active') === 'ended') continue;
      if (!tenancy.move_in_at) continue;
      const rent = Number(tenancy.monthly_rent ?? 0);
      if (!(rent > 0)) continue;

      const moveIn = new Date(tenancy.move_in_at);
      if (Number.isNaN(moveIn.getTime())) continue;
      let checkIn: string;
      try {
        checkIn = calendarDateInTimeZone(moveIn, timeZone);
      } catch {
        checkIn = calendarDateInTimeZone(moveIn, 'Asia/Kolkata');
      }

      let moveOut: string | null = null;
      if (tenancy.move_out_at) {
        const out = new Date(tenancy.move_out_at);
        if (!Number.isNaN(out.getTime())) {
          try {
            moveOut = calendarDateInTimeZone(out, timeZone);
          } catch {
            moveOut = calendarDateInTimeZone(out, 'Asia/Kolkata');
          }
        }
      }

      const existing = await query<{ period_start: Date | string }>(
        `SELECT period_start FROM invoices WHERE tenancy_id = $1`,
        [tenancy.id],
      );
      const existingStarts = new Set(
        existing.map((row) => dbDateToYmd(row.period_start)),
      );

      const drafts: { id: string; periodStart: string; periodEnd: string }[] = [];
      for (const cycle of hostelCyclesDue(checkIn, today)) {
        if (moveOut && compareYmd(cycle.billDate, moveOut) > 0) continue;
        if (existingStarts.has(cycle.periodStart)) continue;

        const label = formatMonthLabel(cycle.periodStart.slice(0, 7));
        const initialStatus =
          compareYmd(cycle.dueDate, today) < 0 ? 'overdue' : 'pending';

        // Draft (sent_at NULL): hidden from the tenant until the owner sends it.
        // NOT EXISTS + the unique (tenancy_id, period_start) index make retries safe.
        let inserted: { id: string }[];
        try {
          inserted = await query<{ id: string }>(
            `INSERT INTO invoices
               (tenancy_id, property_id, period_start, period_end, due_date, total_amount,
                status, sent_at, is_auto_generated)
             SELECT $1, $2, $3::date, $4::date, $5::date, $6, $7::invoice_status, NULL, true
             WHERE NOT EXISTS (
               SELECT 1 FROM invoices
               WHERE tenancy_id = $1 AND period_start = $3::date
             )
             RETURNING id`,
            [
              tenancy.id,
              propertyId,
              cycle.periodStart,
              cycle.periodEnd,
              cycle.dueDate,
              rent,
              initialStatus,
            ],
          );
        } catch (err: any) {
          if (err?.code === '23505') continue;
          throw err;
        }
        const invoiceId = inserted[0]?.id;
        if (!invoiceId) continue;

        await query(
          `INSERT INTO invoice_line_items
             (invoice_id, charge_type_id, description, amount, charge_kind)
           VALUES ($1, $2, $3, $4, 'rent'::invoice_charge_kind)`,
          [invoiceId, rentType?.id ?? null, `${label} Rent`, rent],
        );
        await this.addPendingChargesToInvoice(tenancy.id, invoiceId).catch((err) =>
          console.warn('[billing] attach pending charges to draft:', err),
        );
        existingStarts.add(cycle.periodStart);
        drafts.push({
          id: invoiceId,
          periodStart: cycle.periodStart,
          periodEnd: cycle.periodEnd,
        });
        created += 1;
      }

      if (drafts.length > 0) {
        await this.notifyOwnersDraftsReady(
          propertyId,
          tenancy.id,
          tenancy.full_name ?? 'Tenant',
          drafts,
        ).catch((err) => console.warn('[billing] draft-ready notification:', err));
      }
    }

    return created;
  }

  private async notifyOwnersDraftsReady(
    propertyId: string,
    tenancyId: string,
    tenantName: string,
    drafts: { id: string; periodStart: string; periodEnd: string }[],
  ) {
    const latest = drafts[drafts.length - 1];
    const body =
      drafts.length === 1
        ? `${tenantName}'s invoice for ${formatShortDate(latest.periodStart)} – ${formatShortDate(latest.periodEnd)} is ready. Review rent, utilities and due date, then send it.`
        : `${drafts.length} invoices for ${tenantName} are ready (up to ${formatShortDate(latest.periodEnd)}). Review and send them.`;
    await notifyPropertyOwners({
      propertyId,
      type: 'invoice_draft_ready',
      title: 'Invoice ready for review',
      body,
      data: {
        route: '/invoice-review',
        invoice_id: latest.id,
        invoiceId: latest.id,
        tenancy_id: tenancyId,
        tenancyId,
        property_id: propertyId,
        propertyId,
        draft_count: drafts.length,
      },
    });
  }

  /** Overdue starts the calendar day after the saved due_date. */
  async refreshHostelInvoiceStatuses(propertyId: string, invoiceId?: string) {
    const [property] = await query<{ timezone: string | null }>(
      `SELECT timezone FROM properties WHERE id = $1`,
      [propertyId],
    );
    const timeZone = hostelBillingTimeZone(property?.timezone);
    let today: string;
    try {
      today = calendarDateInTimeZone(new Date(), timeZone);
    } catch {
      today = calendarDateInTimeZone(new Date(), 'Asia/Kolkata');
    }

    await query(
      `UPDATE invoices i
       SET status = v.new_status::invoice_status,
           updated_at = now()
       FROM (
         SELECT i2.id,
           CASE
             WHEN COALESCE(SUM(p.amount), 0) >= i2.total_amount
                  AND i2.total_amount > 0 THEN 'paid'
             WHEN COALESCE(SUM(p.amount), 0) > 0 THEN 'partial'
             WHEN i2.due_date < $2::date THEN 'overdue'
             ELSE 'pending'
           END AS new_status
         FROM invoices i2
         LEFT JOIN payments p ON p.invoice_id = i2.id
         WHERE i2.property_id = $1
           AND ($3::uuid IS NULL OR i2.id = $3::uuid)
         GROUP BY i2.id
       ) v
       WHERE i.id = v.id
         AND i.status::text IS DISTINCT FROM v.new_status`,
      [propertyId, today, invoiceId ?? null],
    );
  }

  /**
   * Scheduled run: create draft invoices for completed cycles, refresh statuses,
   * then send each overdue notice once. Safe to run repeatedly.
   */
  async ensureAllHostelPgAnniversaryInvoices(): Promise<number> {
    const properties = await query<{ id: string }>(
      `SELECT id FROM properties`,
    );
    let created = 0;
    for (const property of properties) {
      try {
        created += await this.ensureHostelPgAnniversaryInvoices(property.id);
        await this.refreshHostelInvoiceStatuses(property.id);
        await this.notifyOverdueInvoices(property.id);
      } catch (err) {
        console.error(`[billing] scheduled run failed for property ${property.id}:`, err);
      }
    }
    return created;
  }

  /**
   * One overdue notice per sent invoice (tenant + owners). The row is claimed
   * by setting overdue_notified_at first, so concurrent runs cannot double-send.
   * Changing the due date clears the marker (see updateDueDate / updateInvoice).
   */
  async notifyOverdueInvoices(propertyId: string): Promise<number> {
    const today = await this.propertyToday(propertyId);
    const claimed = await query<{
      id: string;
      tenancy_id: string;
      due_date: Date | string;
      balance: string;
      user_id: string;
      full_name: string | null;
    }>(
      `UPDATE invoices i
       SET overdue_notified_at = now()
       FROM tenancies t
       WHERE t.id = i.tenancy_id
         AND i.property_id = $1
         AND i.sent_at IS NOT NULL
         AND i.overdue_notified_at IS NULL
         AND i.due_date < $2::date
         AND i.total_amount > COALESCE(
           (SELECT SUM(p.amount) FROM payments p WHERE p.invoice_id = i.id), 0)
       RETURNING i.id, i.tenancy_id, i.due_date::text AS due_date,
         (i.total_amount - COALESCE(
           (SELECT SUM(p.amount) FROM payments p WHERE p.invoice_id = i.id), 0))::text AS balance,
         t.user_id, t.full_name`,
      [propertyId, today],
    );

    for (const row of claimed) {
      const due = formatShortDate(String(row.due_date));
      const balance = Number(row.balance);
      const name = row.full_name ?? 'Tenant';
      const ids = {
        invoice_id: row.id,
        invoiceId: row.id,
        tenancy_id: row.tenancy_id,
        tenancyId: row.tenancy_id,
        property_id: propertyId,
        propertyId,
        amount_due: balance,
      };
      await createNotification({
        userId: row.user_id,
        propertyId,
        type: 'invoice_overdue',
        title: 'Payment overdue',
        body: `Your payment of ₹${balance} was due on ${due}. Please pay as soon as possible.`,
        data: { route: '/tenant/dashboard?focus=payments', ...ids },
      });
      await notifyPropertyOwners({
        propertyId,
        type: 'invoice_overdue_owner',
        title: 'Rent overdue',
        body: `${name} has ₹${balance} overdue (due ${due}).`,
        data: { route: '/tenant-profile', ...ids },
      }).catch((err) => console.warn('[billing] owner overdue notification:', err));
    }
    return claimed.length;
  }

  /**
   * Owner confirms a draft: mark it sent and notify the tenant.
   * Idempotent — a second call returns the invoice without re-notifying.
   */
  async sendInvoice(invoiceId: string, propertyId: string) {
    await ensureBillingSchema();
    const [existing] = await query<{ id: string; total_amount: string }>(
      `SELECT id, total_amount FROM invoices WHERE id = $1 AND property_id = $2`,
      [invoiceId, propertyId],
    );
    if (!existing) return null;
    if (!(Number(existing.total_amount) > 0)) {
      throw new Error('Add at least one charge with an amount above 0 before sending.');
    }

    const today = await this.propertyToday(propertyId);
    // If the due date has already passed, the "sent" notice itself says so,
    // so the scheduled overdue notice is not sent a second time.
    const sent = await query<{ id: string }>(
      `UPDATE invoices
       SET sent_at = now(),
           overdue_notified_at = CASE
             WHEN due_date < $3::date THEN now()
             ELSE overdue_notified_at
           END,
           updated_at = now()
       WHERE id = $1 AND property_id = $2 AND sent_at IS NULL
       RETURNING id`,
      [invoiceId, propertyId, today],
    );

    const invoice = await this.getById(invoiceId);
    if (sent.length > 0 && invoice) {
      await this.notifyTenantInvoiceSent(invoice).catch((err) =>
        console.warn('[billing] invoice_sent notification:', err),
      );
    }
    return invoice ? { ...invoice, newly_sent: sent.length > 0 } : null;
  }

  private async notifyTenantInvoiceSent(invoice: any) {
    const [row] = await query<{
      user_id: string;
      due_date: string;
      period_start: string;
      period_end: string;
    }>(
      `SELECT t.user_id, i.due_date::text AS due_date,
              i.period_start::text AS period_start, i.period_end::text AS period_end
       FROM invoices i JOIN tenancies t ON t.id = i.tenancy_id
       WHERE i.id = $1`,
      [invoice.id],
    );
    if (!row) return;
    const tenancy = { user_id: row.user_id };
    const total = Number(invoice.total_amount ?? 0);
    const balance = total - Number(invoice.paid_amount ?? 0);
    const dueYmd = row.due_date;
    const periodStart = row.period_start;
    const periodEnd = row.period_end;
    const today = await this.propertyToday(String(invoice.property_id));
    const pastDue = compareYmd(dueYmd, today) < 0;
    await createNotification({
      userId: tenancy.user_id,
      propertyId: invoice.property_id,
      type: 'invoice_sent',
      title: pastDue ? 'New invoice — payment overdue' : 'New invoice',
      body: `Invoice for ${formatShortDate(periodStart)} – ${formatShortDate(periodEnd)}: ₹${balance}. ${
        pastDue ? 'It was due on' : 'Due by'
      } ${formatShortDate(dueYmd)}.`,
      data: {
        route: '/tenant/dashboard?focus=payments',
        invoice_id: invoice.id,
        invoiceId: invoice.id,
        tenancy_id: invoice.tenancy_id,
        tenancyId: invoice.tenancy_id,
        property_id: invoice.property_id,
        propertyId: invoice.property_id,
        amount_due: balance,
      },
    });
  }

  private async propertyToday(propertyId: string): Promise<string> {
    const [property] = await query<{ timezone: string | null }>(
      `SELECT timezone FROM properties WHERE id = $1`,
      [propertyId],
    );
    try {
      return calendarDateInTimeZone(new Date(), hostelBillingTimeZone(property?.timezone));
    } catch {
      return calendarDateInTimeZone(new Date(), 'Asia/Kolkata');
    }
  }

  async getById(invoiceId: string) {
    await ensureBillingSchema();
    const [invoice] = await query<any>(
      `SELECT * FROM invoices WHERE id = $1`,
      [invoiceId],
    );
    if (!invoice) return null;
    await this.refreshHostelInvoiceStatuses(String(invoice.property_id), invoiceId);
    const [fresh] = await query<any>(
      `SELECT i.*, t.full_name, u.phone
       FROM invoices i
       LEFT JOIN tenancies t ON t.id = i.tenancy_id
       LEFT JOIN users u ON u.id = t.user_id
       WHERE i.id = $1`,
      [invoiceId],
    );
    if (fresh) Object.assign(invoice, fresh);
    const lineItems = await query(
      `SELECT ili.*, ct.name AS charge_type_name
       FROM invoice_line_items ili
       LEFT JOIN charge_types ct ON ct.id = ili.charge_type_id
       WHERE ili.invoice_id = $1
       ORDER BY
         CASE ili.charge_kind
           WHEN 'previous_dues' THEN 0
           WHEN 'rent' THEN 1
           WHEN 'electricity' THEN 2
           WHEN 'maintenance' THEN 3
           ELSE 4
         END,
         ili.description`,
      [invoiceId],
    );
    const payments = await query<any>(
      `SELECT * FROM payments WHERE invoice_id = $1 ORDER BY paid_at DESC`,
      [invoiceId],
    );
    const paidAmount = payments.reduce((sum, p) => sum + Number(p.amount ?? 0), 0);
    return { ...invoice, paid_amount: paidAmount, lineItems, payments };
  }

  async listByProperty(propertyId: string) {
    await this.ensureHostelPgAnniversaryInvoices(propertyId).catch((err) =>
      console.warn('[billing] anniversary invoices:', err),
    );
    await this.refreshHostelInvoiceStatuses(propertyId).catch((err) =>
      console.warn('[billing] status refresh:', err),
    );
    return query(
      `SELECT i.*, t.full_name, t.profile_photo_url, u.phone, n.name AS node_name,
              floor_node.name AS floor_name,
              COALESCE((SELECT SUM(amount) FROM payments WHERE invoice_id = i.id), 0) AS paid_amount
       FROM invoices i
       JOIN tenancies t ON t.id = i.tenancy_id
       JOIN users u ON u.id = t.user_id
       JOIN hierarchy_nodes n ON n.id = t.node_id
       LEFT JOIN LATERAL (
         WITH RECURSIVE ancestors AS (
           SELECT hn.id, hn.name, hn.parent_node_id, hn.level_id
           FROM hierarchy_nodes hn
           WHERE hn.id = n.id
           UNION ALL
           SELECT p.id, p.name, p.parent_node_id, p.level_id
           FROM hierarchy_nodes p
           INNER JOIN ancestors a ON p.id = a.parent_node_id
         )
         SELECT a.name
         FROM ancestors a
         JOIN hierarchy_levels hl ON hl.id = a.level_id
         WHERE lower(hl.display_name) LIKE '%floor%'
         LIMIT 1
       ) floor_node ON true
       WHERE i.property_id = $1
       ORDER BY i.due_date DESC`,
      [propertyId],
    );
  }

  async receivedThisMonth(propertyId: string) {
    const [row] = await query<{ received: string }>(
      `SELECT COALESCE(SUM(p.amount), 0)::text AS received
       FROM payments p
       INNER JOIN invoices i ON i.id = p.invoice_id
       WHERE i.property_id = $1
         AND p.paid_at >= date_trunc('month', now())
         AND p.paid_at < date_trunc('month', now()) + interval '1 month'`,
      [propertyId],
    );
    return Number(row?.received ?? 0);
  }

  async listPaymentsByProperty(propertyId: string) {
    return query(
      `SELECT p.id,
              p.invoice_id,
              p.amount,
              p.method,
              p.note,
              p.paid_at,
              i.tenancy_id,
              t.full_name,
              n.name AS node_name,
              floor_node.name AS floor_name
       FROM payments p
       INNER JOIN invoices i ON i.id = p.invoice_id
       INNER JOIN tenancies t ON t.id = i.tenancy_id
       INNER JOIN hierarchy_nodes n ON n.id = t.node_id
       LEFT JOIN LATERAL (
         WITH RECURSIVE ancestors AS (
           SELECT hn.id, hn.name, hn.parent_node_id, hn.level_id
           FROM hierarchy_nodes hn
           WHERE hn.id = n.id
           UNION ALL
           SELECT pr.id, pr.name, pr.parent_node_id, pr.level_id
           FROM hierarchy_nodes pr
           INNER JOIN ancestors a ON pr.id = a.parent_node_id
         )
         SELECT a.name
         FROM ancestors a
         JOIN hierarchy_levels hl ON hl.id = a.level_id
         WHERE lower(hl.display_name) LIKE '%floor%'
         LIMIT 1
       ) floor_node ON true
       WHERE i.property_id = $1
       ORDER BY p.paid_at DESC`,
      [propertyId],
    );
  }

  async listByTenancy(tenancyId: string) {
    await ensureBillingSchema();
    const invoices = await query<any>(
      `SELECT i.*,
              COALESCE((SELECT SUM(amount) FROM payments WHERE invoice_id = i.id), 0) AS paid_amount
       FROM invoices i
       WHERE i.tenancy_id = $1
         AND i.sent_at IS NOT NULL
       ORDER BY i.due_date DESC`,
      [tenancyId],
    );

    if (invoices.length === 0) return [];

    const ids = invoices.map((i) => i.id);
    const lineItems = await query<any>(
      `SELECT ili.*, ct.name AS charge_type_name
       FROM invoice_line_items ili
       LEFT JOIN charge_types ct ON ct.id = ili.charge_type_id
       WHERE ili.invoice_id = ANY($1::uuid[])
       ORDER BY ili.invoice_id,
         CASE ili.charge_kind
           WHEN 'previous_dues' THEN 0
           WHEN 'rent' THEN 1
           WHEN 'electricity' THEN 2
           WHEN 'maintenance' THEN 3
           ELSE 4
         END,
         ili.description`,
      [ids],
    );

    const byInvoice = new Map<string, any[]>();
    for (const li of lineItems) {
      const key = String(li.invoice_id);
      if (!byInvoice.has(key)) byInvoice.set(key, []);
      byInvoice.get(key)!.push(li);
    }

    return invoices.map((inv) => ({
      ...inv,
      lineItems: byInvoice.get(String(inv.id)) ?? [],
    }));
  }

  async recordPayment(
    invoiceId: string,
    amount: number,
    method: string,
    note: string | undefined,
    recordedBy: string,
  ) {
    await query(
      `INSERT INTO payments (invoice_id, amount, method, note, recorded_by) VALUES ($1,$2,$3,$4,$5)`,
      [invoiceId, amount, method, note ?? null, recordedBy],
    );
    await this.recomputeStatus(invoiceId);
    return this.getById(invoiceId);
  }

  /** Same rules as refreshHostelInvoiceStatuses, in the property's local calendar. */
  private async recomputeStatus(invoiceId: string) {
    const [invoice] = await query<{ property_id: string }>(
      `SELECT property_id FROM invoices WHERE id = $1`,
      [invoiceId],
    );
    if (!invoice) return;
    await this.refreshHostelInvoiceStatuses(invoice.property_id, invoiceId);
  }

  async sendReminder(invoiceId: string) {
    const invoice = await this.getById(invoiceId);
    if (!invoice) throw new Error('Invoice not found');
    if ((invoice as any).sent_at == null) {
      throw new Error('This invoice is still a draft. Send it to the tenant first.');
    }

    const [tenancy] = await query<any>(
      `SELECT t.user_id, t.full_name, u.phone
       FROM tenancies t JOIN users u ON u.id = t.user_id
       WHERE t.id = $1`,
      [(invoice as any).tenancy_id],
    );

    const paidAmount = Number((invoice as any).paid_amount ?? 0);
    const pending = Number((invoice as any).total_amount) - paidAmount;
    const title = 'Rent Reminder';
    const body = `Hi ${tenancy.full_name}, your payment of ₹${pending} is due on ${
      new Date((invoice as any).due_date).toLocaleDateString()
    }. Please pay as soon as possible.`;
    const payload = JSON.stringify({
      route: '/tenant/dashboard?focus=payments',
      invoice_id: invoiceId,
      invoiceId,
      tenancy_id: (invoice as any).tenancy_id,
      tenancyId: (invoice as any).tenancy_id,
      property_id: (invoice as any).property_id,
      propertyId: (invoice as any).property_id,
      amount_due: pending,
    });

    try {
      await query(
        `INSERT INTO notifications (user_id, property_id, type, title, body, data)
         VALUES ($1,$2,'rent_reminder',$3,$4,$5::jsonb)`,
        [tenancy.user_id, (invoice as any).property_id, title, body, payload],
      );
    } catch {
      await query(
        `INSERT INTO notifications (user_id, property_id, type, title, body)
         VALUES ($1,$2,'rent_reminder',$3,$4)`,
        [tenancy.user_id, (invoice as any).property_id, title, body],
      );
    }

    // eslint-disable-next-line no-console
    console.log(`[REMINDER] -> ${tenancy.phone}: ${title} — ${body}`);
    return { sent: true };
  }
}
