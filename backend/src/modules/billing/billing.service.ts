// modules/billing/billing.service.ts
import { query, withTransaction, type TxQuery } from '@config/db';
import {
  calendarDateInTimeZone,
  compareYmd,
  DEFAULT_PROPERTY_TIME_ZONE,
  hostelBillingTimeZone,
  checkMoveInEdit,
  invoiceFormCycle,
  planHostelCycles,
  type CyclePlan,
  type InvoiceFormCycle,
  type MoveInEditCheck,
} from './hostel-billing-cycle';
import {
  createNotification,
  notifyPropertyOwners,
} from '@modules/notifications/notify';
import {
  ensureNotificationsSchema,
  resolvePropertyOwnerIds,
} from '@modules/notifications/move-out-notifications';
import { overdueFlagSql, propertyClock } from './billing-metrics';
import { schemaAutoMigrateEnabled } from '@config/runtime-flags';

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
  /** Defaults to 'cycle'. Stored only once migration 026 is applied. */
  invoiceKind?: InvoiceKind;
  /** Authenticated user who created (and thereby approved) the invoice. */
  approvedBy?: string | null;
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

/**
 * Applies the billing schema of migrations 019/025 (idempotent) when
 * DB_SCHEMA_AUTO_MIGRATE is on. Otherwise a no-op: startup has already
 * verified the schema read-only. Never drops the legacy invoice index; that is
 * retireLegacyInvoiceIndex(), gated separately at startup.
 */
export async function ensureBillingSchema(): Promise<void> {
  if (!billingSchemaReady && !schemaAutoMigrateEnabled()) return;
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
      // After 026 the cycle-only partial index replaces this one; recreating
      // it would block ad hoc charges that share a cycle's start date.
      const caps = await billingSchemaCaps();
      if (!caps.invoiceKind) {
        await query(
          `CREATE UNIQUE INDEX IF NOT EXISTS invoices_tenancy_period_start_uniq
             ON invoices (tenancy_id, period_start)`,
        ).catch((err) =>
          console.warn(
            '[billing] unique (tenancy_id, period_start) not created — existing duplicates?',
            err,
          ),
        );
      }
    })();
  }
  return billingSchemaReady;
}

/**
 * Pre-026 builds recreate invoices_tenancy_period_start_uniq at boot. Once the
 * cycle-only index is confirmed valid, relabel the one-day manual charges
 * those builds stored with the 'cycle' default, then drop the legacy index.
 * Rows written by current code always carry approved_by, so they are never
 * relabelled. Idempotent; removes no invoices. Only called from startup when
 * LEGACY_INVOICE_INDEX_CLEANUP is on.
 */
export async function retireLegacyInvoiceIndex(caps: BillingSchemaCaps): Promise<void> {
  const [state] = await query<{ cycle_index_valid: boolean; legacy_index_exists: boolean }>(
    `SELECT
       EXISTS (
         SELECT 1 FROM pg_index ix
         JOIN pg_class c ON c.oid = ix.indexrelid
         JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'public'
           AND c.relname = 'invoices_cycle_tenancy_period_start_uniq'
           AND ix.indisvalid AND ix.indisready
       ) AS cycle_index_valid,
       to_regclass('public.invoices_tenancy_period_start_uniq') IS NOT NULL
         AS legacy_index_exists`,
  );
  if (!state?.cycle_index_valid) {
    console.warn('[billing] cycle-only invoice index missing or invalid; legacy index kept');
    return;
  }

  await withTransaction(async (q) => {
    if (caps.approvedBy) {
      const relabelled = await q<{ id: string }>(
        `UPDATE invoices
         SET invoice_kind = 'adhoc', updated_at = now()
         WHERE invoice_kind = 'cycle'
           AND NOT is_auto_generated
           AND period_start = period_end
           AND approved_by IS NULL
         RETURNING id`,
      );
      if (relabelled.length > 0) {
        console.log(`[billing] relabelled ${relabelled.length} one-day manual invoice(s) as adhoc`);
      }
    }
    if (state.legacy_index_exists) {
      await q(`DROP INDEX IF EXISTS invoices_tenancy_period_start_uniq`);
      console.log('[billing] dropped legacy index invoices_tenancy_period_start_uniq');
    }
  });
}

export type BillingSchemaCaps = { invoiceKind: boolean; approvedBy: boolean };

const CAPS_TTL_MS = 5 * 60_000;
let capsCache: { at: number; value: Promise<BillingSchemaCaps> } | null = null;

/**
 * Columns from migration 026 (applied manually). Cached briefly so the app
 * picks them up without a restart once the migration has been run.
 */
export function billingSchemaCaps(): Promise<BillingSchemaCaps> {
  const now = Date.now();
  if (!capsCache || now - capsCache.at > CAPS_TTL_MS) {
    const value = query<{ column_name: string }>(
      `SELECT column_name FROM information_schema.columns
       WHERE table_schema = 'public' AND table_name = 'invoices'
         AND column_name IN ('invoice_kind', 'approved_by')`,
    )
      .then((rows) => {
        const cols = new Set(rows.map((r) => r.column_name));
        return {
          invoiceKind: cols.has('invoice_kind'),
          approvedBy: cols.has('approved_by'),
        };
      })
      .catch(() => {
        capsCache = null;
        return { invoiceKind: false, approvedBy: false };
      });
    capsCache = { at: now, value };
  }
  return capsCache.value;
}

export type InvoiceKind = 'cycle' | 'adhoc';

type GeneratorTenancyRow = {
  id: string;
  full_name: string | null;
  monthly_rent: string | number | null;
  move_in_at: Date | string | null;
  move_out_at: Date | string | null;
  status: string | null;
};

type BilledRow = { period_start: Date | string; period_end: Date | string };

/**
 * Billing periods already covered by rent-cycle invoices. Before 026 there is
 * no invoice_kind, so one-day manual charges are excluded by the same rule
 * the 026 backfill uses.
 */
function billedCyclesSql(hasInvoiceKind: boolean): string {
  return `SELECT period_start::text AS period_start, period_end::text AS period_end
          FROM invoices
          WHERE tenancy_id = $1
            AND ${cycleInvoiceSql(hasInvoiceKind)}`;
}

function cycleInvoiceSql(hasInvoiceKind: boolean): string {
  return hasInvoiceKind
    ? `invoice_kind = 'cycle'`
    : `NOT (NOT is_auto_generated AND period_start = period_end)`;
}

function calendarDateOrNull(raw: Date | string | null, timeZone: string): string | null {
  if (!raw) return null;
  const instant = new Date(raw);
  if (Number.isNaN(instant.getTime())) return null;
  try {
    return calendarDateInTimeZone(instant, timeZone);
  } catch {
    return calendarDateInTimeZone(instant, DEFAULT_PROPERTY_TIME_ZONE);
  }
}

/** Invoice edit refused because it would change an issued bill. */
export class InvoiceLockedError extends Error {
  constructor(
    message: string,
    readonly code:
      | 'invoice_period_locked'
      | 'cycle_period_locked'
      | 'invoice_paid'
      | 'invoice_partially_paid'
      | 'invoice_identity_locked'
      | 'invoice_sent'
      | 'meter_line_linked',
  ) {
    super(message);
  }
}

export type InvoiceEditState = {
  sent: boolean;
  kind: InvoiceKind;
  total: number;
  paid: number;
};

export type InvoiceEditChange = {
  periodChanged: boolean;
  dueDateChanged: boolean;
  chargesChanged: boolean;
};

/**
 * Edit rules:
 * - A sent invoice's billing period never changes; a cycle invoice's period
 *   never changes (it is the cycle's identity), even as a draft.
 * - Charges change only while no payment is recorded, so payments always
 *   match the bill they were made against.
 * - The due date may still move on a partially paid invoice (e.g. to give
 *   the tenant more time for the balance), but not once it is fully paid.
 * Returns null when the edit is allowed.
 */
export function invoiceEditBlock(
  state: InvoiceEditState,
  change: InvoiceEditChange,
): InvoiceLockedError | null {
  if (change.periodChanged) {
    if (state.sent) {
      return new InvoiceLockedError(
        "The billing period of a sent invoice can't be changed. You can still edit its charges and due date while it is unpaid.",
        'invoice_period_locked',
      );
    }
    if (state.kind === 'cycle') {
      return new InvoiceLockedError(
        "The billing period of a rent-cycle invoice can't be changed; it is set by the tenant's move-in anniversary. Edit the charges or due date instead.",
        'cycle_period_locked',
      );
    }
  }
  if (state.paid <= 0) return null;
  const fullyPaid = state.total > 0 && state.paid >= state.total;
  if (fullyPaid && (change.chargesChanged || change.dueDateChanged)) {
    return new InvoiceLockedError(
      "This invoice is fully paid, so its charges and due date can't be changed. Add a one-off charge for anything new.",
      'invoice_paid',
    );
  }
  if (change.chargesChanged) {
    return new InvoiceLockedError(
      `A payment of ₹${roundMoney(state.paid)} is already recorded on this invoice, so its charges can't be changed. You can still change the due date, or add a one-off charge for anything new.`,
      'invoice_partially_paid',
    );
  }
  return null;
}

export type CurrentLine = {
  id: string;
  description: string;
  amount: number;
  chargeTypeId: string | null;
  meterLinked: boolean;
};

export type IncomingLine = {
  description: string;
  amount: number;
  chargeTypeId: string | null;
  chargeKind?: ChargeKind;
};

export type LineItemPlan = {
  keep: string[];
  update: { id: string; line: IncomingLine }[];
  remove: string[];
  insert: IncomingLine[];
  /** Meter-reading lines the edit would remove or rename. */
  blocked: CurrentLine[];
};

const sameLine = (c: CurrentLine, i: IncomingLine) =>
  c.description.trim() === i.description.trim() &&
  roundMoney(c.amount) === roundMoney(i.amount) &&
  (i.chargeTypeId == null || c.chargeTypeId === i.chargeTypeId);

/**
 * Reconciles an edited charge list with the stored line items. The app sends
 * lines without ids, so unchanged lines are matched by content and kept.
 * A line linked to a meter reading keeps its row: a changed amount under the
 * same description is updated in place; removing or renaming it is blocked.
 */
export function planLineItemChanges(
  current: CurrentLine[],
  incoming: IncomingLine[],
): LineItemPlan {
  const plan: LineItemPlan = { keep: [], update: [], remove: [], insert: [], blocked: [] };
  const open = incoming.map(() => true);
  const take = (pred: (i: IncomingLine) => boolean) => {
    const idx = incoming.findIndex((line, k) => open[k] && pred(line));
    if (idx >= 0) open[idx] = false;
    return idx;
  };

  // Meter-linked rows claim their exact match first.
  const ordered = [...current].sort((a, b) => Number(b.meterLinked) - Number(a.meterLinked));
  const unmatched: CurrentLine[] = [];
  for (const c of ordered) {
    if (take((i) => sameLine(c, i)) >= 0) plan.keep.push(c.id);
    else unmatched.push(c);
  }
  for (const c of unmatched) {
    if (!c.meterLinked) {
      plan.remove.push(c.id);
      continue;
    }
    const idx = take((i) => i.description.trim() === c.description.trim());
    if (idx >= 0) plan.update.push({ id: c.id, line: incoming[idx] });
    else plan.blocked.push(c);
  }
  incoming.forEach((line, k) => {
    if (open[k]) plan.insert.push(line);
  });
  return plan;
}

type LineSignature = { description: string; amount: number; chargeTypeId: string | null };

/**
 * True when [incoming] is the same set of charges as [current]. A charge type
 * is compared only when the client sends one, so re-saving an unchanged form
 * is not mistaken for an edit.
 */
export function sameCharges(current: LineSignature[], incoming: LineSignature[]): boolean {
  if (current.length !== incoming.length) return false;
  const remaining = [...current];
  for (const item of incoming) {
    const i = remaining.findIndex(
      (c) =>
        c.description.trim() === item.description.trim() &&
        roundMoney(c.amount) === roundMoney(item.amount) &&
        (item.chargeTypeId == null || c.chargeTypeId === item.chargeTypeId),
    );
    if (i < 0) return false;
    remaining.splice(i, 1);
  }
  return true;
}

/** Move-in date edit refused because it would shift already-billed cycles. */
export class MoveInDateLockedError extends Error {
  readonly code = 'move_in_date_locked';
}

function dayOrdinal(day: number): string {
  if (day >= 11 && day <= 13) return `${day}th`;
  const suffix = ({ 1: 'st', 2: 'nd', 3: 'rd' } as Record<number, string>)[day % 10] ?? 'th';
  return `${day}${suffix}`;
}

export function moveInLockedMessage(
  check: Exclude<MoveInEditCheck, { allowed: true }>,
  currentCheckIn: string | null,
  newCheckIn: string,
): string {
  const billed = `Rent is already billed for ${formatShortDate(check.firstBilledStart)} – ${formatShortDate(check.lastBilledEnd)}`;
  const keep = 'Existing invoices and payments are kept as they are. Keep the current move-in date, or add a one-off charge for any adjustment.';
  if (check.reason === 'anniversary_changed' && currentCheckIn) {
    return `The move-in date can't be changed to ${formatShortDate(newCheckIn)}: it would move the billing day from the ${dayOrdinal(Number(currentCheckIn.slice(8, 10)))} to the ${dayOrdinal(Number(newCheckIn.slice(8, 10)))} of each month. ${billed}, so the billing periods would overlap or leave days unbilled. ${keep}`;
  }
  if (check.reason === 'after_billed_period') {
    return `The move-in date can't be changed to ${formatShortDate(newCheckIn)}: it is after the start of an already-billed period. ${billed}. ${keep}`;
  }
  return `The move-in date can't be changed to ${formatShortDate(newCheckIn)}: it doesn't line up with the billing periods already invoiced. ${billed}. ${keep}`;
}

/**
 * Runs on the caller's transaction and locks the tenancy row, so the draft
 * generator cannot bill a cycle between this check and the update.
 * Throws MoveInDateLockedError when the edit would shift billed cycles.
 */
export async function assertMoveInEditAllowed(
  q: TxQuery,
  tenancyId: string,
  newMoveInAt: string,
): Promise<void> {
  const [row] = await q<{ move_in_at: Date | string | null; timezone: string | null }>(
    `SELECT t.move_in_at, p.timezone
     FROM tenancies t JOIN properties p ON p.id = t.property_id
     WHERE t.id = $1
     FOR UPDATE OF t`,
    [tenancyId],
  );
  if (!row) return;
  const timeZone = hostelBillingTimeZone(row.timezone);
  const newCheckIn = calendarDateOrNull(newMoveInAt, timeZone);
  // Unparseable input is left to the UPDATE, which rejects it as before.
  if (!newCheckIn) return;
  const currentCheckIn = calendarDateOrNull(row.move_in_at, timeZone);
  if (currentCheckIn === newCheckIn) return;

  const caps = await billingSchemaCaps();
  const billed = await q<BilledRow>(billedCyclesSql(caps.invoiceKind), [tenancyId]);
  const check = checkMoveInEdit({
    currentCheckIn,
    newCheckIn,
    billed: billed.map((b) => ({
      periodStart: dbDateToYmd(b.period_start),
      periodEnd: dbDateToYmd(b.period_end),
    })),
  });
  if (!check.allowed) {
    throw new MoveInDateLockedError(moveInLockedMessage(check, currentCheckIn, newCheckIn));
  }
}

/** Null when the tenancy cannot be billed (not active, no move-in, no rent). */
export function planForTenancy(
  tenancy: GeneratorTenancyRow,
  billed: BilledRow[],
  timeZone: string,
  today: string,
): { rent: number; plan: CyclePlan } | null {
  if (tenancy.status !== 'active') return null;
  const rent = roundMoney(Number(tenancy.monthly_rent ?? 0));
  if (!(rent > 0)) return null;
  const checkIn = calendarDateOrNull(tenancy.move_in_at, timeZone);
  if (!checkIn) return null;
  return {
    rent,
    plan: planHostelCycles({
      checkIn,
      today,
      moveOut: calendarDateOrNull(tenancy.move_out_at, timeZone),
      billed: billed.map((b) => ({
        periodStart: dbDateToYmd(b.period_start),
        periodEnd: dbDateToYmd(b.period_end),
      })),
    }),
  };
}

type NotificationRow = {
  userId: string;
  propertyId: string;
  type: string;
  title: string;
  body: string;
  data: Record<string, unknown>;
};

/**
 * Inserts on the caller's transaction and throws on failure, so the invoice
 * change and its in-app notification commit or roll back together.
 */
async function insertNotificationTx(
  q: TxQuery,
  n: NotificationRow,
  hasDataColumn: boolean,
): Promise<void> {
  if (hasDataColumn) {
    await q(
      `INSERT INTO notifications (user_id, property_id, type, title, body, data)
       VALUES ($1, $2, $3, $4, $5, $6::jsonb)`,
      [n.userId, n.propertyId, n.type, n.title, n.body, JSON.stringify(n.data)],
    );
  } else {
    await q(
      `INSERT INTO notifications (user_id, property_id, type, title, body)
       VALUES ($1, $2, $3, $4, $5)`,
      [n.userId, n.propertyId, n.type, n.title, n.body],
    );
  }
}

/** Tenant-facing "invoice sent" notification for a freshly approved invoice. */
export function buildInvoiceSentNotification(inv: {
  id: string;
  tenancyId: string;
  propertyId: string;
  tenantUserId: string;
  periodStart: string;
  periodEnd: string;
  dueDate: string;
  balance: number;
  today: string;
}): NotificationRow {
  const pastDue = compareYmd(inv.dueDate, inv.today) < 0;
  return {
    userId: inv.tenantUserId,
    propertyId: inv.propertyId,
    type: 'invoice_sent',
    title: pastDue ? 'New invoice — payment overdue' : 'New invoice',
    body: `Invoice for ${formatShortDate(inv.periodStart)} – ${formatShortDate(inv.periodEnd)}: ₹${inv.balance}. ${
      pastDue ? 'It was due on' : 'Due by'
    } ${formatShortDate(inv.dueDate)}.`,
    data: {
      route: '/tenant/dashboard?focus=payments',
      invoice_id: inv.id,
      invoiceId: inv.id,
      tenancy_id: inv.tenancyId,
      tenancyId: inv.tenancyId,
      property_id: inv.propertyId,
      propertyId: inv.propertyId,
      amount_due: inv.balance,
    },
  };
}

/** Tenant-facing notice that an already-sent invoice's charges or due date changed. */
export function buildInvoiceUpdatedNotification(inv: {
  id: string;
  tenancyId: string;
  propertyId: string;
  tenantUserId: string;
  periodStart: string;
  periodEnd: string;
  dueDate: string;
  total: number;
  balance: number;
  chargesChanged: boolean;
  dueDateChanged: boolean;
}): NotificationRow {
  const parts = [
    `Your invoice for ${formatShortDate(inv.periodStart)} – ${formatShortDate(inv.periodEnd)} was updated.`,
  ];
  if (inv.chargesChanged) parts.push(`New total: ₹${inv.total}.`);
  if (inv.balance !== inv.total) parts.push(`Balance due: ₹${inv.balance}.`);
  parts.push(
    inv.dueDateChanged
      ? `New due date: ${formatShortDate(inv.dueDate)}.`
      : `Due by ${formatShortDate(inv.dueDate)}.`,
  );
  return {
    userId: inv.tenantUserId,
    propertyId: inv.propertyId,
    type: 'invoice_updated',
    title: inv.chargesChanged ? 'Invoice amount updated' : 'Invoice due date updated',
    body: parts.join(' '),
    data: {
      route: '/tenant/dashboard?focus=payments',
      invoice_id: inv.id,
      invoiceId: inv.id,
      tenancy_id: inv.tenancyId,
      tenancyId: inv.tenancyId,
      property_id: inv.propertyId,
      propertyId: inv.propertyId,
      amount_due: inv.balance,
      total_amount: inv.total,
      due_date: inv.dueDate,
    },
  };
}

/** Money is NUMERIC(12,2): round to paise before comparing or persisting. */
export function roundMoney(n: number): number {
  return Math.round((n + Number.EPSILON) * 100) / 100;
}

/** Largest value NUMERIC(12,2) holds: invoices.total_amount and line item amounts. */
export const MAX_INVOICE_AMOUNT = 9_999_999_999.99;

/** An invoice whose total or a line amount the database cannot store. */
export class InvoiceAmountRangeError extends Error {
  readonly code = 'invoice_total_out_of_range';
  constructor() {
    super(
      'This invoice would be more than ₹9,999,999,999.99, the largest amount supported. Reduce the charges or bill them on separate invoices.',
    );
  }
}

/** Throws InvoiceAmountRangeError unless every rounded amount fits NUMERIC(12,2). */
export function assertInvoiceAmountsInRange(amounts: number[]): void {
  const fits = (n: number) => Number.isFinite(n) && Math.abs(roundMoney(n)) <= MAX_INVOICE_AMOUNT;
  if (!amounts.every(fits)) throw new InvoiceAmountRangeError();
}

/** Rejects a payment that would exceed the invoice's outstanding balance. */
export function assertPaymentWithinBalance(
  amount: number,
  total: number,
  paid: number,
): void {
  const balance = roundMoney(total - paid);
  if (balance <= 0) {
    throw new Error('This invoice is already fully paid.');
  }
  if (roundMoney(amount) > balance) {
    throw new Error(`Amount exceeds the outstanding balance of ₹${balance}.`);
  }
}

function isoDate(d: Date): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

/** node-pg parses DATE as local midnight, so read it back with local getters. */
function dbDateToYmd(value: Date | string): string {
  if (value instanceof Date) return isoDate(value);
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

  async deleteChargeType(chargeTypeId: string, propertyId: string) {
    await query(
      `UPDATE charge_types SET is_active = false WHERE id = $1 AND property_id = $2`,
      [chargeTypeId, propertyId],
    );
  }

  // ---- Add Utilities period ----

  /**
   * Period, due date and unbilled-stay summary for the manual invoice form,
   * on the property's calendar. `cycle` is null when the tenancy has no
   * move-in date. `draft` is the oldest unsent cycle invoice, which the owner
   * should review instead of creating another invoice.
   */
  async invoiceFormCycle(
    propertyId: string,
    tenancyId: string,
  ): Promise<{
    today: string;
    cycle: InvoiceFormCycle | null;
    draft: { id: string; periodStart: string; periodEnd: string } | null;
  }> {
    await ensureBillingSchema();
    const [tenancy] = await query<{
      move_in_at: Date | string | null;
      move_out_at: Date | string | null;
    }>(
      `SELECT move_in_at, move_out_at FROM tenancies WHERE id = $1 AND property_id = $2`,
      [tenancyId, propertyId],
    );
    if (!tenancy) throw new Error('Tenant not found for this property.');

    const clock = await propertyClock(propertyId);
    const caps = await billingSchemaCaps();
    const [draft] = await query<{ id: string; period_start: string; period_end: string }>(
      `SELECT id, period_start::text AS period_start, period_end::text AS period_end
       FROM invoices
       WHERE tenancy_id = $1 AND sent_at IS NULL AND ${cycleInvoiceSql(caps.invoiceKind)}
       ORDER BY period_start
       LIMIT 1`,
      [tenancyId],
    );
    const draftSummary = draft
      ? {
          id: draft.id,
          periodStart: dbDateToYmd(draft.period_start),
          periodEnd: dbDateToYmd(draft.period_end),
        }
      : null;

    const checkIn = calendarDateOrNull(tenancy.move_in_at, clock.timeZone);
    if (!checkIn) return { today: clock.today, cycle: null, draft: draftSummary };

    const billed = await query<BilledRow>(billedCyclesSql(caps.invoiceKind), [tenancyId]);
    return {
      today: clock.today,
      cycle: invoiceFormCycle({
        checkIn,
        today: clock.today,
        moveOut: calendarDateOrNull(tenancy.move_out_at, clock.timeZone),
        billed: billed.map((b) => ({
          periodStart: dbDateToYmd(b.period_start),
          periodEnd: dbDateToYmd(b.period_end),
        })),
      }),
      draft: draftSummary,
    };
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
  async listPendingUtilityCharges(tenancyId: string, q: TxQuery = query) {
    await ensureBillingSchema();
    return q<{
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
       ORDER BY mr.created_at ASC
       FOR UPDATE OF mr`,
      [tenancyId],
    );
  }

  /**
   * Attach unpaid utility meter charges (and similar) as line items on an invoice.
   */
  /**
   * Pass `tx` to run inside the caller's transaction; status is then left for
   * the caller to refresh after commit.
   */
  async addPendingChargesToInvoice(
    tenancyId: string,
    invoiceId: string,
    tx?: TxQuery,
  ): Promise<{ added: number; amount: number }> {
    await ensureBillingSchema();
    if (!tx) {
      // Line items, reading links and the total must commit together.
      const result = await withTransaction((q) =>
        this.addPendingChargesToInvoice(tenancyId, invoiceId, q),
      );
      if (result.amount > 0) await this.recomputeStatus(invoiceId);
      return result;
    }
    const q: TxQuery = tx;

    const [invoice] = await q<{
      id: string;
      tenancy_id: string;
      property_id: string;
    }>(`SELECT id, tenancy_id, property_id FROM invoices WHERE id = $1`, [
      invoiceId,
    ]);
    if (!invoice || invoice.tenancy_id !== tenancyId) {
      throw new Error('Invoice does not belong to this tenancy');
    }

    const pending = await this.listPendingUtilityCharges(tenancyId, q);
    if (pending.length === 0) return { added: 0, amount: 0 };

    // Validate the final total before writing anything; the caller holds the
    // invoice (lock or fresh insert) for the rest of the transaction.
    const [current] = await q<{ total_amount: string }>(
      `SELECT total_amount::text AS total_amount FROM invoices WHERE id = $1`,
      [invoiceId],
    );
    const pendingAmounts = pending.map((row) => Number(row.amount)).filter((a) => a > 0);
    const pendingTotal = roundMoney(pendingAmounts.reduce((sum, a) => sum + a, 0));
    assertInvoiceAmountsInRange([
      ...pendingAmounts,
      pendingTotal,
      Number(current?.total_amount ?? 0) + pendingTotal,
    ]);

    const chargeTypes = await this.listChargeTypes(invoice.property_id);
    const electricity = chargeTypes.find((c: any) =>
      String(c.name).toLowerCase().includes('electric'),
    ) as any;

    let totalAdded = 0;
    for (const row of pending) {
      const amount = Number(row.amount);
      if (!(amount > 0)) continue;

      const [li] = await q<{ id: string }>(
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

      await q(
        `UPDATE meter_readings
         SET invoice_id = $1, invoice_line_item_id = $2
         WHERE id = $3`,
        [invoiceId, li.id, row.id],
      );
      totalAdded += amount;
    }

    if (totalAdded > 0) {
      await q(
        `UPDATE invoices
         SET total_amount = total_amount + $1, updated_at = now()
         WHERE id = $2`,
        [roundMoney(totalAdded), invoiceId],
      );
    }

    return { added: pending.length, amount: totalAdded };
  }

  /**
   * Owner action: attach pending meter/utility charges to a draft. A sent
   * invoice is an issued bill, so new readings wait for the next invoice.
   */
  async attachPendingChargesToDraft(
    invoiceId: string,
    propertyId: string,
    tenancyId: string,
  ): Promise<{ added: number; amount: number } | null> {
    await ensureBillingSchema();
    const result = await withTransaction(async (q) => {
      const [inv] = await q<{ sent_at: Date | null }>(
        `SELECT sent_at FROM invoices
         WHERE id = $1 AND property_id = $2
         FOR UPDATE`,
        [invoiceId, propertyId],
      );
      if (!inv) return null;
      if (inv.sent_at != null) {
        throw new InvoiceLockedError(
          'This invoice has already been sent to the tenant, so new meter charges are not added to it. They stay pending for the next invoice.',
          'invoice_sent',
        );
      }
      return this.addPendingChargesToInvoice(tenancyId, invoiceId, q);
    });
    if (result && result.amount > 0) await this.recomputeStatus(invoiceId);
    return result;
  }

  // ---- Invoices ----

  async createInvoice(input: CreateInvoiceInput) {
    await ensureBillingSchema();

    const [ownTenancy] = await query<{ id: string }>(
      `SELECT id FROM tenancies WHERE id = $1 AND property_id = $2`,
      [input.tenancyId, input.propertyId],
    );
    if (!ownTenancy) {
      throw new Error('Tenancy not found in this property');
    }

    const caps = await billingSchemaCaps();
    const periodStartYmd = input.periodStart.slice(0, 10);
    // Clients that predate invoiceKind create one-off charges as one-day periods.
    const kind: InvoiceKind =
      input.invoiceKind ??
      (periodStartYmd === input.periodEnd.slice(0, 10) ? 'adhoc' : 'cycle');
    // Before 026 every invoice shares one (tenancy_id, period_start) index;
    // after it, only cycle invoices compete for a period start.
    const [duplicate] =
      kind === 'cycle' || !caps.invoiceKind
        ? await query<{ id: string; sent_at: Date | null }>(
            `SELECT id, sent_at FROM invoices
             WHERE tenancy_id = $1 AND period_start = $2::date
               ${caps.invoiceKind ? `AND invoice_kind = 'cycle'` : ''}
             LIMIT 1`,
            [input.tenancyId, periodStartYmd],
          )
        : [];
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

    const positiveItems = lineItems
      .map((li) => ({ ...li, amount: roundMoney(li.amount) }))
      .filter((li) => li.amount > 0);
    const willAttachPending = input.includePendingCharges !== false;
    if (positiveItems.length === 0 && !willAttachPending) {
      throw new Error('Add at least one charge with an amount above 0.');
    }

    const totalAmount = roundMoney(
      positiveItems.reduce((sum, li) => sum + li.amount, 0),
    );
    assertInvoiceAmountsInRange([...positiveItems.map((li) => li.amount), totalAmount]);

    const chargeTypes = await this.listChargeTypes(input.propertyId);
    const typeNameById = new Map(
      chargeTypes.map((c: any) => [String(c.id), String(c.name)]),
    );
    const hasNotificationData = await ensureNotificationsSchema().catch(() => false);
    const today = await this.propertyToday(input.propertyId);

    const extraCols: string[] = [];
    const extraVals: unknown[] = [];
    if (caps.invoiceKind) {
      extraCols.push('invoice_kind');
      extraVals.push(kind);
    }
    if (caps.approvedBy) {
      extraCols.push('approved_by');
      extraVals.push(input.approvedBy ?? null);
    }
    const extraPlaceholders = extraVals.map((_, i) => `, $${7 + i}`).join('');

    // Owner-created invoices are confirmed on save, so they go straight to the
    // tenant. Invoice, line items, pending charges and the tenant notification
    // commit together; any failure leaves no invoice behind.
    let invoiceId: string;
    try {
      invoiceId = await withTransaction(async (q) => {
        const [invoice] = await q<{ id: string }>(
          `INSERT INTO invoices
             (tenancy_id, property_id, period_start, period_end, due_date, total_amount,
              status, sent_at, is_auto_generated${extraCols.map((c) => `, ${c}`).join('')})
           VALUES ($1,$2,$3,$4,$5,$6,'pending',now(),false${extraPlaceholders})
           RETURNING id`,
          [
            input.tenancyId,
            input.propertyId,
            input.periodStart,
            input.periodEnd,
            input.dueDate,
            totalAmount,
            ...extraVals,
          ],
        );

        for (const li of positiveItems) {
          const chargeKind =
            li.chargeKind ??
            inferChargeKind(
              li.description,
              li.chargeTypeId ? typeNameById.get(li.chargeTypeId) : null,
            );
          await q(
            `INSERT INTO invoice_line_items
               (invoice_id, charge_type_id, description, amount, charge_kind)
             VALUES ($1,$2,$3,$4,$5::invoice_charge_kind)`,
            [invoice.id, li.chargeTypeId ?? null, li.description, li.amount, chargeKind],
          );
        }

        if (willAttachPending) {
          await this.addPendingChargesToInvoice(input.tenancyId, invoice.id, q);
        }

        const [row] = await q<{
          total_amount: string;
          line_count: string;
          user_id: string;
          period_start: string;
          period_end: string;
          due_date: string;
        }>(
          `SELECT i.total_amount::text AS total_amount,
                  (SELECT COUNT(*) FROM invoice_line_items li
                    WHERE li.invoice_id = i.id)::text AS line_count,
                  t.user_id, i.period_start::text AS period_start,
                  i.period_end::text AS period_end, i.due_date::text AS due_date
           FROM invoices i JOIN tenancies t ON t.id = i.tenancy_id
           WHERE i.id = $1`,
          [invoice.id],
        );
        if (!(Number(row.total_amount) > 0) || Number(row.line_count) === 0) {
          throw new Error('Add at least one charge with an amount above 0.');
        }

        await insertNotificationTx(
          q,
          buildInvoiceSentNotification({
            id: invoice.id,
            tenancyId: input.tenancyId,
            propertyId: input.propertyId,
            tenantUserId: row.user_id,
            periodStart: row.period_start,
            periodEnd: row.period_end,
            dueDate: row.due_date,
            balance: Number(row.total_amount),
            today,
          }),
          hasNotificationData,
        );
        return invoice.id;
      });
    } catch (err: any) {
      if (err?.code === '23505') {
        throw new Error(
          'An invoice for this billing cycle already exists. Open it from Payments to edit it.',
        );
      }
      throw err;
    }

    return this.getById(invoiceId);
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
    approvedBy?: string | null;
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
      const latestCaps = await billingSchemaCaps();
      const [latest] = await query<{ id: string }>(
        `SELECT id FROM invoices
         WHERE tenancy_id = $1 AND property_id = $2
           ${latestCaps.invoiceKind ? `AND invoice_kind = 'cycle'` : ''}
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

    const caps = await billingSchemaCaps();
    const existing = await query<{ id: string }>(
      `SELECT id FROM invoices
       WHERE tenancy_id = $1
         AND period_start = $2::date
         AND period_end = $3::date
         ${caps.invoiceKind ? `AND invoice_kind = 'cycle'` : ''}
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
      invoiceKind: 'cycle',
      approvedBy: opts.approvedBy ?? null,
    });
  }

  async updateInvoice(
    invoiceId: string,
    propertyId: string,
    input: UpdateInvoiceInput,
  ) {
    await ensureBillingSchema();
    const caps = await billingSchemaCaps();

    const lineItems = input.lineItems.map((li) => ({
      ...li,
      amount: roundMoney(li.amount),
    }));
    const totalAmount = roundMoney(
      lineItems.reduce((sum, li) => sum + li.amount, 0),
    );
    assertInvoiceAmountsInRange([...lineItems.map((li) => li.amount), totalAmount]);
    const periodStart = input.periodStart.slice(0, 10);
    const periodEnd = input.periodEnd.slice(0, 10);
    const dueDate = input.dueDate.slice(0, 10);

    const chargeTypes = await this.listChargeTypes(propertyId);
    const typeNameById = new Map(
      chargeTypes.map((c: any) => [String(c.id), String(c.name)]),
    );

    const hasNotificationData = await ensureNotificationsSchema().catch(() => false);

    try {
      const found = await withTransaction(async (q) => {
        const [inv] = await q<{
          id: string;
          tenancy_id: string;
          tenant_user_id: string | null;
          sent_at: Date | null;
          is_auto_generated: boolean;
          period_start: string;
          period_end: string;
          due_date: string;
          total_amount: string;
          invoice_kind?: InvoiceKind;
          paid: string;
        }>(
          `SELECT i.id, i.tenancy_id, t.user_id AS tenant_user_id,
                  i.sent_at, i.is_auto_generated,
                  i.period_start::text AS period_start,
                  i.period_end::text AS period_end,
                  i.due_date::text AS due_date,
                  i.total_amount::text AS total_amount,
                  ${caps.invoiceKind ? 'i.invoice_kind,' : ''}
                  COALESCE((SELECT SUM(p.amount) FROM payments p
                            WHERE p.invoice_id = i.id), 0)::text AS paid
           FROM invoices i
           LEFT JOIN tenancies t ON t.id = i.tenancy_id
           WHERE i.id = $1 AND i.property_id = $2
           FOR UPDATE OF i`,
          [invoiceId, propertyId],
        );
        if (!inv) return false;

        const currentLines = await q<{
          id: string;
          description: string;
          amount: string;
          charge_type_id: string | null;
          meter_linked: boolean;
        }>(
          `SELECT li.id, li.description, li.amount::text AS amount, li.charge_type_id,
                  EXISTS (SELECT 1 FROM meter_readings mr
                          WHERE mr.invoice_line_item_id = li.id) AS meter_linked
           FROM invoice_line_items li WHERE li.invoice_id = $1`,
          [invoiceId],
        );
        const current: CurrentLine[] = currentLines.map((l) => ({
          id: l.id,
          description: l.description,
          amount: Number(l.amount),
          chargeTypeId: l.charge_type_id,
          meterLinked: l.meter_linked === true,
        }));
        const incoming: IncomingLine[] = lineItems.map((l) => ({
          description: l.description,
          amount: l.amount,
          chargeTypeId: l.chargeTypeId ?? null,
          chargeKind: l.chargeKind,
        }));
        const chargesChanged = !sameCharges(current, incoming);
        const kind: InvoiceKind =
          inv.invoice_kind ??
          (!inv.is_auto_generated && inv.period_start === inv.period_end ? 'adhoc' : 'cycle');
        const sent = inv.sent_at != null;

        const blocked = invoiceEditBlock(
          { sent, kind, total: Number(inv.total_amount), paid: Number(inv.paid) },
          {
            periodChanged: periodStart !== inv.period_start || periodEnd !== inv.period_end,
            dueDateChanged: dueDate !== inv.due_date,
            chargesChanged,
          },
        );
        if (blocked) throw blocked;
        if (sent && chargesChanged && !(totalAmount > 0)) {
          throw new Error('A sent invoice must keep at least one charge with an amount above 0.');
        }
        const plan = chargesChanged ? planLineItemChanges(current, incoming) : null;
        if (plan && plan.blocked.length > 0) {
          const names = plan.blocked.map((l) => `"${l.description}"`).join(', ');
          throw new InvoiceLockedError(
            `${names} ${plan.blocked.length === 1 ? 'comes' : 'come'} from a recorded meter reading, so ${plan.blocked.length === 1 ? 'it' : 'they'} can't be removed or renamed on this invoice. Keep the description; you can still change the amount.`,
            'meter_line_linked',
          );
        }

        await q(
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
            periodStart,
            periodEnd,
            dueDate,
            chargesChanged ? totalAmount : Number(inv.total_amount),
            invoiceId,
            propertyId,
          ],
        );

        // Unchanged lines keep their rows, so meter readings stay linked.
        if (plan) {
          if (plan.remove.length > 0) {
            await q(
              `DELETE FROM invoice_line_items li
               WHERE li.invoice_id = $1 AND li.id = ANY($2::uuid[])
                 AND NOT EXISTS (SELECT 1 FROM meter_readings mr
                                 WHERE mr.invoice_line_item_id = li.id)`,
              [invoiceId, plan.remove],
            );
          }
          for (const { id, line } of plan.update) {
            await q(
              `UPDATE invoice_line_items
               SET description = $1,
                   amount = $2,
                   charge_type_id = COALESCE($3::uuid, charge_type_id),
                   charge_kind = COALESCE($4::invoice_charge_kind, charge_kind)
               WHERE id = $5 AND invoice_id = $6`,
              [line.description, line.amount, line.chargeTypeId, line.chargeKind ?? null, id, invoiceId],
            );
          }
          for (const li of plan.insert) {
            const chargeKind =
              li.chargeKind ??
              inferChargeKind(
                li.description,
                li.chargeTypeId ? typeNameById.get(li.chargeTypeId) : null,
              );
            await q(
              `INSERT INTO invoice_line_items
                 (invoice_id, charge_type_id, description, amount, charge_kind)
               VALUES ($1,$2,$3,$4,$5::invoice_charge_kind)`,
              [invoiceId, li.chargeTypeId, li.description, li.amount, chargeKind],
            );
          }
        }

        const dueDateChanged = dueDate !== inv.due_date;
        if (sent && inv.tenant_user_id && (chargesChanged || dueDateChanged)) {
          const total = chargesChanged ? totalAmount : roundMoney(Number(inv.total_amount));
          await insertNotificationTx(
            q,
            buildInvoiceUpdatedNotification({
              id: inv.id,
              tenancyId: inv.tenancy_id,
              propertyId,
              tenantUserId: inv.tenant_user_id,
              periodStart: inv.period_start,
              periodEnd: inv.period_end,
              dueDate,
              total,
              balance: roundMoney(total - Number(inv.paid)),
              chargesChanged,
              dueDateChanged,
            }),
            hasNotificationData,
          );
        }
        return true;
      });
      if (!found) return null;
    } catch (err: any) {
      if (err?.code === '23505') {
        throw new Error(
          'Another invoice already covers a billing cycle starting on this date.',
        );
      }
      throw err;
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

    const hasNotificationData = await ensureNotificationsSchema().catch(() => false);

    const found = await withTransaction(async (q) => {
      const [inv] = await q<{
        id: string;
        tenancy_id: string;
        tenant_user_id: string | null;
        sent_at: Date | null;
        period_start: string;
        period_end: string;
        due_date: string;
        total_amount: string;
        paid: string;
      }>(
        `SELECT i.id, i.tenancy_id, t.user_id AS tenant_user_id, i.sent_at,
                i.period_start::text AS period_start,
                i.period_end::text AS period_end,
                i.due_date::text AS due_date,
                i.total_amount::text AS total_amount,
                COALESCE((SELECT SUM(p.amount) FROM payments p
                          WHERE p.invoice_id = i.id), 0)::text AS paid
         FROM invoices i
         LEFT JOIN tenancies t ON t.id = i.tenancy_id
         WHERE i.id = $1 AND i.property_id = $2
         FOR UPDATE OF i`,
        [invoiceId, propertyId],
      );
      if (!inv) return false;
      const dueDateChanged = due !== inv.due_date;
      const blocked = invoiceEditBlock(
        {
          sent: inv.sent_at != null,
          // Kind only matters for period changes, which this path never makes.
          kind: 'cycle',
          total: Number(inv.total_amount),
          paid: Number(inv.paid),
        },
        { periodChanged: false, dueDateChanged, chargesChanged: false },
      );
      if (blocked) throw blocked;
      if (!dueDateChanged) return true;

      await q(
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

      if (inv.sent_at != null && inv.tenant_user_id) {
        const total = roundMoney(Number(inv.total_amount));
        await insertNotificationTx(
          q,
          buildInvoiceUpdatedNotification({
            id: inv.id,
            tenancyId: inv.tenancy_id,
            propertyId,
            tenantUserId: inv.tenant_user_id,
            periodStart: inv.period_start,
            periodEnd: inv.period_end,
            dueDate: due,
            total,
            balance: roundMoney(total - Number(inv.paid)),
            chargesChanged: false,
            dueDateChanged: true,
          }),
          hasNotificationData,
        );
      }
      return true;
    });
    if (!found) return null;
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
      today = calendarDateInTimeZone(new Date(), DEFAULT_PROPERTY_TIME_ZONE);
    }

    // tenancy_status is ('active', 'ended', 'pending'); only active stays are billed.
    const tenancies = await query<GeneratorTenancyRow>(
      `SELECT id, full_name, monthly_rent, move_in_at, move_out_at, status
       FROM tenancies
       WHERE property_id = $1
         AND status = 'active'
         AND ($2::uuid IS NULL OR id = $2::uuid)`,
      [propertyId, onlyTenancyId ?? null],
    );

    const chargeTypes = await this.listChargeTypes(propertyId);
    const rentType = chargeTypes.find((c: any) => {
      const n = String(c.name).toLowerCase();
      return n === 'rent' || n.includes('rent');
    }) as { id?: string } | undefined;

    const caps = await billingSchemaCaps();
    const hasNotificationData = await ensureNotificationsSchema().catch(() => false);
    let ownerIds: string[] | undefined;

    let created = 0;
    for (const tenancy of tenancies) {
      // Cheap pre-check outside a transaction; the plan is recomputed under
      // the tenancy row lock before anything is written.
      const billed = await query<BilledRow>(billedCyclesSql(caps.invoiceKind), [tenancy.id]);
      const preview = planForTenancy(tenancy, billed, timeZone, today);
      if (!preview || preview.plan.cycles.length === 0) continue;

      // Without a recipient nobody would learn the drafts exist; leave the
      // cycles for the next run instead of creating silent drafts.
      ownerIds ??= await resolvePropertyOwnerIds(propertyId);
      if (ownerIds.length === 0) {
        console.warn(`[billing] no owner recipients for property ${propertyId}; drafts deferred`);
        return created;
      }
      const recipients = ownerIds;

      try {
        const result = await withTransaction(async (q) => {
          // Serialises concurrent runs and owner edits for this tenancy; the
          // second run re-reads committed invoices and plans nothing.
          const [locked] = await q<GeneratorTenancyRow>(
            `SELECT id, full_name, monthly_rent, move_in_at, move_out_at, status
             FROM tenancies
             WHERE id = $1 AND property_id = $2
             FOR UPDATE`,
            [tenancy.id, propertyId],
          );
          if (!locked || locked.status !== 'active') return { drafts: 0, gap: null };
          const billedNow = await q<BilledRow>(billedCyclesSql(caps.invoiceKind), [locked.id]);
          const planned = planForTenancy(locked, billedNow, timeZone, today);
          if (!planned || planned.plan.cycles.length === 0) return { drafts: 0, gap: null };

          const drafts = await this.insertDraftBatch(q, {
            propertyId,
            tenancyId: locked.id,
            tenantName: locked.full_name ?? 'Tenant',
            rent: planned.rent,
            rentTypeId: rentType?.id ?? null,
            cycles: planned.plan.cycles,
            recipients,
            hasInvoiceKind: caps.invoiceKind,
            hasNotificationData,
          });
          return { drafts, gap: planned.plan.gap };
        });
        created += result.drafts;
        if (result.drafts > 0 && result.gap) {
          console.warn(
            `[billing] tenancy ${tenancy.id}: ${result.gap.from}..${result.gap.to} is not covered by a cycle invoice (move-in date changed); owner review needed`,
          );
        }
      } catch (err) {
        // Whole batch rolled back; the next scheduled run retries it.
        console.error(`[billing] draft generation failed for tenancy ${tenancy.id}:`, err);
      }
    }

    return created;
  }

  /**
   * Inserts one tenancy's missing cycle drafts and notifies owners, all on the
   * caller's transaction. Returns the number of drafts actually created.
   * Concurrent runs are safe: the losing INSERT hits the unique index and
   * returns no row (ON CONFLICT DO NOTHING), so it never notifies.
   */
  async insertDraftBatch(
    q: TxQuery,
    opts: {
      propertyId: string;
      tenancyId: string;
      tenantName: string;
      rent: number;
      rentTypeId: string | null;
      cycles: { periodStart: string; periodEnd: string; dueDate: string }[];
      recipients: string[];
      hasInvoiceKind: boolean;
      hasNotificationData: boolean;
    },
  ): Promise<number> {
    const drafts: { id: string; periodStart: string; periodEnd: string }[] = [];
    const rent = roundMoney(opts.rent);
    for (const cycle of opts.cycles) {
      // Draft (sent_at NULL): hidden from the tenant until the owner sends it,
      // and never overdue — overdue only applies once it has been sent.
      const inserted = await q<{ id: string }>(
        `INSERT INTO invoices
           (tenancy_id, property_id, period_start, period_end, due_date, total_amount,
            status, sent_at, is_auto_generated${opts.hasInvoiceKind ? ', invoice_kind' : ''})
         SELECT $1, $2, $3::date, $4::date, $5::date, $6, 'pending'::invoice_status, NULL, true
                ${opts.hasInvoiceKind ? `, 'cycle'` : ''}
         WHERE NOT EXISTS (
           SELECT 1 FROM invoices
           WHERE tenancy_id = $1 AND period_start = $3::date
             ${opts.hasInvoiceKind ? `AND invoice_kind = 'cycle'` : ''}
         )
         ON CONFLICT DO NOTHING
         RETURNING id`,
        [
          opts.tenancyId,
          opts.propertyId,
          cycle.periodStart,
          cycle.periodEnd,
          cycle.dueDate,
          rent,
        ],
      );
      const invoiceId = inserted[0]?.id;
      if (!invoiceId) continue;

      // The rent line stores the amount at generation time; later edits to
      // tenancies.monthly_rent never touch existing drafts or sent invoices.
      const label = formatMonthLabel(cycle.periodStart.slice(0, 7));
      await q(
        `INSERT INTO invoice_line_items
           (invoice_id, charge_type_id, description, amount, charge_kind)
         VALUES ($1, $2, $3, $4, 'rent'::invoice_charge_kind)`,
        [invoiceId, opts.rentTypeId, `${label} Rent`, rent],
      );
      await this.addPendingChargesToInvoice(opts.tenancyId, invoiceId, q);
      drafts.push({
        id: invoiceId,
        periodStart: cycle.periodStart,
        periodEnd: cycle.periodEnd,
      });
    }

    if (drafts.length === 0) return 0;

    const latest = drafts[drafts.length - 1];
    const body =
      drafts.length === 1
        ? `${opts.tenantName}'s invoice for ${formatShortDate(latest.periodStart)} – ${formatShortDate(latest.periodEnd)} is ready. Review rent, utilities and due date, then send it.`
        : `${drafts.length} invoices for ${opts.tenantName} are ready (up to ${formatShortDate(latest.periodEnd)}). Review and send them.`;
    for (const userId of opts.recipients) {
      await insertNotificationTx(
        q,
        {
          userId,
          propertyId: opts.propertyId,
          type: 'invoice_draft_ready',
          title: 'Invoice ready for review',
          body,
          data: {
            route: '/invoice-review',
            invoice_id: latest.id,
            invoiceId: latest.id,
            tenancy_id: opts.tenancyId,
            tenancyId: opts.tenancyId,
            property_id: opts.propertyId,
            propertyId: opts.propertyId,
            draft_count: drafts.length,
          },
        },
        opts.hasNotificationData,
      );
    }
    return drafts.length;
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
      today = calendarDateInTimeZone(new Date(), DEFAULT_PROPERTY_TIME_ZONE);
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
             WHEN i2.sent_at IS NOT NULL AND i2.due_date < $2::date THEN 'overdue'
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
   * Owner approves a draft: mark it sent, record the approver and notify the
   * tenant in one transaction. If the notification insert fails nothing is
   * committed and the invoice stays a draft. Idempotent — a second call
   * returns the invoice without re-notifying.
   */
  async sendInvoice(invoiceId: string, propertyId: string, approvedBy: string) {
    await ensureBillingSchema();
    const caps = await billingSchemaCaps();
    const hasNotificationData = await ensureNotificationsSchema().catch(() => false);
    const today = await this.propertyToday(propertyId);

    const outcome = await withTransaction(async (q) => {
      const [row] = await q<{
        id: string;
        tenancy_id: string;
        sent_at: Date | null;
        total_amount: string;
        paid: string;
        user_id: string;
        period_start: string;
        period_end: string;
        due_date: string;
      }>(
        `SELECT i.id, i.tenancy_id, i.sent_at, i.total_amount::text AS total_amount,
                COALESCE((SELECT SUM(p.amount) FROM payments p
                          WHERE p.invoice_id = i.id), 0)::text AS paid,
                t.user_id, i.period_start::text AS period_start,
                i.period_end::text AS period_end, i.due_date::text AS due_date
         FROM invoices i JOIN tenancies t ON t.id = i.tenancy_id
         WHERE i.id = $1 AND i.property_id = $2
         FOR UPDATE OF i`,
        [invoiceId, propertyId],
      );
      if (!row) return 'not_found' as const;
      if (row.sent_at != null) return 'already_sent' as const;
      if (!(Number(row.total_amount) > 0)) {
        throw new Error('Add at least one charge with an amount above 0 before sending.');
      }

      // If the due date has already passed, the "sent" notice itself says so,
      // so the scheduled overdue notice is not sent a second time.
      await q(
        `UPDATE invoices
         SET sent_at = now(),
             ${caps.approvedBy ? 'approved_by = $4,' : ''}
             overdue_notified_at = CASE
               WHEN due_date < $3::date THEN now()
               ELSE overdue_notified_at
             END,
             updated_at = now()
         WHERE id = $1 AND property_id = $2 AND sent_at IS NULL`,
        caps.approvedBy
          ? [invoiceId, propertyId, today, approvedBy]
          : [invoiceId, propertyId, today],
      );

      await insertNotificationTx(
        q,
        buildInvoiceSentNotification({
          id: row.id,
          tenancyId: row.tenancy_id,
          propertyId,
          tenantUserId: row.user_id,
          periodStart: row.period_start,
          periodEnd: row.period_end,
          dueDate: row.due_date,
          balance: roundMoney(Number(row.total_amount) - Number(row.paid)),
          today,
        }),
        hasNotificationData,
      );
      return 'sent' as const;
    });

    if (outcome === 'not_found') return null;
    const invoice = await this.getById(invoiceId);
    return invoice ? { ...invoice, newly_sent: outcome === 'sent' } : null;
  }

  private async propertyToday(propertyId: string): Promise<string> {
    const [property] = await query<{ timezone: string | null }>(
      `SELECT timezone FROM properties WHERE id = $1`,
      [propertyId],
    );
    try {
      return calendarDateInTimeZone(new Date(), hostelBillingTimeZone(property?.timezone));
    } catch {
      return calendarDateInTimeZone(new Date(), DEFAULT_PROPERTY_TIME_ZONE);
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
    const clock = await propertyClock(String(invoice.property_id));
    const [fresh] = await query<any>(
      `SELECT i.*, t.full_name, u.phone, ${overdueFlagSql('$2')}
       FROM invoices i
       LEFT JOIN tenancies t ON t.id = i.tenancy_id
       LEFT JOIN users u ON u.id = t.user_id
       WHERE i.id = $1`,
      [invoiceId, clock.today],
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
    const clock = await propertyClock(propertyId);
    return query(
      `SELECT i.*, t.full_name, t.profile_photo_url, u.phone, n.name AS node_name,
              floor_node.name AS floor_name,
              COALESCE((SELECT SUM(amount) FROM payments WHERE invoice_id = i.id), 0) AS paid_amount,
              ${overdueFlagSql('$2')}
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
      [propertyId, clock.today],
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
    const [tenancy] = await query<{ property_id: string }>(
      `SELECT property_id FROM tenancies WHERE id = $1`,
      [tenancyId],
    );
    if (!tenancy) return [];
    const clock = await propertyClock(String(tenancy.property_id));
    const invoices = await query<any>(
      `SELECT i.*,
              COALESCE((SELECT SUM(amount) FROM payments WHERE invoice_id = i.id), 0) AS paid_amount,
              ${overdueFlagSql('$2')}
       FROM invoices i
       WHERE i.tenancy_id = $1
         AND i.sent_at IS NOT NULL
       ORDER BY i.due_date DESC`,
      [tenancyId, clock.today],
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
    propertyId: string,
    amount: number,
    method: string,
    note: string | undefined,
    recordedBy: string,
  ) {
    const value = roundMoney(amount);
    const recorded = await withTransaction(async (q) => {
      // Row lock serialises concurrent payments on the same invoice.
      const [invoice] = await q<{ total_amount: string; sent_at: Date | null }>(
        `SELECT total_amount, sent_at FROM invoices
         WHERE id = $1 AND property_id = $2
         FOR UPDATE`,
        [invoiceId, propertyId],
      );
      if (!invoice) return false;
      if (invoice.sent_at == null) {
        throw new Error('This invoice is still a draft. Send it to the tenant before recording a payment.');
      }
      const [{ paid }] = await q<{ paid: string }>(
        `SELECT COALESCE(SUM(amount), 0)::text AS paid
         FROM payments WHERE invoice_id = $1`,
        [invoiceId],
      );
      assertPaymentWithinBalance(value, Number(invoice.total_amount), Number(paid));
      await q(
        `INSERT INTO payments (invoice_id, amount, method, note, recorded_by)
         VALUES ($1,$2,$3,$4,$5)`,
        [invoiceId, value, method, note ?? null, recordedBy],
      );
      return true;
    });
    if (!recorded) return null;
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

    return { sent: true };
  }
}
