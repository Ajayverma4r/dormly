// modules/billing/billing-metrics.ts
//
// Shared rules for every billing summary (dashboard, analytics, reports,
// tenant dues). All fragments expect the invoice table aliased as `i`.

import { query } from '@config/db';
import {
  DEFAULT_PROPERTY_TIME_ZONE,
  calendarDateInTimeZone,
  hostelBillingTimeZone,
} from './hostel-billing-cycle';

/** Issued to the tenant. Drafts (sent_at NULL) are never dues. */
export const SENT_INVOICE_SQL = `i.sent_at IS NOT NULL`;

/**
 * Amount still owed: total minus recorded payments. Payments are summed in a
 * per-invoice subquery, so joins elsewhere cannot repeat them.
 */
export const INVOICE_BALANCE_SQL = `(i.total_amount - COALESCE((SELECT SUM(p.amount) FROM payments p WHERE p.invoice_id = i.id), 0))`;

/** Sent with money still owed. */
export const OUTSTANDING_INVOICE_SQL = `${SENT_INVOICE_SQL} AND ${INVOICE_BALANCE_SQL} > 0`;

/**
 * Outstanding and past its due date in the property's calendar — the same rule
 * as overdue notices, so partially paid invoices are included.
 * [todayParam] is the placeholder holding the property-local date.
 */
export function overdueInvoiceSql(todayParam: string): string {
  return `${OUTSTANDING_INVOICE_SQL} AND i.due_date < ${todayParam}::date`;
}

/**
 * Derived `is_overdue` response column for invoice rows, so clients never
 * judge overdue by the device date. The stored `status` is left untouched
 * (it keeps partially paid invoices as 'partial').
 */
export function overdueFlagSql(todayParam: string): string {
  return `COALESCE((${overdueInvoiceSql(todayParam)}), false) AS is_overdue`;
}

export type PropertyClock = {
  timeZone: string;
  /** YYYY-MM-DD in the property's time zone. */
  today: string;
  /** First day of the property-local month. */
  monthStart: string;
  /** First day of the following month. */
  nextMonthStart: string;
};

export function clockFor(timeZoneRaw: string | null | undefined, now = new Date()): PropertyClock {
  let timeZone = hostelBillingTimeZone(timeZoneRaw);
  let today: string;
  try {
    today = calendarDateInTimeZone(now, timeZone);
  } catch {
    timeZone = DEFAULT_PROPERTY_TIME_ZONE;
    today = calendarDateInTimeZone(now, timeZone);
  }
  const year = Number(today.slice(0, 4));
  const month = Number(today.slice(5, 7));
  const next = month === 12 ? `${year + 1}-01-01` : `${year}-${String(month + 1).padStart(2, '0')}-01`;
  return { timeZone, today, monthStart: `${today.slice(0, 7)}-01`, nextMonthStart: next };
}

/** Billing clock for a property (time zone falls back like invoice status refresh). */
export async function propertyClock(propertyId: string, now = new Date()): Promise<PropertyClock> {
  const [row] = await query<{ timezone: string | null }>(
    `SELECT timezone FROM properties WHERE id = $1`,
    [propertyId],
  ).catch(() => [] as { timezone: string | null }[]);
  return clockFor(row?.timezone, now);
}
