// modules/search/search.service.ts
//
// Role-scoped global search. The property / tenancy scope is resolved here
// from the verified token context only — never from client input — and every
// category query filters on that scope in SQL, with a LIMIT, inside one
// read-only transaction that has a statement timeout.

import { withTransaction, type TxQuery } from '@config/db';
import { INVOICE_BALANCE_SQL, clockFor, overdueInvoiceSql } from '@modules/billing/billing-metrics';
import { complaintSchemaCaps } from '@modules/complaints/complaint.service';
import { isFeatureAllowed } from '@modules/tenant-portal/property-type-access';
import {
  SearchRequestError,
  serializeHit,
  type SearchCategory,
  type SearchFilter,
  type SearchHit,
  type SearchRole,
} from './search.policy';

export const SEARCH_STATEMENT_TIMEOUT_MS = 3000;
/** Upper bound on properties an organization-wide search spans. */
export const MAX_SCOPE_PROPERTIES = 500;

export interface SearchContext {
  userId: string;
  role: SearchRole;
  ctxType: 'organization' | 'tenancy' | undefined;
  ctxId: string;
  ctxPropertyId: string | null;
}

export interface SearchRequest {
  text: string;
  categories: SearchCategory[];
  filter: SearchFilter | null;
  limit: number;
}

interface ScopeProperty {
  id: string;
  name: string;
  type: string | null;
  today: string;
}

type Scope =
  | { kind: 'team'; role: Exclude<SearchRole, 'tenant'>; userId: string; properties: ScopeProperty[] }
  | { kind: 'tenant'; userId: string; tenancyId: string; nodeId: string | null; property: ScopeProperty };

interface Terms {
  text: string;
  /** `%text%`, LIKE-escaped; null when only a filter is applied. */
  contains: string | null;
  /** `text%`, LIKE-escaped, for ranking prefix matches first. */
  prefix: string | null;
  /** `%digits%` for phone lookup, only for roles allowed to see phones. */
  digits: string | null;
  filter: SearchFilter | null;
  limit: number;
}

/** Collects positional parameters so each query reads top to bottom. */
class Params {
  readonly values: unknown[] = [];
  add(value: unknown): string {
    this.values.push(value);
    return `$${this.values.length}`;
  }
}

export function escapeLike(text: string): string {
  return text.replace(/[\\%_]/g, (c) => `\\${c}`);
}

const PHONE_ROLES = new Set<SearchRole>(['owner', 'admin', 'manager']);
const BILLING_ROLES = new Set<SearchRole>(['owner', 'admin', 'manager']);
const DAY_NAMES = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const DAY_NAME_SQL = `(ARRAY['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'])[m.day_of_week]`;

function buildTerms(request: SearchRequest, role: SearchRole): Terms {
  const text = request.text;
  const hasText = text.length > 0;
  const digitsOnly = text.replace(/\D/g, '');
  const phoneLike = /^[\d\s+()-]+$/.test(text) && digitsOnly.length >= 3;
  return {
    text,
    contains: hasText ? `%${escapeLike(text)}%` : null,
    prefix: hasText ? `${escapeLike(text)}%` : null,
    digits: hasText && phoneLike && PHONE_ROLES.has(role) ? `%${digitsOnly}%` : null,
    filter: request.filter,
    limit: request.limit,
  };
}

function money(value: string | number | null | undefined): number | null {
  if (value === null || value === undefined) return null;
  const n = Number(value);
  return Number.isFinite(n) ? Math.round(n * 100) / 100 : null;
}

function joinParts(parts: (string | null | undefined)[]): string | null {
  const kept = parts.map((p) => (p ?? '').trim()).filter((p) => p.length > 0);
  return kept.length ? kept.join(' · ') : null;
}

function snippet(text: string | null | undefined, max = 80): string | null {
  const flat = (text ?? '').replace(/\s+/g, ' ').trim();
  if (!flat) return null;
  return flat.length > max ? `${flat.slice(0, max - 1)}…` : flat;
}

function isoDate(value: unknown): string | null {
  if (value === null || value === undefined) return null;
  if (value instanceof Date) return Number.isNaN(value.getTime()) ? null : value.toISOString();
  return String(value);
}

function notAvailable(): SearchRequestError {
  return new SearchRequestError(403, 'search_not_available', 'Search is not available for this workspace.');
}

async function resolveScope(q: TxQuery, ctx: SearchContext): Promise<Scope> {
  type PropertyRow = { id: string; name: string; property_type_key: string | null; timezone: string | null };
  const toScope = (row: PropertyRow): ScopeProperty => ({
    id: row.id,
    name: row.name,
    type: row.property_type_key,
    today: clockFor(row.timezone).today,
  });

  if (ctx.role === 'tenant') {
    if (ctx.ctxType !== 'tenancy' || !ctx.ctxPropertyId) throw notAvailable();
    const [row] = await q<PropertyRow & { tenancy_id: string; node_id: string | null }>(
      `SELECT t.id AS tenancy_id, t.node_id, p.id, p.name, p.property_type_key, p.timezone
         FROM tenancies t
         JOIN properties p ON p.id = t.property_id
        WHERE t.id = $1 AND t.user_id = $2 AND t.property_id = $3 AND t.status = 'active'`,
      [ctx.ctxId, ctx.userId, ctx.ctxPropertyId],
    );
    if (!row) throw notAvailable();
    return {
      kind: 'tenant',
      userId: ctx.userId,
      tenancyId: row.tenancy_id,
      nodeId: row.node_id,
      property: toScope(row),
    };
  }

  if (ctx.ctxType !== 'organization') throw notAvailable();

  if (ctx.role === 'owner' || ctx.role === 'admin') {
    if (ctx.ctxPropertyId) throw notAvailable();
    const rows = await q<PropertyRow>(
      `SELECT id, name, property_type_key, timezone
         FROM properties
        WHERE organization_id = $1
        ORDER BY name
        LIMIT ${MAX_SCOPE_PROPERTIES}`,
      [ctx.ctxId],
    );
    return { kind: 'team', role: ctx.role, userId: ctx.userId, properties: rows.map(toScope) };
  }

  // Manager / staff contexts are bound to exactly one assigned property.
  if (!ctx.ctxPropertyId || ctx.ctxPropertyId !== ctx.ctxId) throw notAvailable();
  const rows = await q<PropertyRow>(
    `SELECT p.id, p.name, p.property_type_key, p.timezone
       FROM properties p
       JOIN property_staff_assignments psa
         ON psa.property_id = p.id AND psa.user_id = $2 AND psa.role = $3 AND psa.status = 'active'
      WHERE p.id = $1`,
    [ctx.ctxPropertyId, ctx.userId, ctx.role],
  );
  if (!rows.length) throw notAvailable();
  return { kind: 'team', role: ctx.role, userId: ctx.userId, properties: rows.map(toScope) };
}

type Provider = (q: TxQuery, scope: Scope, terms: Terms) => Promise<SearchHit[]>;

function propertyLookup(scope: Scope): (id: string) => ScopeProperty | undefined {
  const list = scope.kind === 'team' ? scope.properties : [scope.property];
  const byId = new Map(list.map((p) => [p.id, p]));
  return (id) => byId.get(id);
}

function scopeIds(scope: Scope): string[] {
  return scope.kind === 'team' ? scope.properties.map((p) => p.id) : [scope.property.id];
}

function baseHit(
  category: SearchCategory,
  id: string,
  propertyId: string,
  scope: Scope,
): Pick<SearchHit, 'category' | 'id' | 'propertyId' | 'propertyName' | 'propertyType'> {
  const property = propertyLookup(scope)(propertyId);
  return {
    category,
    id,
    propertyId,
    propertyName: property?.name ?? null,
    propertyType: property?.type ?? null,
  };
}

const searchProperties: Provider = async (q, scope, terms) => {
  if (scope.kind !== 'team' || !terms.contains) return [];
  const p = new Params();
  const ids = p.add(scopeIds(scope));
  const contains = p.add(terms.contains);
  const prefix = p.add(terms.prefix);
  const limit = p.add(terms.limit);
  const rows = await q<{ id: string; name: string; city: string | null; state: string | null }>(
    `SELECT pr.id, pr.name, pr.city, pr.state
       FROM properties pr
      WHERE pr.id = ANY(${ids}::uuid[])
        AND (pr.name ILIKE ${contains} OR pr.city ILIKE ${contains} OR pr.address ILIKE ${contains})
      ORDER BY (pr.name ILIKE ${prefix}) DESC, pr.name
      LIMIT ${limit}`,
    p.values,
  );
  return rows.map((r) => ({
    ...baseHit('properties', r.id, r.id, scope),
    title: r.name,
    subtitle: joinParts([r.city, r.state]),
    status: null,
  }));
};

// A "room" is a space a tenant can occupy (bed / flat / unit level) or the
// direct parent of one (a hostel room holding beds) — not buildings or floors.
const SPACE_LEVEL_SQL = `(l.supports_occupancy OR EXISTS (
    SELECT 1 FROM hierarchy_levels cl WHERE cl.parent_level_id = l.id AND cl.supports_occupancy))`;

const OCCUPIED_SQL = `EXISTS (
    SELECT 1 FROM tenancies ot
     WHERE ot.status = 'active' AND ot.property_id = n.property_id
       AND (ot.node_id = n.id
            OR ot.node_id IN (SELECT c.id FROM hierarchy_nodes c WHERE c.parent_node_id = n.id)))`;

const searchRooms: Provider = async (q, scope, terms) => {
  if (scope.kind === 'tenant') return searchOwnStay(q, scope, terms);
  const p = new Params();
  const ids = p.add(scopeIds(scope));
  const contains = p.add(terms.contains);
  const prefix = p.add(terms.prefix);
  const limit = p.add(terms.limit);
  const vacantOnly = terms.filter === 'vacant';
  const rows = await q<{
    id: string;
    property_id: string;
    name: string;
    level_name: string | null;
    parent_name: string | null;
    occupied: boolean;
    tenant_name: string | null;
  }>(
    `SELECT * FROM (
       SELECT n.id, n.property_id, n.name, l.display_name AS level_name, parent.name AS parent_name,
              ${OCCUPIED_SQL} AS occupied,
              (SELECT COALESCE(NULLIF(tt.full_name, ''), tu.name)
                 FROM tenancies tt LEFT JOIN users tu ON tu.id = tt.user_id
                WHERE tt.status = 'active' AND tt.node_id = n.id
                ORDER BY tt.created_at DESC LIMIT 1) AS tenant_name
         FROM hierarchy_nodes n
         JOIN hierarchy_levels l ON l.id = n.level_id
         LEFT JOIN hierarchy_nodes parent ON parent.id = n.parent_node_id
        WHERE n.property_id = ANY(${ids}::uuid[])
          AND n.is_active
          AND ${SPACE_LEVEL_SQL}
          AND (${contains}::text IS NULL
               OR n.name ILIKE ${contains} OR n.code ILIKE ${contains} OR parent.name ILIKE ${contains})
     ) rooms
     ${vacantOnly ? 'WHERE NOT rooms.occupied' : ''}
     ORDER BY (${prefix}::text IS NOT NULL AND rooms.name ILIKE ${prefix}) DESC, rooms.name
     LIMIT ${limit}`,
    p.values,
  );
  return rows.map((r) => ({
    ...baseHit('rooms', r.id, r.property_id, scope),
    nodeId: r.id,
    levelName: r.level_name,
    title: r.name,
    subtitle: joinParts([r.level_name, r.parent_name, r.occupied ? r.tenant_name : null]),
    status: r.occupied ? 'occupied' : 'vacant',
  }));
};

async function searchOwnStay(
  q: TxQuery,
  scope: Extract<Scope, { kind: 'tenant' }>,
  terms: Terms,
): Promise<SearchHit[]> {
  if (!scope.nodeId || !terms.contains) return [];
  const p = new Params();
  const node = p.add(scope.nodeId);
  const property = p.add(scope.property.id);
  const contains = p.add(terms.contains);
  const propertyName = p.add(scope.property.name);
  const rows = await q<{
    id: string;
    name: string;
    level_name: string | null;
    parent_name: string | null;
    grandparent_name: string | null;
  }>(
    `SELECT n.id, n.name, l.display_name AS level_name,
            pn.name AS parent_name, gpn.name AS grandparent_name
       FROM hierarchy_nodes n
       LEFT JOIN hierarchy_levels l ON l.id = n.level_id
       LEFT JOIN hierarchy_nodes pn ON pn.id = n.parent_node_id
       LEFT JOIN hierarchy_nodes gpn ON gpn.id = pn.parent_node_id
      WHERE n.id = ${node} AND n.property_id = ${property}
        AND (n.name ILIKE ${contains} OR l.display_name ILIKE ${contains}
             OR pn.name ILIKE ${contains} OR gpn.name ILIKE ${contains}
             OR ${propertyName}::text ILIKE ${contains})`,
    p.values,
  );
  return rows.map((r) => ({
    ...baseHit('rooms', r.id, scope.property.id, scope),
    nodeId: r.id,
    levelName: r.level_name,
    title: r.name,
    subtitle: joinParts([r.level_name, r.parent_name, r.grandparent_name]),
    status: null,
  }));
}

const searchTenants: Provider = async (q, scope, terms) => {
  if (scope.kind !== 'team') return [];
  const overdueOnly = terms.filter === 'overdue';
  if (overdueOnly && !BILLING_ROLES.has(scope.role)) return [];
  const withPhone = PHONE_ROLES.has(scope.role);
  const p = new Params();
  const ids = p.add(scopeIds(scope));
  const contains = p.add(terms.contains);
  const prefix = p.add(terms.prefix);
  const digits = withPhone ? p.add(terms.digits) : null;
  const limit = p.add(terms.limit);
  const checkedOutOnly = terms.filter === 'checked_out';
  const overdueJoin = overdueOnly
    ? `JOIN (
         SELECT i.tenancy_id, SUM(${INVOICE_BALANCE_SQL}) AS overdue_balance
           FROM invoices i
           JOIN unnest(${ids}::uuid[], ${p.add(scope.properties.map((x) => x.today))}::date[])
             AS oclk(property_id, today) ON oclk.property_id = i.property_id
          WHERE ${overdueInvoiceSql('oclk.today')}
          GROUP BY i.tenancy_id
       ) od ON od.tenancy_id = t.id`
    : '';
  const rows = await q<{
    id: string;
    property_id: string;
    node_id: string | null;
    status: string;
    name: string | null;
    node_name: string | null;
    phone?: string | null;
    overdue_balance?: string;
  }>(
    `SELECT t.id, t.property_id, t.node_id, t.status::text AS status,
            COALESCE(NULLIF(t.full_name, ''), u.name) AS name,
            n.name AS node_name
            ${withPhone ? ', u.phone' : ''}
            ${overdueOnly ? ', od.overdue_balance::text AS overdue_balance' : ''}
       FROM tenancies t
       ${overdueJoin}
       LEFT JOIN users u ON u.id = t.user_id
       LEFT JOIN hierarchy_nodes n ON n.id = t.node_id
      WHERE t.property_id = ANY(${ids}::uuid[])
        ${checkedOutOnly ? `AND t.status = 'ended'` : ''}
        ${overdueOnly ? `AND t.status = 'active'` : ''}
        AND (${contains}::text IS NULL
             OR t.full_name ILIKE ${contains} OR u.name ILIKE ${contains} OR n.name ILIKE ${contains}
             ${digits ? `OR (${digits}::text IS NOT NULL AND regexp_replace(COALESCE(u.phone, ''), '\\D', '', 'g') LIKE ${digits})` : ''})
      ORDER BY (t.status = 'active') DESC,
               (${prefix}::text IS NOT NULL AND COALESCE(NULLIF(t.full_name, ''), u.name) ILIKE ${prefix}) DESC,
               COALESCE(NULLIF(t.full_name, ''), u.name), t.created_at DESC
      LIMIT ${limit}`,
    p.values,
  );
  return rows.map((r) => ({
    ...baseHit('tenants', r.id, r.property_id, scope),
    nodeId: r.node_id,
    title: r.name?.trim() || 'Tenant',
    subtitle: r.node_name,
    status: r.status,
    ...(withPhone ? { phone: r.phone ?? null } : {}),
    ...(overdueOnly ? { amount: money(r.overdue_balance) } : {}),
  }));
};

const searchTeam: Provider = async (q, scope, terms) => {
  if (scope.kind !== 'team' || (scope.role !== 'owner' && scope.role !== 'admin')) return [];
  if (!terms.contains) return [];
  const p = new Params();
  const ids = p.add(scopeIds(scope));
  const contains = p.add(terms.contains);
  const digits = p.add(terms.digits);
  const limit = p.add(terms.limit);
  const rows = await q<{
    id: string;
    property_id: string;
    role: string;
    status: string;
    name: string | null;
    phone: string | null;
  }>(
    `SELECT psa.id, psa.property_id, psa.role::text AS role, psa.status, u.name, u.phone
       FROM property_staff_assignments psa
       JOIN users u ON u.id = psa.user_id
      WHERE psa.property_id = ANY(${ids}::uuid[])
        AND (u.name ILIKE ${contains} OR psa.role::text ILIKE ${contains}
             OR (${digits}::text IS NOT NULL AND regexp_replace(COALESCE(u.phone, ''), '\\D', '', 'g') LIKE ${digits}))
      ORDER BY u.name NULLS LAST, psa.created_at
      LIMIT ${limit}`,
    p.values,
  );
  const roleLabel = (role: string) => (role === 'manager' ? 'Manager' : role === 'staff' ? 'Staff' : role);
  return rows.map((r) => ({
    ...baseHit('team', r.id, r.property_id, scope),
    title: r.name?.trim() || 'Invited member',
    subtitle: joinParts([roleLabel(r.role), r.status === 'pending' ? 'Invitation pending' : null]),
    status: r.status,
    phone: r.phone ?? null,
  }));
};

const searchComplaints: Provider = async (q, scope, terms) => {
  if (!terms.contains) return [];
  const p = new Params();
  const contains = p.add(terms.contains);
  const limit = p.add(terms.limit);
  let where: string;
  if (scope.kind === 'tenant') {
    where = `c.property_id = ${p.add(scope.property.id)} AND c.raised_by = ${p.add(scope.userId)}`;
  } else {
    where = `c.property_id = ANY(${p.add(scopeIds(scope))}::uuid[])`;
    if (scope.role === 'staff' && (await complaintSchemaCaps()).assignment) {
      where += ` AND (c.assigned_to IS NULL OR c.assigned_to = ${p.add(scope.userId)})`;
    }
  }
  const rows = await q<{
    id: string;
    property_id: string;
    node_id: string | null;
    ticket_number: string | null;
    category: string;
    description: string | null;
    status: string;
    created_at: Date | string;
    node_name: string | null;
  }>(
    `SELECT c.id, c.property_id, c.node_id, c.ticket_number, c.category, c.description,
            c.status::text AS status, c.created_at, n.name AS node_name
       FROM complaints c
       LEFT JOIN hierarchy_nodes n ON n.id = c.node_id
      WHERE ${where}
        AND (c.ticket_number ILIKE ${contains} OR c.category ILIKE ${contains}
             OR c.description ILIKE ${contains} OR n.name ILIKE ${contains}
             OR replace(c.status::text, '_', ' ') ILIKE ${contains})
      ORDER BY c.created_at DESC
      LIMIT ${limit}`,
    p.values,
  );
  return rows.map((r) => ({
    ...baseHit('complaints', r.id, r.property_id, scope),
    nodeId: r.node_id,
    title: joinParts([r.ticket_number, r.category]) ?? 'Complaint',
    subtitle: joinParts([r.node_name, snippet(r.description)]),
    status: r.status,
    date: isoDate(r.created_at),
  }));
};

const searchGatePasses: Provider = async (q, scope, terms) => {
  if (!terms.contains) return [];
  const p = new Params();
  const contains = p.add(terms.contains);
  const limit = p.add(terms.limit);
  let where: string;
  if (scope.kind === 'tenant') {
    if (!isFeatureAllowed({ property_type_key: scope.property.type }, 'gate_pass')) return [];
    where = `gp.property_id = ${p.add(scope.property.id)}
             AND (gp.requested_by = ${p.add(scope.userId)} OR gp.tenancy_id = ${p.add(scope.tenancyId)})`;
  } else {
    where = `gp.property_id = ANY(${p.add(scopeIds(scope))}::uuid[])`;
  }
  const rows = await q<{
    id: string;
    property_id: string;
    unit_id: string | null;
    visitor_name: string;
    purpose: string | null;
    status: string;
    created_at: Date | string;
    unit_name: string | null;
  }>(
    `SELECT gp.id, gp.property_id, gp.unit_id, gp.visitor_name, gp.purpose, gp.status,
            gp.created_at, n.name AS unit_name
       FROM gate_passes gp
       LEFT JOIN hierarchy_nodes n ON n.id = gp.unit_id
      WHERE ${where}
        AND (gp.visitor_name ILIKE ${contains} OR gp.purpose ILIKE ${contains}
             OR n.name ILIKE ${contains} OR gp.status ILIKE ${contains})
      ORDER BY gp.created_at DESC
      LIMIT ${limit}`,
    p.values,
  );
  return rows.map((r) => ({
    ...baseHit('gate_passes', r.id, r.property_id, scope),
    nodeId: r.unit_id,
    title: r.visitor_name,
    subtitle: joinParts([r.purpose, r.unit_name]),
    status: r.status,
    date: isoDate(r.created_at),
  }));
};

const searchInvoices: Provider = async (q, scope, terms) => {
  if (scope.kind === 'team' && scope.role === 'staff') return [];
  const p = new Params();
  const clockIds = scope.kind === 'team' ? scope.properties.map((x) => x.id) : [scope.property.id];
  const clockDays = scope.kind === 'team' ? scope.properties.map((x) => x.today) : [scope.property.today];
  const ids = p.add(clockIds);
  const days = p.add(clockDays);
  const contains = p.add(terms.contains);
  const limit = p.add(terms.limit);
  const ownOnly = scope.kind === 'tenant' ? `AND i.tenancy_id = ${p.add(scope.tenancyId)} AND i.sent_at IS NOT NULL` : '';
  const labelFilter =
    terms.filter === 'overdue' ? `AND x.label = 'overdue'` : terms.filter === 'drafts' ? `AND x.label = 'draft'` : '';
  const rows = await q<{
    id: string;
    property_id: string;
    tenancy_id: string | null;
    period_label: string | null;
    due_date: string | null;
    total_amount: string;
    balance: string;
    label: string;
    tenant_name: string | null;
    node_name: string | null;
  }>(
    `SELECT * FROM (
       SELECT i.id, i.property_id, i.tenancy_id, i.period_start,
              to_char(i.period_start, 'Mon YYYY') AS period_label,
              to_char(i.period_start, 'FMMonth') AS month_name,
              i.due_date::text AS due_date,
              i.total_amount::text AS total_amount,
              (i.total_amount - COALESCE(pay.paid, 0))::text AS balance,
              CASE
                WHEN i.sent_at IS NULL THEN 'draft'
                WHEN i.total_amount - COALESCE(pay.paid, 0) <= 0 THEN 'paid'
                WHEN i.due_date < clk.today THEN 'overdue'
                WHEN COALESCE(pay.paid, 0) > 0 THEN 'partial'
                ELSE 'pending'
              END AS label,
              COALESCE(NULLIF(t.full_name, ''), u.name) AS tenant_name,
              n.name AS node_name
         FROM invoices i
         JOIN unnest(${ids}::uuid[], ${days}::date[]) AS clk(property_id, today)
           ON clk.property_id = i.property_id
         LEFT JOIN (
           SELECT pp.invoice_id, SUM(pp.amount) AS paid
             FROM payments pp
             JOIN invoices pi ON pi.id = pp.invoice_id
            WHERE pi.property_id = ANY(${ids}::uuid[])
            GROUP BY pp.invoice_id
         ) pay ON pay.invoice_id = i.id
         LEFT JOIN tenancies t ON t.id = i.tenancy_id
         LEFT JOIN users u ON u.id = t.user_id
         LEFT JOIN hierarchy_nodes n ON n.id = t.node_id
        WHERE TRUE ${ownOnly}
     ) x
     WHERE (${contains}::text IS NULL
            OR x.tenant_name ILIKE ${contains} OR x.node_name ILIKE ${contains}
            OR x.period_label ILIKE ${contains} OR x.month_name ILIKE ${contains}
            OR x.label ILIKE ${contains})
       ${labelFilter}
     ORDER BY x.period_start DESC, x.tenant_name
     LIMIT ${limit}`,
    p.values,
  );
  return rows.map((r) => {
    const amount = r.label === 'paid' || r.label === 'draft' ? money(r.total_amount) : money(r.balance);
    return {
      ...baseHit('invoices', r.id, r.property_id, scope),
      invoiceId: r.id,
      title:
        scope.kind === 'tenant'
          ? `Bill · ${r.period_label ?? ''}`.trim()
          : joinParts([r.tenant_name, r.period_label]) ?? 'Invoice',
      subtitle: scope.kind === 'tenant' ? null : r.node_name,
      status: r.label,
      amount,
      date: r.due_date,
    };
  });
};

const searchPayments: Provider = async (q, scope, terms) => {
  if (scope.kind === 'team' && scope.role === 'staff') return [];
  if (!terms.contains) return [];
  const p = new Params();
  const contains = p.add(terms.contains);
  const limit = p.add(terms.limit);
  const where =
    scope.kind === 'tenant'
      ? `i.property_id = ${p.add(scope.property.id)} AND i.tenancy_id = ${p.add(scope.tenancyId)} AND i.sent_at IS NOT NULL`
      : `i.property_id = ANY(${p.add(scopeIds(scope))}::uuid[])`;
  const rows = await q<{
    id: string;
    invoice_id: string;
    property_id: string;
    amount: string;
    method: string | null;
    paid_at: Date | string;
    period_label: string | null;
    tenant_name: string | null;
    node_name: string | null;
  }>(
    `SELECT p.id, p.invoice_id, i.property_id, p.amount::text AS amount, p.method, p.paid_at,
            to_char(i.period_start, 'Mon YYYY') AS period_label,
            COALESCE(NULLIF(t.full_name, ''), u.name) AS tenant_name,
            n.name AS node_name
       FROM payments p
       JOIN invoices i ON i.id = p.invoice_id
       LEFT JOIN tenancies t ON t.id = i.tenancy_id
       LEFT JOIN users u ON u.id = t.user_id
       LEFT JOIN hierarchy_nodes n ON n.id = t.node_id
      WHERE ${where}
        AND (t.full_name ILIKE ${contains} OR u.name ILIKE ${contains} OR n.name ILIKE ${contains}
             OR p.method ILIKE ${contains}
             OR to_char(i.period_start, 'Mon YYYY') ILIKE ${contains}
             OR to_char(p.paid_at, 'Mon YYYY') ILIKE ${contains})
      ORDER BY p.paid_at DESC
      LIMIT ${limit}`,
    p.values,
  );
  return rows.map((r) => ({
    ...baseHit('payments', r.id, r.property_id, scope),
    invoiceId: r.invoice_id,
    title:
      scope.kind === 'tenant'
        ? `Payment · ${r.period_label ?? ''}`.trim()
        : joinParts([r.tenant_name, r.period_label]) ?? 'Payment',
    subtitle: joinParts([r.method ? r.method.toUpperCase() : null, scope.kind === 'tenant' ? null : r.node_name]),
    status: 'paid',
    amount: money(r.amount),
    date: isoDate(r.paid_at),
  }));
};

const searchMeterReadings: Provider = async (q, scope, terms) => {
  if (!terms.contains) return [];
  const p = new Params();
  const contains = p.add(terms.contains);
  const limit = p.add(terms.limit);
  let where: string;
  if (scope.kind === 'tenant') {
    if (!scope.nodeId || !isFeatureAllowed({ property_type_key: scope.property.type }, 'meter_reading')) return [];
    where = `mr.property_id = ${p.add(scope.property.id)}
             AND mr.tenancy_id = ${p.add(scope.tenancyId)}
             AND mr.unit_id = ${p.add(scope.nodeId)}`;
  } else {
    where = `mr.property_id = ANY(${p.add(scopeIds(scope))}::uuid[])`;
  }
  const rows = await q<{
    id: string;
    property_id: string;
    unit_id: string;
    reading: string;
    billing_cycle: string;
    created_at: Date | string;
    unit_name: string | null;
  }>(
    `SELECT mr.id, mr.property_id, mr.unit_id, mr.meter_reading_value::text AS reading,
            mr.billing_cycle, mr.created_at, n.name AS unit_name
       FROM meter_readings mr
       LEFT JOIN hierarchy_nodes n ON n.id = mr.unit_id
      WHERE ${where}
        AND (n.name ILIKE ${contains} OR mr.billing_cycle ILIKE ${contains})
      ORDER BY mr.created_at DESC
      LIMIT ${limit}`,
    p.values,
  );
  return rows.map((r) => {
    const reading = Number(r.reading);
    return {
      ...baseHit('meter_readings', r.id, r.property_id, scope),
      nodeId: r.unit_id,
      title: joinParts([r.unit_name, r.billing_cycle]) ?? 'Meter reading',
      subtitle: Number.isFinite(reading) ? `Reading ${reading}` : null,
      status: null,
      date: isoDate(r.created_at),
    };
  });
};

const searchMessMenu: Provider = async (q, scope, terms) => {
  if (!terms.contains) return [];
  if (scope.kind === 'tenant' && !isFeatureAllowed({ property_type_key: scope.property.type }, 'mess_menu')) {
    return [];
  }
  const p = new Params();
  const ids = p.add(scopeIds(scope));
  const contains = p.add(terms.contains);
  const limit = p.add(terms.limit);
  const rows = await q<{
    id: string;
    property_id: string;
    day_of_week: number;
    breakfast: string;
    lunch: string;
    dinner: string;
  }>(
    `SELECT m.id, m.property_id, m.day_of_week, m.breakfast, m.lunch, m.dinner
       FROM mess_menus m
      WHERE m.property_id = ANY(${ids}::uuid[])
        AND (m.breakfast ILIKE ${contains} OR m.lunch ILIKE ${contains} OR m.dinner ILIKE ${contains}
             OR ${DAY_NAME_SQL} ILIKE ${contains})
      ORDER BY m.property_id, m.day_of_week
      LIMIT ${limit}`,
    p.values,
  );
  const needle = terms.text.toLowerCase();
  return rows.map((r) => {
    const day = DAY_NAMES[r.day_of_week - 1] ?? 'Menu';
    const meals: [string, string][] = [
      ['Breakfast', r.breakfast],
      ['Lunch', r.lunch],
      ['Dinner', r.dinner],
    ];
    const matching = meals.filter(([, food]) => food.toLowerCase().includes(needle));
    const shown = (matching.length ? matching : meals).filter(([, food]) => food.trim().length > 0);
    return {
      ...baseHit('mess_menu', r.id, r.property_id, scope),
      title: `${day} menu`,
      subtitle: snippet(shown.map(([meal, food]) => `${meal}: ${food.trim()}`).join(' · '), 100),
      status: null,
    };
  });
};

const PROVIDERS: Record<SearchCategory, Provider> = {
  properties: searchProperties,
  rooms: searchRooms,
  tenants: searchTenants,
  team: searchTeam,
  complaints: searchComplaints,
  gate_passes: searchGatePasses,
  invoices: searchInvoices,
  payments: searchPayments,
  meter_readings: searchMeterReadings,
  mess_menu: searchMessMenu,
};

function isStatementTimeout(err: unknown): boolean {
  return typeof err === 'object' && err !== null && (err as { code?: unknown }).code === '57014';
}

export class SearchService {
  async search(ctx: SearchContext, request: SearchRequest): Promise<SearchHit[]> {
    const terms = buildTerms(request, ctx.role);
    try {
      return await withTransaction(async (q) => {
        await q('SET TRANSACTION READ ONLY');
        await q(`SET LOCAL statement_timeout = ${SEARCH_STATEMENT_TIMEOUT_MS}`);
        const scope = await resolveScope(q, ctx);
        if (scope.kind === 'team' && scope.properties.length === 0) return [];
        const hits: SearchHit[] = [];
        for (const category of request.categories) {
          hits.push(...(await PROVIDERS[category](q, scope, terms)));
        }
        return hits.map((hit) => serializeHit(hit, ctx.role));
      });
    } catch (err) {
      if (isStatementTimeout(err)) {
        throw new SearchRequestError(503, 'search_timeout', 'Search took too long. Try a more specific search.');
      }
      throw err;
    }
  }
}
