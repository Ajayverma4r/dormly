// Global search through the real router, auth guard, context check and SQL on
// an in-memory Postgres (PGlite). No server process, network or real database.
import type { AddressInfo } from 'net';
import express from 'express';
import jwt from 'jsonwebtoken';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';

process.env.DATABASE_URL ??= 'postgres://test:test@127.0.0.1:1/test';
process.env.JWT_ACCESS_SECRET = 'search-test-secret';
process.env.JWT_REFRESH_SECRET ??= 'test';
process.env.RAZORPAY_KEY_ID ??= 'rzp_test_x';
process.env.RAZORPAY_KEY_SECRET ??= 'test';
process.env.RAZORPAY_WEBHOOK_SECRET ??= 'test';

const pg = vi.hoisted(() => ({ db: null as any, log: [] as string[] }));

vi.mock('@config/db', () => {
  const run = async (sql: string, params?: unknown[]) => {
    pg.log.push(sql);
    return (await pg.db.query(sql, params ?? [])).rows;
  };
  return {
    query: run,
    withTransaction: async (fn: (q: typeof run) => Promise<unknown>) => {
      await pg.db.query('BEGIN');
      try {
        const result = await fn(run);
        await pg.db.query('COMMIT');
        return result;
      } catch (err) {
        await pg.db.query('ROLLBACK');
        throw err;
      }
    },
  };
});

vi.mock('@modules/notifications/notify', () => ({
  ensureLiveOpsSchema: async () => undefined,
  notifyPropertyOwners: async () => 0,
  createNotification: async () => true,
}));

const id = (prefix: string, n: number) => `${prefix}000000-0000-4000-8000-${String(n).padStart(12, '0')}`;

const ORG_1 = id('01', 1);
const ORG_2 = id('02', 2);
const P1 = id('11', 1); // hostel, ORG_1
const P2 = id('12', 2); // apartment, ORG_1
const P3 = id('13', 3); // hostel, ORG_2

const USER = {
  owner: id('31', 1),
  admin: id('31', 2),
  manager: id('31', 3),
  staff: id('31', 4),
  staff2: id('31', 5),
  tenantA: id('31', 6),
  tenantB: id('31', 7),
  tenantC: id('31', 8),
  tenantX: id('31', 9),
  oldTenant: id('31', 10),
  otherStaff: id('31', 11),
};

const LEVEL = {
  p1Floor: id('61', 1),
  p1Room: id('61', 2),
  p1Bed: id('61', 3),
  p2Flat: id('62', 4),
  p3Room: id('63', 5),
};

const NODE = {
  floor1: id('21', 1),
  room101: id('21', 2),
  bed101a: id('21', 3),
  bed101b: id('21', 4),
  room102: id('21', 5),
  bed102a: id('21', 6),
  room103: id('21', 7),
  bed103a: id('21', 8),
  flat201: id('22', 9),
  flat202: id('22', 10),
  p3room101: id('23', 11),
};

const TEN = {
  a: id('41', 1),
  b: id('41', 2),
  c: id('42', 3),
  x: id('43', 4),
  old: id('41', 5),
};

const COMPLAINT = { mineA: id('51', 1), otherStaff: id('51', 2), assignedToMe: id('51', 3), otherOrg: id('53', 4) };
const GATE = { tenantC: id('52', 1), otherOrg: id('53', 2), hostel: id('51', 3) };
const INVOICE = {
  overdueA: id('71', 1),
  draftA: id('71', 2),
  paidB: id('71', 3),
  pendingC: id('72', 4),
  overdueX: id('73', 5),
  overdueA2: id('71', 6),
  draftB: id('71', 7),
  overdueOld: id('71', 8),
};
const PAYMENT = { a: id('81', 1), b: id('81', 2), x: id('83', 3) };
const READING = { c: id('91', 1), x: id('93', 2) };
const MENU = { p1: id('a1', 1), p3: id('a3', 2) };

const token = (claims: Record<string, unknown>) =>
  jwt.sign(claims, process.env.JWT_ACCESS_SECRET!, { expiresIn: '5m' });
const orgToken = (user: string, org: string, role: 'owner' | 'admin') =>
  token({ sub: user, ctxType: 'organization', ctxId: org, ctxRole: role, ctxPropertyId: null });
const propToken = (user: string, property: string, role: 'manager' | 'staff') =>
  token({ sub: user, ctxType: 'organization', ctxId: property, ctxRole: role, ctxPropertyId: property });
const tenantToken = (user: string, tenancy: string, property: string) =>
  token({ sub: user, ctxType: 'tenancy', ctxId: tenancy, ctxRole: 'tenant', ctxPropertyId: property });

const TOKENS = {
  owner: () => orgToken(USER.owner, ORG_1, 'owner'),
  admin: () => orgToken(USER.admin, ORG_1, 'admin'),
  manager: () => propToken(USER.manager, P1, 'manager'),
  staff: () => propToken(USER.staff, P1, 'staff'),
  tenantA: () => tenantToken(USER.tenantA, TEN.a, P1),
  tenantC: () => tenantToken(USER.tenantC, TEN.c, P2),
};

let baseUrl = '';
let server: ReturnType<express.Express['listen']>;
let rateLimit: typeof import('./search.routes.js');

async function seed() {
  const q = (sql: string, params: unknown[] = []) => pg.db.query(sql, params);
  await q(
    `INSERT INTO properties (id, organization_id, name, property_type_key, timezone, city) VALUES
       ($1, $4, 'Sunrise PG', 'hostel_pg', 'Asia/Kolkata', 'Pune'),
       ($2, $4, 'Lake View Apartments', 'apartment', 'Asia/Kolkata', 'Pune'),
       ($3, $5, 'Other Org PG', 'hostel_pg', 'Asia/Kolkata', 'Mumbai')`,
    [P1, P2, P3, ORG_1, ORG_2],
  );
  await q(
    `INSERT INTO memberships (user_id, organization_id, role) VALUES ($1, $3, 'owner'), ($2, $3, 'admin')`,
    [USER.owner, USER.admin, ORG_1],
  );
  await q(
    `INSERT INTO property_staff_assignments (user_id, property_id, role, status) VALUES
       ($1, $5, 'manager', 'active'), ($2, $5, 'staff', 'active'), ($3, $5, 'staff', 'active'),
       ($4, $6, 'staff', 'active')`,
    [USER.manager, USER.staff, USER.staff2, USER.otherStaff, P1, P3],
  );
  const users: [string, string, string][] = [
    [USER.owner, 'Olivia Owner', '9000000001'],
    [USER.admin, 'Arun Admin', '9000000002'],
    [USER.manager, 'Meena Manager', '9000000003'],
    [USER.staff, 'Suresh Kumar', '9000000004'],
    [USER.staff2, 'Suresh Staff', '9000000005'],
    [USER.tenantA, 'Ravi Kumar', '9876543210'],
    [USER.tenantB, 'Sita Devi', '9123456789'],
    [USER.tenantC, 'Ravi Shah', '9000011111'],
    [USER.tenantX, 'Ravi Other', '9000022222'],
    [USER.oldTenant, 'Mohan Lal', '9000033333'],
    [USER.otherStaff, 'Suresh Other', '9000044444'],
  ];
  for (const [uid, name, phone] of users) {
    await q(`INSERT INTO users (id, name, phone) VALUES ($1, $2, $3)`, [uid, name, phone]);
  }
  await q(
    `INSERT INTO hierarchy_levels (id, property_id, display_name, internal_key, parent_level_id, supports_occupancy) VALUES
       ($1, $6, 'Floor', 'floor', NULL, false),
       ($2, $6, 'Room', 'room', $1, false),
       ($3, $6, 'Bed', 'bed', $2, true),
       ($4, $7, 'Flat', 'flat', NULL, true),
       ($5, $8, 'Room', 'room', NULL, true)`,
    [LEVEL.p1Floor, LEVEL.p1Room, LEVEL.p1Bed, LEVEL.p2Flat, LEVEL.p3Room, P1, P2, P3],
  );
  const nodes: [string, string, string, string | null, string][] = [
    [NODE.floor1, P1, LEVEL.p1Floor, null, 'Floor 1'],
    [NODE.room101, P1, LEVEL.p1Room, NODE.floor1, 'Room 101'],
    [NODE.bed101a, P1, LEVEL.p1Bed, NODE.room101, '101-A'],
    [NODE.bed101b, P1, LEVEL.p1Bed, NODE.room101, '101-B'],
    [NODE.room102, P1, LEVEL.p1Room, NODE.floor1, 'Room 102'],
    [NODE.bed102a, P1, LEVEL.p1Bed, NODE.room102, '102-A'],
    [NODE.room103, P1, LEVEL.p1Room, NODE.floor1, 'Room 103'],
    [NODE.bed103a, P1, LEVEL.p1Bed, NODE.room103, '103-A'],
    [NODE.flat201, P2, LEVEL.p2Flat, null, 'Flat 201'],
    [NODE.flat202, P2, LEVEL.p2Flat, null, 'Flat 202'],
    [NODE.p3room101, P3, LEVEL.p3Room, null, 'Room 101'],
  ];
  for (const [nid, property, level, parent, name] of nodes) {
    await q(
      `INSERT INTO hierarchy_nodes (id, property_id, level_id, parent_node_id, name) VALUES ($1, $2, $3, $4, $5)`,
      [nid, property, level, parent, name],
    );
  }
  await q(
    `INSERT INTO tenancies (id, property_id, node_id, user_id, full_name, status, aadhaar_number, monthly_rent) VALUES
       ($1, $6, $9,  $14, 'Ravi Kumar', 'active', '123412341234', 7000),
       ($2, $6, $10, $15, 'Sita Devi',  'active', '999988887777', 6500),
       ($3, $7, $11, $16, 'Ravi Shah',  'active', NULL, 20000),
       ($4, $8, $12, $17, 'Ravi Other', 'active', NULL, 6000),
       ($5, $6, $13, $18, 'Mohan Lal',  'ended',  NULL, 6000)`,
    [
      TEN.a, TEN.b, TEN.c, TEN.x, TEN.old, P1, P2, P3,
      NODE.bed101a, NODE.bed102a, NODE.flat201, NODE.p3room101, NODE.bed103a,
      USER.tenantA, USER.tenantB, USER.tenantC, USER.tenantX, USER.oldTenant,
    ],
  );
  await q(
    `INSERT INTO complaints (id, property_id, node_id, raised_by, category, description, status, ticket_number, assigned_to) VALUES
       ($1, $5, $7, $9,  'Electrical', 'Fan not working',   'open', 'CMP-A1', NULL),
       ($2, $5, $8, $10, 'Electrical', 'Fan making noise',  'open', 'CMP-B2', $11),
       ($3, $5, $8, $10, 'Electrical', 'Fan blade broken',  'open', 'CMP-B3', $12),
       ($4, $6, $13, $14, 'Electrical', 'Fan in other org', 'open', 'CMP-X4', NULL)`,
    [
      COMPLAINT.mineA, COMPLAINT.otherStaff, COMPLAINT.assignedToMe, COMPLAINT.otherOrg, P1, P3,
      NODE.bed101a, NODE.bed102a, USER.tenantA, USER.tenantB, USER.staff2, USER.staff,
      NODE.p3room101, USER.tenantX,
    ],
  );
  await q(
    `INSERT INTO gate_passes (id, property_id, unit_id, tenancy_id, requested_by, visitor_name, purpose, status) VALUES
       ($1, $4, $7, $10, $13, 'Ramesh Courier', 'delivery', 'pending'),
       ($2, $5, $8, $11, $14, 'Ramesh Other',   'visitor',  'pending'),
       ($3, $6, $9, $12, $15, 'Ramesh Friend',  'visitor',  'approved')`,
    [
      GATE.tenantC, GATE.otherOrg, GATE.hostel, P2, P3, P1,
      NODE.flat201, NODE.p3room101, NODE.bed101a, TEN.c, TEN.x, TEN.a,
      USER.tenantC, USER.tenantX, USER.tenantA,
    ],
  );
  await q(
    `INSERT INTO invoices (id, tenancy_id, property_id, period_start, due_date, total_amount, status, sent_at) VALUES
       ($1, $6, $10, '2020-01-01', '2020-01-06', 5000, 'partial', now()),
       ($2, $6, $10, '2020-02-01', '2020-02-06', 5100, 'pending', NULL),
       ($3, $7, $10, '2020-01-01', '2020-01-06', 6500, 'paid',    now()),
       ($4, $8, $11, '2099-01-01', '2099-01-06', 20000, 'pending', now()),
       ($5, $9, $12, '2020-01-01', '2020-01-06', 6000, 'pending', now()),
       ($13, $6, $10, '2019-12-01', '2019-12-06', 1500, 'pending', now()),
       ($14, $7, $10, '2020-03-01', '2020-03-06', 4000, 'pending', NULL),
       ($15, $16, $10, '2020-04-01', '2020-04-06', 4000, 'pending', now())`,
    [
      INVOICE.overdueA, INVOICE.draftA, INVOICE.paidB, INVOICE.pendingC, INVOICE.overdueX,
      TEN.a, TEN.b, TEN.c, TEN.x, P1, P2, P3,
      INVOICE.overdueA2, INVOICE.draftB, INVOICE.overdueOld, TEN.old,
    ],
  );
  await q(
    `INSERT INTO payments (id, invoice_id, amount, method, paid_at) VALUES
       ($1, $4, 2000, 'upi',  '2020-01-10'),
       ($2, $5, 6500, 'cash', '2020-01-05'),
       ($3, $6, 100,  'upi',  '2020-01-07')`,
    [PAYMENT.a, PAYMENT.b, PAYMENT.x, INVOICE.overdueA, INVOICE.paidB, INVOICE.overdueX],
  );
  await q(
    `INSERT INTO meter_readings (id, property_id, unit_id, tenancy_id, meter_reading_value, rate_per_unit, amount, billing_cycle, submitted_by) VALUES
       ($1, $3, $5, $7, 1234.5, 8.5, 777.77, '2026-09', $9),
       ($2, $4, $6, $8, 999,    9,   555.55, '2026-09', $10)`,
    [READING.c, READING.x, P2, P3, NODE.flat201, NODE.p3room101, TEN.c, TEN.x, USER.tenantC, USER.tenantX],
  );
  await q(
    `INSERT INTO mess_menus (id, property_id, day_of_week, breakfast, lunch, dinner) VALUES
       ($1, $3, 1, 'Poha', 'Paneer butter masala', 'Dal rice'),
       ($2, $4, 1, 'Upma', 'Paneer tikka', 'Khichdi')`,
    [MENU.p1, MENU.p3, P1, P3],
  );
}

beforeAll(async () => {
  const { PGlite } = await import('@electric-sql/pglite');
  pg.db = new PGlite();
  await pg.db.exec(`
    CREATE TABLE properties (id uuid PRIMARY KEY, organization_id uuid, name text NOT NULL,
      property_type_key text, timezone text, address text, city text, state text);
    CREATE TABLE memberships (user_id uuid, organization_id uuid, role text);
    CREATE TABLE property_staff_assignments (id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id uuid, property_id uuid, role text, status text, created_at timestamptz DEFAULT now());
    CREATE TABLE users (id uuid PRIMARY KEY, name text, phone text, email text);
    CREATE TABLE hierarchy_levels (id uuid PRIMARY KEY, property_id uuid, display_name text,
      internal_key text, parent_level_id uuid, supports_occupancy boolean NOT NULL DEFAULT false);
    CREATE TABLE hierarchy_nodes (id uuid PRIMARY KEY, property_id uuid, level_id uuid,
      parent_node_id uuid, name text NOT NULL, code text, is_active boolean NOT NULL DEFAULT true,
      metadata jsonb NOT NULL DEFAULT '{}'::jsonb);
    CREATE TABLE tenancies (id uuid PRIMARY KEY, property_id uuid, node_id uuid, user_id uuid,
      full_name text, status text, aadhaar_number text, monthly_rent numeric(12,2),
      created_at timestamptz DEFAULT now());
    CREATE TABLE complaints (id uuid PRIMARY KEY, property_id uuid, node_id uuid, raised_by uuid,
      category text, description text, priority text DEFAULT 'medium', status text,
      ticket_number text, assigned_to uuid, created_at timestamptz DEFAULT now());
    CREATE TABLE gate_passes (id uuid PRIMARY KEY, property_id uuid, unit_id uuid, tenancy_id uuid,
      requested_by uuid, visitor_name text NOT NULL, purpose text, notes text, status text,
      created_at timestamptz DEFAULT now());
    CREATE TABLE invoices (id uuid PRIMARY KEY, tenancy_id uuid, property_id uuid,
      period_start date, due_date date, total_amount numeric(12,2), status text,
      sent_at timestamptz);
    CREATE TABLE payments (id uuid PRIMARY KEY, invoice_id uuid, amount numeric(12,2),
      method text, note text, paid_at timestamptz);
    CREATE TABLE meter_readings (id uuid PRIMARY KEY, property_id uuid, unit_id uuid,
      tenancy_id uuid, meter_reading_value numeric(14,3), rate_per_unit numeric(12,4),
      amount numeric(12,2), billing_cycle text, submitted_by uuid,
      created_at timestamptz DEFAULT now());
    CREATE TABLE mess_menus (id uuid PRIMARY KEY, property_id uuid, day_of_week smallint,
      breakfast text, lunch text, dinner text);
  `);
  await seed();

  const routes = await import('./search.routes.js');
  const { searchRouter } = routes;
  rateLimit = routes;
  const { errorHandler } = await import('../../shared/middleware/error-handler.js');
  const app = express();
  app.use('/v1/search', searchRouter);
  app.use(errorHandler);
  await new Promise<void>((resolve) => {
    server = app.listen(0, resolve);
  });
  baseUrl = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
}, 60_000);

afterAll(async () => {
  server?.close();
  await pg.db?.close();
});

afterEach(() => {
  vi.restoreAllMocks();
  rateLimit?.searchRateLimit.reset();
});

async function search(tok: string | null, params: Record<string, string | string[]>) {
  const qs = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) {
    for (const item of Array.isArray(v) ? v : [v]) qs.append(k, item);
  }
  const res = await fetch(`${baseUrl}/v1/search?${qs}`, {
    headers: tok ? { authorization: `Bearer ${tok}` } : {},
  });
  const text = await res.text();
  return {
    status: res.status,
    text,
    body: JSON.parse(text) as any,
    cacheControl: res.headers.get('cache-control'),
  };
}

const hits = (body: any, category?: string) =>
  (body.data.results as any[]).filter((r) => !category || r.category === category);
const hitIds = (body: any, category: string) => hits(body, category).map((r) => r.id).sort();

describe('owner / admin', () => {
  it('searches every property of the organization and labels each result with its property', async () => {
    const res = await search(TOKENS.owner(), { q: 'ravi' });
    expect(res.status).toBe(200);
    expect(res.cacheControl).toBe('no-store');
    expect(hitIds(res.body, 'tenants')).toEqual([TEN.a, TEN.c].sort());
    const ravi = hits(res.body, 'tenants').find((r) => r.id === TEN.a);
    expect(ravi).toMatchObject({
      title: 'Ravi Kumar',
      propertyId: P1,
      propertyName: 'Sunrise PG',
      propertyType: 'hostel_pg',
      nodeId: NODE.bed101a,
      status: 'active',
      phone: '9876543210',
    });
    expect(res.body.data.categories).toEqual([
      'properties', 'rooms', 'tenants', 'team', 'complaints',
      'gate_passes', 'invoices', 'payments', 'meter_readings', 'mess_menu',
    ]);
  });

  it('gives an admin the same organization-wide results as the owner', async () => {
    const owner = await search(TOKENS.owner(), { q: 'ravi' });
    const admin = await search(TOKENS.admin(), { q: 'ravi' });
    expect(admin.status).toBe(200);
    expect(admin.body.data.results).toEqual(owner.body.data.results);
  });

  it('finds properties, team members and phone numbers inside the organization only', async () => {
    const props = await search(TOKENS.owner(), { q: 'lake', category: 'properties' });
    expect(hitIds(props.body, 'properties')).toEqual([P2]);

    const team = await search(TOKENS.owner(), { q: 'suresh', category: 'team' });
    expect(hits(team.body, 'team').map((r) => r.title).sort()).toEqual(['Suresh Kumar', 'Suresh Staff']);
    expect(hits(team.body, 'team')[0].phone).toMatch(/^9/);

    const phone = await search(TOKENS.owner(), { q: '98765', category: 'tenants' });
    expect(hitIds(phone.body, 'tenants')).toEqual([TEN.a]);
  });

  it('applies the overdue and drafts filters with the billing rules', async () => {
    const overdue = await search(TOKENS.owner(), { q: '', filter: 'overdue' });
    expect(overdue.status).toBe(200);
    expect(hitIds(overdue.body, 'invoices')).toEqual(
      [INVOICE.overdueA, INVOICE.overdueA2, INVOICE.overdueOld].sort(),
    );
    expect(hits(overdue.body, 'invoices').find((r) => r.id === INVOICE.overdueA)).toMatchObject({
      status: 'overdue',
      amount: 3000,
      invoiceId: INVOICE.overdueA,
    });

    const drafts = await search(TOKENS.owner(), { filter: 'drafts' });
    expect(hitIds(drafts.body, 'invoices')).toEqual([INVOICE.draftA, INVOICE.draftB].sort());
    expect(hits(drafts.body).find((r) => r.id === INVOICE.draftA)).toMatchObject({ status: 'draft', amount: 5100 });
  });

  it('overdue also lists active tenants who owe, with phone and overdue balance', async () => {
    const res = await search(TOKENS.owner(), { filter: 'overdue' });
    expect(res.status).toBe(200);
    expect(hits(res.body).map((r) => r.category)).toEqual([
      'tenants', 'invoices', 'invoices', 'invoices',
    ]);
    // Sita's only past-due bill is a draft, Ravi Shah's is not due yet, Mohan
    // Lal has checked out and Ravi Other belongs to another organization.
    expect(hitIds(res.body, 'tenants')).toEqual([TEN.a]);
    expect(hits(res.body, 'tenants')[0]).toEqual({
      category: 'tenants',
      id: TEN.a,
      title: 'Ravi Kumar',
      subtitle: '101-A',
      status: 'active',
      propertyId: P1,
      propertyName: 'Sunrise PG',
      propertyType: 'hostel_pg',
      nodeId: NODE.bed101a,
      phone: '9876543210',
      amount: 4500,
    });
  });

  it('matches the search text in both overdue result types', async () => {
    const mohan = await search(TOKENS.owner(), { q: 'mohan', filter: 'overdue' });
    expect(hits(mohan.body, 'tenants')).toEqual([]);
    expect(hitIds(mohan.body, 'invoices')).toEqual([INVOICE.overdueOld]);

    const sita = await search(TOKENS.owner(), { q: 'sita', filter: 'overdue' });
    expect(hits(sita.body)).toEqual([]);

    const phone = await search(TOKENS.owner(), { q: '98765', filter: 'overdue' });
    expect(hitIds(phone.body, 'tenants')).toEqual([TEN.a]);
  });

  it('narrows overdue to one result type when a category is chosen', async () => {
    const tenants = await search(TOKENS.owner(), { filter: 'overdue', category: 'tenants' });
    expect(tenants.status).toBe(200);
    expect(hits(tenants.body).map((r) => r.id)).toEqual([TEN.a]);

    const invoices = await search(TOKENS.owner(), { filter: 'overdue', category: 'invoices' });
    expect(new Set(hits(invoices.body).map((r) => r.category))).toEqual(new Set(['invoices']));

    const wrong = await search(TOKENS.owner(), { filter: 'overdue', category: 'rooms' });
    expect(wrong.status).toBe(400);
    expect(wrong.body.code).toBe('invalid_search_filter');
  });

  it('lists vacant rentable spaces, never buildings or floors', async () => {
    const res = await search(TOKENS.owner(), { filter: 'vacant' });
    expect(hitIds(res.body, 'rooms')).toEqual([NODE.bed101b, NODE.bed103a, NODE.flat202, NODE.room103].sort());
    const floors = await search(TOKENS.owner(), { q: 'floor', category: 'rooms' });
    expect(hits(floors.body).map((r) => r.id)).not.toContain(NODE.floor1);
  });
});

describe('manager', () => {
  it('only sees their assigned property', async () => {
    const res = await search(TOKENS.manager(), { q: 'ravi' });
    expect(res.status).toBe(200);
    expect(hitIds(res.body, 'tenants')).toEqual([TEN.a]);
    expect(hits(res.body).every((r) => r.propertyId === P1)).toBe(true);
    expect(res.body.data.categories).not.toContain('team');
    expect(res.body.data.categories).not.toContain('properties');
  });

  it('sees financial records of their property with amounts', async () => {
    const res = await search(TOKENS.manager(), { q: 'jan 2020', category: 'invoices' });
    expect(hitIds(res.body, 'invoices')).toEqual([INVOICE.overdueA, INVOICE.paidB].sort());
    const pay = await search(TOKENS.manager(), { q: 'upi', category: 'payments' });
    expect(hitIds(pay.body, 'payments')).toEqual([PAYMENT.a]);
    expect(hits(pay.body)[0].amount).toBe(2000);
  });

  it('gets overdue tenants and invoices of their property only, with phone and amount', async () => {
    const res = await search(TOKENS.manager(), { filter: 'overdue' });
    expect(res.status).toBe(200);
    expect(hitIds(res.body, 'tenants')).toEqual([TEN.a]);
    expect(hits(res.body, 'tenants')[0]).toMatchObject({ phone: '9876543210', amount: 4500 });
    expect(hitIds(res.body, 'invoices')).toEqual(
      [INVOICE.overdueA, INVOICE.overdueA2, INVOICE.overdueOld].sort(),
    );
    expect(hits(res.body).every((r) => r.propertyId === P1)).toBe(true);
    expect(res.text).not.toContain(TEN.x);
  });

  it('cannot search the team or properties, even by direct request', async () => {
    for (const category of ['team', 'properties']) {
      const res = await search(TOKENS.manager(), { q: 'suresh', category });
      expect(res.status).toBe(403);
      expect(res.body).toEqual({
        error: 'You do not have access to search this category.',
        code: 'search_category_forbidden',
      });
    }
  });

  it('ignores property, organization and role values sent by the client', async () => {
    const res = await search(TOKENS.manager(), {
      q: 'ravi',
      propertyId: P2,
      organizationId: ORG_2,
      role: 'owner',
      tenantId: TEN.x,
    });
    expect(res.status).toBe(200);
    expect(hitIds(res.body, 'tenants')).toEqual([TEN.a]);
  });
});

describe('staff', () => {
  it('gets operational categories only, without phones or money', async () => {
    const res = await search(TOKENS.staff(), { q: 'ravi' });
    expect(res.status).toBe(200);
    expect(res.body.data.categories).toEqual([
      'rooms', 'tenants', 'complaints', 'gate_passes', 'meter_readings', 'mess_menu',
    ]);
    expect(hitIds(res.body, 'tenants')).toEqual([TEN.a]);
    for (const hit of hits(res.body)) {
      expect(hit).not.toHaveProperty('phone');
      expect(hit).not.toHaveProperty('amount');
    }
    expect(res.text).not.toContain('9876543210');
    expect(res.text).not.toContain('123412341234');
    expect(res.text).not.toContain('7000');
  });

  it('cannot reach invoices, payments, team or the money filters', async () => {
    for (const category of ['invoices', 'payments', 'team', 'properties']) {
      const res = await search(TOKENS.staff(), { q: 'ravi', category });
      expect(res.status).toBe(403);
      expect(res.body.code).toBe('search_category_forbidden');
    }
    for (const filter of ['overdue', 'drafts']) {
      const res = await search(TOKENS.staff(), { filter });
      expect(res.status).toBe(403);
      expect(res.body.code).toBe('search_filter_forbidden');
      expect(res.body.data).toBeUndefined();
    }
    const narrowed = await search(TOKENS.staff(), { filter: 'overdue', category: 'tenants' });
    expect(narrowed.status).toBe(403);
    expect(narrowed.text).not.toContain('9876543210');
  });

  it('never receives phone or amount, even if a tenant result carries them', async () => {
    const { serializeHit } = await import('./search.policy.js');
    const hit = {
      category: 'tenants' as const,
      id: TEN.a,
      title: 'Ravi Kumar',
      subtitle: '101-A',
      status: 'active',
      propertyId: P1,
      propertyName: 'Sunrise PG',
      propertyType: 'hostel_pg',
      phone: '9876543210',
      amount: 4500,
    };
    expect(serializeHit(hit, 'staff')).not.toHaveProperty('phone');
    expect(serializeHit(hit, 'staff')).not.toHaveProperty('amount');
    expect(serializeHit(hit, 'tenant')).not.toHaveProperty('phone');
    expect(serializeHit(hit, 'manager')).toMatchObject({ phone: '9876543210', amount: 4500 });
  });

  it('does not match tenants by phone number', async () => {
    const res = await search(TOKENS.staff(), { q: '98765', category: 'tenants' });
    expect(res.status).toBe(200);
    expect(hits(res.body)).toEqual([]);
  });

  it('only sees complaints that are unassigned or assigned to them', async () => {
    const res = await search(TOKENS.staff(), { q: 'fan', category: 'complaints' });
    expect(hitIds(res.body, 'complaints')).toEqual([COMPLAINT.mineA, COMPLAINT.assignedToMe].sort());
  });

  it('can use the vacant and checked-out filters', async () => {
    const vacant = await search(TOKENS.staff(), { filter: 'vacant' });
    expect(hitIds(vacant.body, 'rooms')).toEqual([NODE.bed101b, NODE.bed103a, NODE.room103].sort());
    const gone = await search(TOKENS.staff(), { filter: 'checked_out' });
    expect(hits(gone.body).map((r) => r.title)).toEqual(['Mohan Lal']);
  });

  it('sees meter readings without rates or amounts', async () => {
    const res = await search(propToken(USER.otherStaff, P3, 'staff'), { q: '2026', category: 'meter_readings' });
    expect(hitIds(res.body, 'meter_readings')).toEqual([READING.x]);
    expect(res.text).not.toContain('555.55');
    expect(res.text).not.toContain('"9"');
  });
});

describe('tenant', () => {
  it('only finds their own complaints at their current property', async () => {
    const res = await search(TOKENS.tenantA(), { q: 'fan' });
    expect(res.status).toBe(200);
    expect(hitIds(res.body, 'complaints')).toEqual([COMPLAINT.mineA]);
    expect(hits(res.body).every((r) => r.propertyId === P1)).toBe(true);
  });

  it('sees their own sent bills and payments with amounts, never drafts', async () => {
    const bills = await search(TOKENS.tenantA(), { q: '2020', category: 'invoices' });
    expect(hitIds(bills.body, 'invoices')).toEqual([INVOICE.overdueA]);
    expect(hits(bills.body)[0]).toMatchObject({ title: 'Bill · Jan 2020', status: 'overdue', amount: 3000 });

    const paid = await search(TOKENS.tenantA(), { q: 'upi', category: 'payments' });
    expect(hitIds(paid.body, 'payments')).toEqual([PAYMENT.a]);
  });

  it('finds their own room only', async () => {
    const res = await search(TOKENS.tenantA(), { q: '10', category: 'rooms' });
    expect(hitIds(res.body, 'rooms')).toEqual([NODE.bed101a]);
    expect(hits(res.body)[0].subtitle).toBe('Bed · Room 101 · Floor 1');
  });

  it('gets feature-gated categories that match their property type', async () => {
    const hostel = await search(TOKENS.tenantA(), { q: 'ramesh' });
    expect(hits(hostel.body, 'gate_passes')).toEqual([]);
    const menu = await search(TOKENS.tenantA(), { q: 'paneer' });
    expect(hitIds(menu.body, 'mess_menu')).toEqual([MENU.p1]);
    expect(hits(menu.body, 'mess_menu')[0]).toMatchObject({
      title: 'Monday menu',
      subtitle: 'Lunch: Paneer butter masala',
    });

    const flat = await search(TOKENS.tenantC(), { q: 'ramesh' });
    expect(hitIds(flat.body, 'gate_passes')).toEqual([GATE.tenantC]);
    const meters = await search(TOKENS.tenantC(), { q: '2026', category: 'meter_readings' });
    expect(hitIds(meters.body, 'meter_readings')).toEqual([READING.c]);
    expect(meters.text).not.toContain('777.77');
    const noMenu = await search(TOKENS.tenantC(), { q: 'paneer' });
    expect(hits(noMenu.body, 'mess_menu')).toEqual([]);
  });

  it('cannot search tenants, team, properties or use filters', async () => {
    for (const category of ['tenants', 'team', 'properties']) {
      const res = await search(TOKENS.tenantA(), { q: 'ravi', category });
      expect(res.status).toBe(403);
      expect(res.body.code).toBe('search_category_forbidden');
    }
    for (const filter of ['vacant', 'overdue']) {
      const res = await search(TOKENS.tenantA(), { filter });
      expect(res.status).toBe(403);
      expect(res.body.code).toBe('search_filter_forbidden');
      expect(res.body.data).toBeUndefined();
    }
  });

  it("ignores client tenant/property ids and rejects another tenant's signed context", async () => {
    const res = await search(TOKENS.tenantA(), { q: 'fan', tenancyId: TEN.b, propertyId: P3 });
    expect(hitIds(res.body, 'complaints')).toEqual([COMPLAINT.mineA]);

    const stolen = await search(tenantToken(USER.tenantA, TEN.b, P1), { q: 'fan' });
    expect(stolen.status).toBe(403);
    expect(stolen.body.data).toBeUndefined();

    const ended = await search(tenantToken(USER.oldTenant, TEN.old, P1), { q: 'fan' });
    expect(ended.status).toBe(403);
  });
});

describe('cross-workspace denial', () => {
  it('rejects a context the user does not hold', async () => {
    const foreignOrg = await search(orgToken(USER.owner, ORG_2, 'owner'), { q: 'ravi' });
    expect(foreignOrg.status).toBe(403);
    const foreignProperty = await search(propToken(USER.manager, P2, 'manager'), { q: 'ravi' });
    expect(foreignProperty.status).toBe(403);
    const spoofedRole = await search(propToken(USER.staff, P1, 'manager'), { q: 'ravi' });
    expect(spoofedRole.status).toBe(403);
  });

  it('requires a signed token', async () => {
    const res = await search(null, { q: 'ravi' });
    expect(res.status).toBe(401);
    expect(res.body.data).toBeUndefined();
  });
});

describe('validation and limits', () => {
  it.each([
    [{ q: 'a' }, 400, 'search_query_too_short'],
    [{ q: '   ' }, 400, 'search_query_too_short'],
    [{ q: 'x'.repeat(81) }, 400, 'invalid_search_query'],
    [{ q: ['ravi', 'sita'] }, 400, 'invalid_search_query'],
    [{ q: 'ravi', category: 'bogus' }, 400, 'invalid_search_category'],
    [{ q: 'ravi', filter: 'bogus' }, 400, 'invalid_search_filter'],
    [{ filter: 'vacant', category: 'invoices' }, 400, 'invalid_search_filter'],
    [{ q: 'ravi', limit: '0' }, 400, 'invalid_search_limit'],
    [{ q: 'ravi', limit: '21' }, 400, 'invalid_search_limit'],
    [{ q: 'ravi', limit: '5.5' }, 400, 'invalid_search_limit'],
    [{ q: 'ravi', limit: 'abc' }, 400, 'invalid_search_limit'],
  ] as const)('rejects %j', async (params, status, code) => {
    const res = await search(TOKENS.owner(), params as Record<string, string | string[]>);
    expect(res.status).toBe(status);
    expect(Object.keys(res.body).sort()).toEqual(['code', 'error']);
    expect(res.body.code).toBe(code);
  });

  it('returns an empty list when nothing matches', async () => {
    const res = await search(TOKENS.owner(), { q: 'zzzz' });
    expect(res.status).toBe(200);
    expect(res.body.data.results).toEqual([]);
  });

  it('treats LIKE wildcards in the query as plain text', async () => {
    for (const q of ['%%', '__', '\\\\']) {
      const res = await search(TOKENS.owner(), { q });
      expect(res.status).toBe(200);
      expect(res.body.data.results).toEqual([]);
    }
  });

  it('caps results per category', async () => {
    const two = await search(TOKENS.owner(), { q: '10', category: 'rooms', limit: '2' });
    expect(hits(two.body)).toHaveLength(2);
    const all = await search(TOKENS.owner(), { q: '10' });
    expect(hits(all.body, 'rooms').length).toBeLessThanOrEqual(5);
  });
});

describe('rate limit', () => {
  const burst = () => rateLimit.SEARCH_RATE_LIMIT.capacity;

  beforeEach(() => {
    // Freeze the clock so no tokens refill while the burst is sent.
    const frozen = Date.now();
    vi.spyOn(Date, 'now').mockReturnValue(frozen);
  });

  it('serves requests within the limit, then answers 429 with Retry-After', async () => {
    const tok = TOKENS.manager();
    for (let i = 0; i < burst(); i++) {
      const ok = await search(tok, { q: 'zz', category: 'rooms' });
      expect(ok.status).toBe(200);
    }
    pg.log.length = 0;
    const res = await fetch(`${baseUrl}/v1/search?q=zz&category=rooms`, {
      headers: { authorization: `Bearer ${tok}` },
    });
    expect(res.status).toBe(429);
    expect(Number(res.headers.get('retry-after'))).toBeGreaterThanOrEqual(1);
    expect(await res.json()).toEqual({
      error: 'Too many searches. Please wait a moment and try again.',
      code: 'search_rate_limited',
    });
    // Rejected before the context check and the search: no queries ran.
    expect(pg.log).toEqual([]);
  });

  it('keeps separate budgets per user, whatever their address', async () => {
    const owner = TOKENS.owner();
    for (let i = 0; i < burst(); i++) await search(owner, { q: 'zz', category: 'rooms' });
    expect((await search(owner, { q: 'zz', category: 'rooms' })).status).toBe(429);

    const admin = await search(TOKENS.admin(), { q: 'zz', category: 'rooms' });
    expect(admin.status).toBe(200);
    const tenant = await search(TOKENS.tenantA(), { q: 'zz', category: 'rooms' });
    expect(tenant.status).toBe(200);
  });

  it('counts a user across workspaces, so switching context does not reset it', async () => {
    const asManager = TOKENS.manager();
    for (let i = 0; i < burst(); i++) await search(asManager, { q: 'zz', category: 'rooms' });
    const reissued = propToken(USER.manager, P1, 'manager');
    expect((await search(reissued, { q: 'zz', category: 'rooms' })).status).toBe(429);
  });

  it('rejects unauthenticated requests with 401 without using anyone’s budget', async () => {
    for (let i = 0; i < burst() + 5; i++) {
      const res = await search(null, { q: 'ravi' });
      expect(res.status).toBe(401);
    }
    const bad = await search('not-a-jwt', { q: 'ravi' });
    expect(bad.status).toBe(401);
    const noSubject = await search(token({ ctxType: 'organization', ctxId: ORG_1, ctxRole: 'owner' }), { q: 'ravi' });
    expect(noSubject.status).toBe(401);
    expect(rateLimit.searchRateLimit.size).toBe(0);
    expect((await search(TOKENS.owner(), { q: 'ravi' })).status).toBe(200);
  });
});

describe('execution', () => {
  it('runs read-only with a statement timeout and a fixed number of queries', async () => {
    pg.log.length = 0;
    const res = await search(TOKENS.owner(), { q: 'ravi' });
    expect(res.status).toBe(200);
    const sql = pg.log.filter((s) => !/information_schema|FROM memberships/.test(s));
    expect(sql[0]).toBe('SET TRANSACTION READ ONLY');
    expect(sql[1]).toMatch(/SET LOCAL statement_timeout = 3000/);
    // Scope lookup + one query per category, however many rows match.
    expect(sql).toHaveLength(2 + 1 + 10);
    for (const statement of sql.slice(3)) expect(statement).toMatch(/LIMIT \$\d+/);
  });

  it('turns a statement timeout into a safe 503', async () => {
    const original = pg.db.query.bind(pg.db);
    vi.spyOn(pg.db, 'query').mockImplementation(async (sql: unknown, params?: unknown) => {
      if (typeof sql === 'string' && sql.includes('FROM gate_passes')) {
        throw Object.assign(new Error('canceling statement due to statement timeout'), {
          code: '57014',
          severity: 'ERROR',
        });
      }
      return original(sql, params);
    });
    const res = await search(TOKENS.owner(), { q: 'ravi' });
    expect(res.status).toBe(503);
    expect(res.body).toEqual({
      error: 'Search took too long. Try a more specific search.',
      code: 'search_timeout',
    });
  });

  it('hides database details on unexpected failures', async () => {
    const original = pg.db.query.bind(pg.db);
    vi.spyOn(console, 'error').mockImplementation(() => undefined);
    vi.spyOn(pg.db, 'query').mockImplementation(async (sql: unknown, params?: unknown) => {
      if (typeof sql === 'string' && sql.includes('FROM mess_menus')) {
        throw Object.assign(new Error('relation "mess_menus" does not exist'), {
          code: '42P01',
          severity: 'ERROR',
        });
      }
      return original(sql, params);
    });
    const res = await search(TOKENS.owner(), { q: 'ravi' });
    expect(res.status).toBe(500);
    expect(res.body).toEqual({ error: 'Internal server error' });
  });
});
