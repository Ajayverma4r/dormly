// Financial Overview periods: pure date windows, plus the real SQL against an
// in-memory Postgres (PGlite). No server, no network, nothing persisted.
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';

const pg = vi.hoisted(() => ({ db: null as any }));

vi.mock('@config/db', () => {
  const run = async (sql: string, params?: unknown[]) =>
    (await pg.db.query(sql, params ?? [])).rows;
  return {
    query: run,
    withTransaction: async (fn: (q: typeof run) => Promise<unknown>) => fn(run),
  };
});

// 13 Oct 2026, 15:30 in Kolkata.
const NOW = new Date('2026-10-13T10:00:00Z');

vi.mock('@modules/billing/billing-metrics', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../billing/billing-metrics.js')>();
  return {
    ...actual,
    propertyClock: async () => actual.clockFor('Asia/Kolkata', NOW),
  };
});

import {
  financialWindows,
  getDashboardFinancials,
  parseFinancialPeriod,
  percentChange,
} from './dashboard-financials';

describe('financialWindows', () => {
  it('this month runs to today and compares with the same days of last month', () => {
    expect(financialWindows('this_month', '2026-10-13')).toEqual({
      current: { start: '2026-10-01', end: '2026-10-14' },
      previous: { start: '2026-09-01', end: '2026-09-14' },
    });
  });

  it('this month on the 31st compares with the whole shorter previous month', () => {
    expect(financialWindows('this_month', '2026-03-31')).toEqual({
      current: { start: '2026-03-01', end: '2026-04-01' },
      previous: { start: '2026-02-01', end: '2026-03-01' },
    });
  });

  it('last month is the full previous calendar month, across a year boundary', () => {
    expect(financialWindows('last_month', '2026-01-15')).toEqual({
      current: { start: '2025-12-01', end: '2026-01-01' },
      previous: { start: '2025-11-01', end: '2025-12-01' },
    });
  });

  it('last 3 months includes the current month to date', () => {
    expect(financialWindows('last_3_months', '2026-10-13')).toEqual({
      current: { start: '2026-08-01', end: '2026-10-14' },
      previous: { start: '2026-05-01', end: '2026-07-14' },
    });
  });

  it('this year compares with last year to the same date, including 29 Feb', () => {
    expect(financialWindows('this_year', '2026-10-13')).toEqual({
      current: { start: '2026-01-01', end: '2026-10-14' },
      previous: { start: '2025-01-01', end: '2025-10-14' },
    });
    expect(financialWindows('this_year', '2028-02-29').previous).toEqual({
      start: '2027-01-01',
      end: '2027-03-01',
    });
  });
});

describe('period parsing and percent change', () => {
  it('defaults to this month and rejects unknown periods', () => {
    expect(parseFinancialPeriod(undefined)).toBe('this_month');
    expect(parseFinancialPeriod('last_3_months')).toBe('last_3_months');
    expect(parseFinancialPeriod('forever')).toBeNull();
  });

  it('gives no percentage when there is nothing to compare against', () => {
    expect(percentChange(1200, 1000)).toBe(20);
    expect(percentChange(500, 1000)).toBe(-50);
    expect(percentChange(1000, 0)).toBeNull();
  });
});

const PROP = 'a1000000-0000-4000-8000-000000000000';
const OTHER = 'b1000000-0000-4000-8000-000000000000';

describe('getDashboardFinancials (SQL)', () => {
  beforeAll(async () => {
    const { PGlite } = await import('@electric-sql/pglite');
    pg.db = new PGlite();
    await pg.db.exec(`
      CREATE TABLE invoices (id TEXT PRIMARY KEY, property_id UUID NOT NULL);
      CREATE TABLE payments (id SERIAL PRIMARY KEY, invoice_id TEXT NOT NULL,
                             amount NUMERIC NOT NULL, paid_at TIMESTAMPTZ NOT NULL);
      CREATE TABLE expenses (id SERIAL PRIMARY KEY, property_id UUID NOT NULL,
                             amount NUMERIC NOT NULL, expense_date DATE NOT NULL);
      INSERT INTO invoices VALUES ('inv-a', '${PROP}'), ('inv-b', '${OTHER}');
      INSERT INTO payments (invoice_id, amount, paid_at) VALUES
        ('inv-a', 5000, '2026-10-05T06:00:00Z'),
        -- 1 Oct 01:30 in Kolkata, still 30 Sep in UTC: belongs to October.
        ('inv-a', 1000, '2026-09-30T20:00:00Z'),
        ('inv-a', 4000, '2026-09-10T06:00:00Z'),
        -- After 13 Sep: outside the to-date comparison window.
        ('inv-a', 9999, '2026-09-20T06:00:00Z'),
        ('inv-a', 3000, '2026-08-15T06:00:00Z'),
        ('inv-b', 7777, '2026-10-05T06:00:00Z');
      INSERT INTO expenses (property_id, amount, expense_date) VALUES
        ('${PROP}', 1500, '2026-10-02'),
        ('${PROP}', 1000, '2026-09-05'),
        ('${PROP}', 400, '2026-09-25'),
        ('${OTHER}', 8888, '2026-10-02');
    `);
  }, 60_000);

  afterAll(async () => {
    await pg.db?.close();
  });

  it('this month: property-local dates, this property only, compared to date', async () => {
    const f = await getDashboardFinancials(PROP, 'this_month');
    expect(f).toMatchObject({
      period: 'this_month',
      today: '2026-10-13',
      range: { start: '2026-10-01', end_inclusive: '2026-10-13' },
      collected: 6000,
      expenses: 1500,
      net_profit: 4500,
      previous: {
        range: { start: '2026-09-01', end_inclusive: '2026-09-13' },
        collected: 4000,
        expenses: 1000,
        net_profit: 3000,
      },
      change: { collected_pct: 50, expenses_pct: 50 },
    });
  });

  it('last month uses the whole of September against August', async () => {
    const f = await getDashboardFinancials(PROP, 'last_month');
    expect(f.range).toEqual({ start: '2026-09-01', end_inclusive: '2026-09-30' });
    expect(f.collected).toBe(4000 + 9999);
    expect(f.expenses).toBe(1400);
    expect(f.previous.collected).toBe(3000);
    expect(f.change.expenses_pct).toBeNull();
  });

  it('this year adds everything so far', async () => {
    const f = await getDashboardFinancials(PROP, 'this_year');
    expect(f.collected).toBe(5000 + 1000 + 4000 + 9999 + 3000);
    expect(f.expenses).toBe(2900);
    expect(f.change.collected_pct).toBeNull();
  });
});
