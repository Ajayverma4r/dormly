// The derived `is_overdue` / `has_overdue` response fields use the property's
// calendar, not the server or device clock. Real SQL on in-memory Postgres
// (PGlite); no server, no network, nothing persisted.
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest';

const pg = vi.hoisted(() => ({ db: null as any }));

vi.mock('@config/db', () => {
  const run = async (sql: string, params?: unknown[]) =>
    (await pg.db.query(sql, params ?? [])).rows;
  return {
    query: run,
    withTransaction: async (fn: (q: typeof run) => Promise<unknown>) => fn(run),
  };
});

const PROP_IN = 'a1000000-0000-4000-8000-000000000000'; // Asia/Kolkata (UTC+5:30)
const PROP_NY = 'b1000000-0000-4000-8000-000000000000'; // America/New_York (UTC-5 in Nov)
const PROP_UTC = 'b2000000-0000-4000-8000-000000000000'; // explicitly configured UTC
const PROP_BAD = 'b3000000-0000-4000-8000-000000000000'; // invalid zone → Asia/Kolkata
const LEVEL = 'c0000000-0000-4000-8000-000000000000';
const T_IN = 'd1000000-0000-4000-8000-000000000001';
const T_NY = 'd1000000-0000-4000-8000-000000000002';
const T_UTC = 'd1000000-0000-4000-8000-000000000003';
const T_BAD = 'd1000000-0000-4000-8000-000000000004';
const I = {
  dueUnpaid: 'e1000000-0000-4000-8000-000000000001',
  duePartial: 'e1000000-0000-4000-8000-000000000002',
  draftPast: 'e1000000-0000-4000-8000-000000000003',
  paidPast: 'e1000000-0000-4000-8000-000000000004',
  nyDue: 'e1000000-0000-4000-8000-000000000005',
  utcDue: 'e1000000-0000-4000-8000-000000000006',
  badDue: 'e1000000-0000-4000-8000-000000000007',
};
const DUE = '2026-11-15';

// 23:59 on 15 Nov in Kolkata / one minute later it is 16 Nov there.
const IN_BEFORE_MIDNIGHT = '2026-11-15T18:29:00Z';
const IN_AFTER_MIDNIGHT = '2026-11-15T18:31:00Z';
// 16 Nov 08:30 in Kolkata but still 15 Nov 22:00 in New York.
const NY_STILL_DUE_DAY = '2026-11-16T03:00:00Z';
const NY_AFTER_MIDNIGHT = '2026-11-16T05:01:00Z';
const UTC_BEFORE_MIDNIGHT = '2026-11-15T23:59:00Z';
const UTC_AFTER_MIDNIGHT = '2026-11-16T00:01:00Z';

async function service() {
  const { BillingService } = await import('./billing.service.js');
  const s = new BillingService();
  // Cycle generation and stored-status refresh are outside this check; the
  // derived flag must not depend on them.
  vi.spyOn(s, 'ensureHostelPgAnniversaryInvoices').mockResolvedValue(0 as never);
  vi.spyOn(s, 'refreshHostelInvoiceStatuses').mockResolvedValue(undefined);
  return s;
}

function at(iso: string) {
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.setSystemTime(new Date(iso));
}

const flags = (rows: any[]) => Object.fromEntries(rows.map((r) => [r.id, r.is_overdue]));

beforeAll(async () => {
  const { PGlite } = await import('@electric-sql/pglite');
  pg.db = new PGlite();
  await pg.db.exec(`
    CREATE TABLE properties (id uuid PRIMARY KEY, timezone text);
    CREATE TABLE users (id uuid PRIMARY KEY, phone text, name text);
    CREATE TABLE hierarchy_levels (id uuid PRIMARY KEY, display_name text);
    CREATE TABLE hierarchy_nodes (id uuid PRIMARY KEY, property_id uuid, level_id uuid,
      parent_node_id uuid, name text);
    CREATE TABLE tenancies (id uuid PRIMARY KEY, property_id uuid, node_id uuid, user_id uuid,
      full_name text, status text, profile_photo_url text, created_at timestamptz DEFAULT now());
    CREATE TABLE invoices (id uuid PRIMARY KEY, tenancy_id uuid, property_id uuid,
      period_start date, period_end date, due_date date, total_amount numeric(12,2),
      status text, sent_at timestamptz, created_at timestamptz DEFAULT now());
    CREATE TABLE payments (id serial PRIMARY KEY, invoice_id uuid, amount numeric(12,2),
      paid_at timestamptz DEFAULT now());
    CREATE TABLE charge_types (id uuid PRIMARY KEY, name text);
    CREATE TABLE invoice_line_items (id serial PRIMARY KEY, invoice_id uuid,
      charge_type_id uuid, description text, amount numeric(12,2), charge_kind text);
  `);
  await pg.db.query(
    `INSERT INTO properties VALUES ($1, 'Asia/Kolkata'), ($2, 'America/New_York'),
                                  ($3, 'UTC'), ($4, 'Not/A_Zone')`,
    [PROP_IN, PROP_NY, PROP_UTC, PROP_BAD],
  );
  await pg.db.query(`INSERT INTO hierarchy_levels VALUES ($1, 'Room')`, [LEVEL]);
  for (const [tenancy, prop, name] of [
    [T_IN, PROP_IN, 'Asha'],
    [T_NY, PROP_NY, 'Nora'],
    [T_UTC, PROP_UTC, 'Uma'],
    [T_BAD, PROP_BAD, 'Bina'],
  ]) {
    const node = `f${tenancy.slice(1)}`;
    const user = `9${tenancy.slice(1)}`;
    await pg.db.query(`INSERT INTO users VALUES ($1, '+1', $2)`, [user, name]);
    await pg.db.query(
      `INSERT INTO hierarchy_nodes (id, property_id, level_id, name) VALUES ($1, $2, $3, $4)`,
      [node, prop, LEVEL, `Room ${name}`],
    );
    await pg.db.query(
      `INSERT INTO tenancies (id, property_id, node_id, user_id, full_name, status)
       VALUES ($1, $2, $3, $4, $5, 'active')`,
      [tenancy, prop, node, user, name],
    );
  }
  const rows: [string, string, string, string, number, string, string | null][] = [
    [I.dueUnpaid, T_IN, PROP_IN, DUE, 5000, 'pending', '2026-11-01T06:00:00Z'],
    // Stored status stays 'partial' even once past due.
    [I.duePartial, T_IN, PROP_IN, DUE, 4000, 'partial', '2026-11-01T06:00:00Z'],
    [I.draftPast, T_IN, PROP_IN, '2026-11-01', 3000, 'pending', null],
    [I.paidPast, T_IN, PROP_IN, '2026-11-01', 2000, 'paid', '2026-10-01T06:00:00Z'],
    [I.nyDue, T_NY, PROP_NY, DUE, 1000, 'pending', '2026-11-01T06:00:00Z'],
    [I.utcDue, T_UTC, PROP_UTC, DUE, 1000, 'pending', '2026-11-01T06:00:00Z'],
    [I.badDue, T_BAD, PROP_BAD, DUE, 1000, 'pending', '2026-11-01T06:00:00Z'],
  ];
  for (const [id, tenancy, prop, due, total, status, sentAt] of rows) {
    await pg.db.query(
      `INSERT INTO invoices (id, tenancy_id, property_id, period_start, period_end, due_date,
                             total_amount, status, sent_at)
       VALUES ($1, $2, $3, $4::date - 35, $4::date - 6, $4, $5, $6, $7)`,
      [id, tenancy, prop, due, total, status, sentAt],
    );
  }
  await pg.db.query(
    `INSERT INTO payments (invoice_id, amount) VALUES ($1, 1500), ($2, 2000)`,
    [I.duePartial, I.paidPast],
  );
  vi.spyOn(console, 'warn').mockImplementation(() => undefined);
  // PGlite boot is slow when several in-memory databases start in parallel.
}, 60_000);

afterEach(() => {
  vi.useRealTimers();
});

afterAll(async () => {
  await pg.db?.close();
});

describe('owner invoice list is_overdue', () => {
  it('an invoice due today is not overdue at 23:59 property time', async () => {
    at(IN_BEFORE_MIDNIGHT);
    const rows = (await (await service()).listByProperty(PROP_IN)) as any[];
    expect(flags(rows)).toEqual({
      [I.dueUnpaid]: false,
      [I.duePartial]: false,
      [I.draftPast]: false,
      [I.paidPast]: false,
    });
  });

  it('unpaid and partially paid become overdue just after property midnight', async () => {
    at(IN_AFTER_MIDNIGHT);
    const rows = (await (await service()).listByProperty(PROP_IN)) as any[];
    expect(flags(rows)).toEqual({
      [I.dueUnpaid]: true,
      [I.duePartial]: true,
      // Drafts and fully paid invoices are never overdue.
      [I.draftPast]: false,
      [I.paidPast]: false,
    });
    // The derived flag does not rewrite the stored status.
    expect(rows.find((r) => r.id === I.duePartial).status).toBe('partial');
  });

  it('uses each property\'s own time zone, not the server clock', async () => {
    at(NY_STILL_DUE_DAY);
    const s = await service();
    expect(flags((await s.listByProperty(PROP_IN)) as any[])[I.dueUnpaid]).toBe(true);
    expect(flags((await s.listByProperty(PROP_NY)) as any[])).toEqual({ [I.nyDue]: false });

    at(NY_AFTER_MIDNIGHT);
    expect(flags((await s.listByProperty(PROP_NY)) as any[])).toEqual({ [I.nyDue]: true });
  });

  it('an explicitly configured UTC property turns its day at UTC midnight', async () => {
    const s = await service();
    // Already 16 Nov in Kolkata, still 15 Nov in UTC.
    at(IN_AFTER_MIDNIGHT);
    expect(flags((await s.listByProperty(PROP_UTC)) as any[])).toEqual({ [I.utcDue]: false });
    at(UTC_BEFORE_MIDNIGHT);
    expect(flags((await s.listByProperty(PROP_UTC)) as any[])).toEqual({ [I.utcDue]: false });
    at(UTC_AFTER_MIDNIGHT);
    expect(flags((await s.listByProperty(PROP_UTC)) as any[])).toEqual({ [I.utcDue]: true });
  });

  it('an invalid property zone falls back to the Asia/Kolkata calendar', async () => {
    const s = await service();
    at(IN_BEFORE_MIDNIGHT);
    expect(flags((await s.listByProperty(PROP_BAD)) as any[])).toEqual({ [I.badDue]: false });
    at(IN_AFTER_MIDNIGHT);
    expect(flags((await s.listByProperty(PROP_BAD)) as any[])).toEqual({ [I.badDue]: true });
  });

  it('never returns another property\'s invoices', async () => {
    at(IN_AFTER_MIDNIGHT);
    const rows = (await (await service()).listByProperty(PROP_NY)) as any[];
    expect(rows.map((r) => r.id)).toEqual([I.nyDue]);
  });
});

describe('invoice detail and tenant invoices is_overdue', () => {
  it('invoice detail flips across property midnight', async () => {
    const s = await service();
    at(IN_BEFORE_MIDNIGHT);
    expect((await s.getById(I.duePartial))?.is_overdue).toBe(false);
    at(IN_AFTER_MIDNIGHT);
    expect((await s.getById(I.duePartial))?.is_overdue).toBe(true);
  });

  it('tenant list carries the flag and still hides drafts', async () => {
    const s = await service();
    at(IN_BEFORE_MIDNIGHT);
    const before = (await s.listByTenancy(T_IN)) as any[];
    expect(flags(before)).toEqual({
      [I.dueUnpaid]: false,
      [I.duePartial]: false,
      [I.paidPast]: false,
    });
    at(IN_AFTER_MIDNIGHT);
    expect(flags((await s.listByTenancy(T_IN)) as any[])).toEqual({
      [I.dueUnpaid]: true,
      [I.duePartial]: true,
      [I.paidPast]: false,
    });
  });

  it('unknown tenancy returns nothing', async () => {
    const s = await service();
    expect(await s.listByTenancy('d9999999-0000-4000-8000-000000000000')).toEqual([]);
  });
});

describe('tenancy list has_overdue', () => {
  it('follows the property calendar across midnight', async () => {
    const { TenancyService } = await import('../tenancies/tenancy.service.js');
    at(IN_BEFORE_MIDNIGHT);
    let [row] = (await new TenancyService().listByProperty(PROP_IN)) as any[];
    expect([row.has_due, row.has_overdue]).toEqual([true, false]);

    at(IN_AFTER_MIDNIGHT);
    [row] = (await new TenancyService().listByProperty(PROP_IN)) as any[];
    expect([row.has_due, row.has_overdue]).toEqual([true, true]);
  });
});
