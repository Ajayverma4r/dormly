// modules/dashboard/dashboard-financials.ts
//
// Financial Overview for one selectable period, in the property's calendar.
// Collected = payments recorded in the period; Expenses = expenses dated in the
// period; Net Profit = Collected - Expenses. Periods still in progress are
// compared with the same elapsed span of the previous period (to-date).

import { query } from '@config/db';
import { propertyClock } from '@modules/billing/billing-metrics';

export const FINANCIAL_PERIODS = ['this_month', 'last_month', 'last_3_months', 'this_year'] as const;
export type FinancialPeriod = (typeof FINANCIAL_PERIODS)[number];

export function parseFinancialPeriod(raw: unknown): FinancialPeriod | null {
  if (raw === undefined || raw === null || raw === '') return 'this_month';
  return (FINANCIAL_PERIODS as readonly string[]).includes(String(raw))
    ? (raw as FinancialPeriod)
    : null;
}

/** [start, end) as YYYY-MM-DD dates. */
export type DateWindow = { start: string; end: string };

const ymd = (d: Date) => d.toISOString().slice(0, 10);
const parse = (s: string) => new Date(`${s}T00:00:00Z`);

function addDays(date: string, days: number): string {
  const d = parse(date);
  d.setUTCDate(d.getUTCDate() + days);
  return ymd(d);
}

/** Shifts by whole months, clamping the day (31 Mar - 1 month = 28/29 Feb). */
function addMonths(date: string, months: number): string {
  const d = parse(date);
  const day = d.getUTCDate();
  const target = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + months, 1));
  const lastDay = new Date(
    Date.UTC(target.getUTCFullYear(), target.getUTCMonth() + 1, 0),
  ).getUTCDate();
  target.setUTCDate(Math.min(day, lastDay));
  return ymd(target);
}

const monthStartOf = (date: string) => `${date.slice(0, 7)}-01`;

const minDate = (a: string, b: string) => (a < b ? a : b);

export function financialWindows(
  period: FinancialPeriod,
  today: string,
): { current: DateWindow; previous: DateWindow } {
  const tomorrow = addDays(today, 1);
  const monthStart = monthStartOf(today);
  switch (period) {
    case 'this_month': {
      const prevStart = addMonths(monthStart, -1);
      return {
        current: { start: monthStart, end: tomorrow },
        previous: { start: prevStart, end: minDate(addDays(addMonths(today, -1), 1), monthStart) },
      };
    }
    case 'last_month': {
      const start = addMonths(monthStart, -1);
      return {
        current: { start, end: monthStart },
        previous: { start: addMonths(monthStart, -2), end: start },
      };
    }
    case 'last_3_months': {
      const start = addMonths(monthStart, -2);
      return {
        current: { start, end: tomorrow },
        previous: {
          start: addMonths(monthStart, -5),
          end: minDate(addDays(addMonths(today, -3), 1), start),
        },
      };
    }
    case 'this_year': {
      const start = `${today.slice(0, 4)}-01-01`;
      return {
        current: { start, end: tomorrow },
        previous: {
          start: `${Number(today.slice(0, 4)) - 1}-01-01`,
          end: minDate(addDays(addMonths(today, -12), 1), start),
        },
      };
    }
  }
}

/** Whole-percent change, or null when there is nothing to compare against. */
export function percentChange(current: number, previous: number): number | null {
  if (!(previous > 0)) return null;
  return Math.round(((current - previous) / previous) * 100);
}

type Totals = { collected: number; expenses: number };

async function totalsFor(propertyId: string, timeZone: string, w: DateWindow): Promise<Totals> {
  const collectedSql = `(SELECT COALESCE(SUM(p.amount), 0)::text
       FROM payments p
       JOIN invoices i ON i.id = p.invoice_id
       WHERE i.property_id = $1
         AND (p.paid_at AT TIME ZONE $2::text)::date >= $3::date
         AND (p.paid_at AT TIME ZONE $2::text)::date < $4::date) AS collected`;
  const params = [propertyId, timeZone, w.start, w.end];
  try {
    const [row] = await query<{ collected: string; expenses: string }>(
      `SELECT ${collectedSql},
         (SELECT COALESCE(SUM(e.amount), 0)::text
          FROM expenses e
          WHERE e.property_id = $1
            AND e.expense_date >= $3::date
            AND e.expense_date < $4::date) AS expenses`,
      params,
    );
    return { collected: Number(row?.collected ?? 0), expenses: Number(row?.expenses ?? 0) };
  } catch (err) {
    // Databases without migration 013 have no expenses table.
    console.warn('[dashboard] financials with expenses failed, using payments only:', err);
    const [row] = await query<{ collected: string }>(`SELECT ${collectedSql}`, params);
    return { collected: Number(row?.collected ?? 0), expenses: 0 };
  }
}

const inclusive = (w: DateWindow) => ({ start: w.start, end_inclusive: addDays(w.end, -1) });

export async function getDashboardFinancials(propertyId: string, period: FinancialPeriod) {
  const clock = await propertyClock(propertyId);
  const windows = financialWindows(period, clock.today);
  const [current, previous] = await Promise.all([
    totalsFor(propertyId, clock.timeZone, windows.current),
    totalsFor(propertyId, clock.timeZone, windows.previous),
  ]);
  return {
    period,
    today: clock.today,
    range: inclusive(windows.current),
    collected: current.collected,
    expenses: current.expenses,
    net_profit: current.collected - current.expenses,
    previous: {
      range: inclusive(windows.previous),
      collected: previous.collected,
      expenses: previous.expenses,
      net_profit: previous.collected - previous.expenses,
    },
    change: {
      collected_pct: percentChange(current.collected, previous.collected),
      expenses_pct: percentChange(current.expenses, previous.expenses),
    },
  };
}
