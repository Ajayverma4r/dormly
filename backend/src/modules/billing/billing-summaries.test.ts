// Runs the real dashboard / analytics / report / tenancy-dues SQL against an
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

// Boot-time schema maintenance is not part of these summaries.
vi.mock('@modules/billing/billing.service', () => ({
  ensureBillingSchema: async () => undefined,
  assertMoveInEditAllowed: async () => undefined,
}));

const ORG_A = 'a0000000-0000-4000-8000-000000000000';
const ORG_B = 'b0000000-0000-4000-8000-000000000000';
const PROP_A = 'a1000000-0000-4000-8000-000000000000';
const PROP_B = 'b1000000-0000-4000-8000-000000000000';
const LEVEL = 'c0000000-0000-4000-8000-000000000000';

const T = {
  draftOnly: 'd1000000-0000-4000-8000-000000000001',
  sentUnpaid: 'd1000000-0000-4000-8000-000000000002',
  partial: 'd1000000-0000-4000-8000-000000000003',
  paid: 'd1000000-0000-4000-8000-000000000004',
  otherProperty: 'd1000000-0000-4000-8000-000000000005',
};
const I = {
  draft: 'e1000000-0000-4000-8000-000000000001',
  sentUnpaid: 'e1000000-0000-4000-8000-000000000002',
  partial: 'e1000000-0000-4000-8000-000000000003',
  paid: 'e1000000-0000-4000-8000-000000000004',
  overdueLastMonth: 'e1000000-0000-4000-8000-000000000005',
  otherProperty: 'e1000000-0000-4000-8000-000000000006',
};

let today = '';
let monthStart = '';
const addDays = (ymd: string, n: number) => {
  const d = new Date(`${ymd}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
};

beforeAll(async () => {
  const { PGlite } = await import('@electric-sql/pglite');
  pg.db = new PGlite();
  const { clockFor } = await import('./billing-metrics.js');
  const clock = clockFor('Asia/Kolkata');
  today = clock.today;
  monthStart = clock.monthStart;

  await pg.db.exec(`
    CREATE TABLE properties (id uuid PRIMARY KEY, organization_id uuid, timezone text);
    CREATE TABLE users (id uuid PRIMARY KEY, phone text, name text);
    CREATE TABLE hierarchy_levels (id uuid PRIMARY KEY, display_name text,
      supports_occupancy boolean, order_index int DEFAULT 0);
    CREATE TABLE hierarchy_nodes (id uuid PRIMARY KEY, property_id uuid, level_id uuid,
      parent_node_id uuid, name text, code text, is_active boolean DEFAULT true);
    CREATE TABLE tenancies (id uuid PRIMARY KEY, property_id uuid, node_id uuid, user_id uuid,
      full_name text, status text, monthly_rent numeric(12,2), kyc_status text,
      planned_move_out_at timestamptz, move_out_is_emergency boolean, move_out_at timestamptz,
      move_in_at timestamptz, aadhaar_number text, profile_photo_url text,
      created_at timestamptz DEFAULT now());
    CREATE TABLE invoices (id uuid PRIMARY KEY, tenancy_id uuid, property_id uuid,
      period_start date, period_end date, due_date date, total_amount numeric(12,2),
      status text, sent_at timestamptz, created_at timestamptz DEFAULT now());
    CREATE TABLE payments (id serial PRIMARY KEY, invoice_id uuid, amount numeric(12,2),
      method text DEFAULT 'cash', paid_at timestamptz DEFAULT now());
    CREATE TABLE complaints (id serial PRIMARY KEY, property_id uuid, status text);
    CREATE TABLE expenses (id serial PRIMARY KEY, property_id uuid, amount numeric(12,2),
      expense_date date);
  `);

  await pg.db.query(
    `INSERT INTO properties VALUES ($1, $2, 'Asia/Kolkata'), ($3, $4, 'Asia/Kolkata')`,
    [PROP_A, ORG_A, PROP_B, ORG_B],
  );
  await pg.db.query(`INSERT INTO hierarchy_levels VALUES ($1, 'Room', true, 0)`, [LEVEL]);

  const tenants: [string, string, string, number][] = [
    [T.draftOnly, PROP_A, 'Asha', 5000],
    [T.sentUnpaid, PROP_A, 'Bala', 4000],
    [T.partial, PROP_A, 'Chitra', 6000],
    [T.paid, PROP_A, 'Dev', 3000],
    [T.otherProperty, PROP_B, 'Other', 9999],
  ];
  for (const [id, prop, name, rent] of tenants) {
    // Node / user ids reuse the tenancy id with a different first digit.
    const node = `f${id.slice(1)}`;
    const user = `9${id.slice(1)}`;
    await pg.db.query(`INSERT INTO users VALUES ($1, $2, $3)`, [user, `+91 ${name}`, name]);
    await pg.db.query(
      `INSERT INTO hierarchy_nodes (id, property_id, level_id, name, code) VALUES ($1, $2, $3, $4, $4)`,
      [node, prop, LEVEL, `Room ${name}`],
    );
    await pg.db.query(
      `INSERT INTO tenancies (id, property_id, node_id, user_id, full_name, status, monthly_rent, kyc_status)
       VALUES ($1, $2, $3, $4, $5, 'active', $6, 'verified')`,
      [id, prop, node, user, name, rent],
    );
  }

  const sentThisMonth = new Date().toISOString();
  const sentLastMonth = `${addDays(monthStart, -2)}T06:00:00Z`;
  const invoices: [string, string, string, string, number, string, string | null][] = [
    // Draft, never sent, already "past due" — must not count anywhere.
    [I.draft, T.draftOnly, PROP_A, addDays(today, -10), 5000, 'pending', null],
    [I.sentUnpaid, T.sentUnpaid, PROP_A, addDays(today, 10), 4000, 'pending', sentThisMonth],
    [I.partial, T.partial, PROP_A, addDays(today, -3), 6000, 'partial', sentThisMonth],
    [I.paid, T.paid, PROP_A, addDays(today, -20), 3000, 'paid', sentThisMonth],
    [I.overdueLastMonth, T.sentUnpaid, PROP_A, addDays(today, -5), 2000, 'overdue', sentLastMonth],
    [I.otherProperty, T.otherProperty, PROP_B, addDays(today, -5), 9999, 'overdue', sentThisMonth],
  ];
  for (const [id, tenancy, prop, due, total, status, sentAt] of invoices) {
    await pg.db.query(
      `INSERT INTO invoices (id, tenancy_id, property_id, period_start, period_end, due_date,
                             total_amount, status, sent_at)
       VALUES ($1, $2, $3, $4::date - 35, $4::date - 6, $4, $5, $6, $7)`,
      [id, tenancy, prop, due, total, status, sentAt],
    );
  }
  // Two payments on one invoice: totals must not double count through joins.
  await pg.db.query(
    `INSERT INTO payments (invoice_id, amount) VALUES ($1, 1000), ($1, 1500), ($2, 3000), ($3, 50)`,
    [I.partial, I.paid, I.otherProperty],
  );
  // PGlite boot is slow when several in-memory databases start in parallel.
}, 60_000);

afterAll(async () => {
  await pg.db?.close();
});

describe('owner dashboard', () => {
  it('counts only sent invoices in dues, overdue and billed totals', async () => {
    const { DashboardService } = await import('../dashboard/dashboard.service.js');
    const dash = await new DashboardService().getPropertyDashboard(PROP_A);

    // 4000 sent unpaid + 3500 left on the partial + 2000 overdue; draft 5000 excluded.
    expect(dash.overview.rent_pending).toBe(9500);
    expect(dash.overview.tenants_with_dues).toBe(2);
    // Sent this (property-local) month: 4000 + 6000 + 3000. Draft and last month's excluded.
    expect(dash.overview.billed_this_month).toBe(13000);
    // Payments recorded this month (definition unchanged): 1000 + 1500 + 3000.
    expect(dash.overview.rent_received).toBe(5500);
  });

  it('lists overdue tenants by sent balance, including partially paid, never drafts', async () => {
    const { DashboardService } = await import('../dashboard/dashboard.service.js');
    const dash = await new DashboardService().getPropertyDashboard(PROP_A);

    expect(dash.actionable_insights.defaulters.map((d) => [d.name, d.amount_due, d.invoice_id])).toEqual([
      ['Chitra', 3500, I.partial],
      // Bala's 4000 invoice is not due yet; only the overdue 2000 shows.
      ['Bala', 2000, I.overdueLastMonth],
    ]);
  });

  it('keeps the existing occupancy and expected-rent figures', async () => {
    const { DashboardService } = await import('../dashboard/dashboard.service.js');
    const dash = await new DashboardService().getPropertyDashboard(PROP_A);

    expect(dash.hero_stats).toEqual({
      total_units: 4,
      occupied_units: 4,
      available_units: 0,
      expected_monthly_rent: 18000,
    });
    expect(dash.overview.total_active_tenants).toBe(4);
  });

  it('never mixes in another property', async () => {
    const { DashboardService } = await import('../dashboard/dashboard.service.js');
    const dash = await new DashboardService().getPropertyDashboard(PROP_B);

    expect(dash.overview.rent_pending).toBe(9949);
    expect(dash.overview.rent_received).toBe(50);
    expect(dash.actionable_insights.defaulters.map((d) => d.name)).toEqual(['Other']);
  });
});

describe('property analytics', () => {
  it('uses the same dues and overdue rules as the dashboard', async () => {
    const { AnalyticsService } = await import('../analytics/analytics.service.js');
    const a = await new AnalyticsService().getPropertyAnalytics(PROP_A);

    expect(a.pendingRent).toBe(9500);
    // Partial (past due) + last month's unpaid. The draft past its date is not overdue.
    expect(a.overdueCount).toBe(2);
    expect(a.totalRevenue).toBe(5500);
  });

  it('organization revenue sums each payment once', async () => {
    const { AnalyticsService } = await import('../analytics/analytics.service.js');
    const org = await new AnalyticsService().getOrganizationAnalytics(ORG_A);
    expect(org.totalRevenue).toBe(5500);
  });
});

describe('rent collection report', () => {
  it('lists only sent invoices with paid and pending per invoice', async () => {
    const { ReportsService } = await import('../reports/reports.service.js');
    const rows = await new ReportsService().getRentCollectionRows(
      PROP_A,
      addDays(today, -60),
      addDays(today, 60),
    );

    const byName = rows.map((r: any) => [
      r.full_name,
      Number(r.total_amount),
      Number(r.paid_amount),
      Number(r.total_amount) - Number(r.paid_amount),
    ]);
    expect(byName).toEqual([
      ['Dev', 3000, 3000, 0],
      ['Bala', 2000, 0, 2000],
      ['Chitra', 6000, 2500, 3500],
      ['Bala', 4000, 0, 4000],
    ]);
    expect(rows.map((r: any) => r.full_name)).not.toContain('Asha');
    // Calendar dates come back as text, so no server time-zone shift.
    expect(rows[0].due_date).toBe(addDays(today, -20));
  });
});

describe('tenancy dues flags', () => {
  it('has_due follows sent balances, not drafts or paid invoices', async () => {
    const { TenancyService } = await import('../tenancies/tenancy.service.js');
    const list = (await new TenancyService().listByProperty(PROP_A)) as any[];
    const flags = Object.fromEntries(
      list.map((t) => [t.full_name, [t.has_due, t.earliest_open_due_date, t.has_overdue]]),
    );

    expect(flags).toEqual({
      // The draft is past its date but is neither due nor overdue.
      Asha: [false, null, false],
      Bala: [true, addDays(today, -5), true],
      // Partially paid and past due counts as overdue.
      Chitra: [true, addDays(today, -3), true],
      Dev: [false, null, false],
    });
  });
});

describe('billing clock', () => {
  it('derives property-local today and month bounds, rolling over December', async () => {
    const { clockFor } = await import('./billing-metrics.js');
    // 31 Dec 20:00 UTC is already 1 Jan in Kolkata.
    const c = clockFor('Asia/Kolkata', new Date('2026-12-31T20:00:00Z'));
    expect(c).toEqual({
      timeZone: 'Asia/Kolkata',
      today: '2027-01-01',
      monthStart: '2027-01-01',
      nextMonthStart: '2027-02-01',
    });
    expect(clockFor(null, new Date('2026-12-15T00:00:00Z')).nextMonthStart).toBe('2027-01-01');
  });
});
