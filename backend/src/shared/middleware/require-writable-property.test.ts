// requireWritableProperty through the real properties.routes.ts guard chain
// (auth, context, property access, freeze check) on an in-memory Postgres
// (PGlite). Gate-pass decisions stand in for every nested property write.
import type { AddressInfo } from 'net';
import express from 'express';
import jwt from 'jsonwebtoken';
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';

process.env.DATABASE_URL ??= 'postgres://test:test@127.0.0.1:1/test';
process.env.JWT_ACCESS_SECRET = 'writable-property-test-secret';
process.env.JWT_REFRESH_SECRET ??= 'test';
process.env.RAZORPAY_KEY_ID ??= 'rzp_test_x';
process.env.RAZORPAY_KEY_SECRET ??= 'test';
process.env.RAZORPAY_WEBHOOK_SECRET ??= 'test';

const pg = vi.hoisted(() => ({ db: null as any }));

vi.mock('@config/db', () => {
  const run = async (sql: string, params?: unknown[]) =>
    (await pg.db.query(sql, params ?? [])).rows;
  return { query: run, withTransaction: async (fn: (q: typeof run) => unknown) => fn(run) };
});

vi.mock('@modules/notifications/notify', () => ({
  ensureLiveOpsSchema: async () => undefined,
  notifyPropertyOwners: async () => 0,
  createNotification: async () => true,
}));

const ORG_PAID = '01000000-0000-4000-8000-000000000001';
const ORG_FREE = '01000000-0000-4000-8000-000000000002';
const PAID_P = '11000000-0000-4000-8000-000000000001';
const PAID_P2 = '11000000-0000-4000-8000-000000000004'; // second property, same paid org
const FREE_OLDEST = '12000000-0000-4000-8000-000000000002'; // still manageable on Free
const FREE_FROZEN = '12000000-0000-4000-8000-000000000003'; // surplus commercial → frozen
const USER = {
  owner: '31000000-0000-4000-8000-000000000001',
  freeOwner: '31000000-0000-4000-8000-000000000002',
  manager: '31000000-0000-4000-8000-000000000003',
  staff: '31000000-0000-4000-8000-000000000004',
  frozenStaff: '31000000-0000-4000-8000-000000000005',
  oldestStaff: '31000000-0000-4000-8000-000000000006',
  tenant: '31000000-0000-4000-8000-000000000007',
  admin: '31000000-0000-4000-8000-000000000008',
};
const UNIT = '21000000-0000-4000-8000-000000000001';
const PASS = {
  paid: '51000000-0000-4000-8000-000000000001',
  paid2: '51000000-0000-4000-8000-000000000004',
  oldest: '52000000-0000-4000-8000-000000000002',
  frozen: '52000000-0000-4000-8000-000000000003',
};

const sign = (claims: Record<string, unknown>) =>
  jwt.sign(claims, process.env.JWT_ACCESS_SECRET!, { expiresIn: '5m' });
const orgToken = (sub: string, org: string, role: 'owner' | 'admin') =>
  sign({ sub, ctxType: 'organization', ctxId: org, ctxRole: role, ctxPropertyId: null });
const propToken = (sub: string, property: string, role: 'manager' | 'staff') =>
  sign({ sub, ctxType: 'organization', ctxId: property, ctxRole: role, ctxPropertyId: property });

let baseUrl = '';
let server: ReturnType<express.Express['listen']>;

async function resetData() {
  const q = (sql: string, params: unknown[] = []) => pg.db.query(sql, params);
  await pg.db.exec(`TRUNCATE properties, memberships, property_staff_assignments,
    org_active_entitlements, gate_passes, users, hierarchy_nodes;`);
  await q(
    `INSERT INTO properties (id, organization_id, property_type_key, created_at) VALUES
       ($1, $4, 'apartment', now() - interval '30 days'),
       ($2, $5, 'apartment', now() - interval '20 days'),
       ($3, $5, 'apartment', now() - interval '10 days')`,
    [PAID_P, FREE_OLDEST, FREE_FROZEN, ORG_PAID, ORG_FREE],
  );
  await q(
    `INSERT INTO properties (id, organization_id, property_type_key, created_at)
     VALUES ($1, $2, 'apartment', now() - interval '5 days')`,
    [PAID_P2, ORG_PAID],
  );
  await q(
    `INSERT INTO org_active_entitlements (organization_id, plan_slug, subscription_status,
       feature_key, value_type, bool_value) VALUES ($1, 'pro', 'active', 'reports', 'boolean', true)`,
    [ORG_PAID],
  );
  await q(
    `INSERT INTO memberships (user_id, organization_id, role) VALUES
       ($1, $2, 'owner'), ($3, $4, 'owner'), ($5, $2, 'admin')`,
    [USER.owner, ORG_PAID, USER.freeOwner, ORG_FREE, USER.admin],
  );
  // The paid org's manager and staff are also assigned to its second property.
  await q(
    `INSERT INTO property_staff_assignments (user_id, property_id, role, status) VALUES
       ($1, $3, 'manager', 'active'), ($2, $3, 'staff', 'active')`,
    [USER.manager, USER.staff, PAID_P2],
  );
  await q(
    `INSERT INTO gate_passes (id, property_id, requested_by, visitor_name, status)
     VALUES ($1, $2, $3, 'Electrician', 'pending')`,
    [PASS.paid2, PAID_P2, USER.tenant],
  );
  await q(
    `INSERT INTO property_staff_assignments (user_id, property_id, role, status) VALUES
       ($1, $4, 'manager', 'active'), ($2, $4, 'staff', 'active'),
       ($3, $5, 'staff', 'active'), ($6, $7, 'staff', 'active')`,
    [USER.manager, USER.staff, USER.frozenStaff, PAID_P, FREE_FROZEN, USER.oldestStaff, FREE_OLDEST],
  );
  await q(
    `INSERT INTO gate_passes (id, property_id, requested_by, visitor_name, status) VALUES
       ($1, $4, $7, 'Courier', 'pending'),
       ($2, $5, $7, 'Plumber', 'pending'),
       ($3, $6, $7, 'Friend',  'pending')`,
    [PASS.paid, PASS.oldest, PASS.frozen, PAID_P, FREE_OLDEST, FREE_FROZEN, USER.tenant],
  );
  await q(`INSERT INTO users (id, name) VALUES ($1, 'Tenant')`, [USER.tenant]);
  await q(`INSERT INTO hierarchy_nodes (id, name) VALUES ($1, 'Flat 1')`, [UNIT]);
  await q(`UPDATE gate_passes SET unit_id = $1`, [UNIT]);
}

beforeAll(async () => {
  const { PGlite } = await import('@electric-sql/pglite');
  pg.db = new PGlite();
  await pg.db.exec(`
    CREATE TABLE properties (id uuid PRIMARY KEY, organization_id uuid, property_type_key text,
      created_at timestamptz DEFAULT now());
    CREATE TABLE memberships (user_id uuid, organization_id uuid, role text);
    CREATE TABLE property_staff_assignments (user_id uuid, property_id uuid, role text, status text);
    CREATE TABLE tenancies (id uuid PRIMARY KEY, property_id uuid, user_id uuid, status text);
    CREATE TABLE org_active_entitlements (organization_id uuid, plan_slug text,
      subscription_status text, trial_ends_at timestamptz, current_period_end timestamptz,
      grace_period_ends_at timestamptz, feature_key text, value_type text, bool_value boolean,
      quota_value int);
    CREATE TABLE gate_passes (id uuid PRIMARY KEY, property_id uuid, unit_id uuid,
      requested_by uuid, visitor_name text, status text, decided_by uuid,
      decided_at timestamptz, created_at timestamptz DEFAULT now(), updated_at timestamptz);
    CREATE TABLE hierarchy_nodes (id uuid PRIMARY KEY, name text);
    CREATE TABLE users (id uuid PRIMARY KEY, name text);
  `);

  const { authGuard, requireContext, requirePropertyAccess } = await import('./auth-guard.js');
  const { requireWritableProperty } = await import('./require-writable-property.js');
  const { gatePassesRouter } = await import('../../modules/gate-passes/gate-passes.routes.js');
  const { errorHandler } = await import('./error-handler.js');

  const app = express();
  app.use(express.json());
  app.use(
    '/v1/properties/:propertyId/gate-passes',
    authGuard,
    requireContext,
    requirePropertyAccess,
    requireWritableProperty,
    gatePassesRouter,
  );
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

beforeEach(async () => {
  await resetData();
  vi.spyOn(console, 'error').mockImplementation(() => undefined);
});

async function decide(token: string, propertyId: string, passId: string) {
  const res = await fetch(`${baseUrl}/v1/properties/${propertyId}/gate-passes/${passId}`, {
    method: 'PATCH',
    headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
    body: JSON.stringify({ status: 'approved' }),
  });
  return { status: res.status, body: (await res.json().catch(() => null)) as any };
}

async function list(token: string, propertyId: string) {
  const res = await fetch(`${baseUrl}/v1/properties/${propertyId}/gate-passes`, {
    headers: { authorization: `Bearer ${token}` },
  });
  return { status: res.status, body: (await res.json().catch(() => null)) as any };
}

const passStatus = async (id: string) =>
  (await pg.db.query(`SELECT status FROM gate_passes WHERE id = $1`, [id])).rows[0].status;

describe('paid organization', () => {
  it.each([
    ['owner', () => orgToken(USER.owner, ORG_PAID, 'owner')],
    ['admin', () => orgToken(USER.admin, ORG_PAID, 'admin')],
    ['manager', () => propToken(USER.manager, PAID_P, 'manager')],
    ['staff', () => propToken(USER.staff, PAID_P, 'staff')],
  ])('lets the %s write to the property', async (_role, token) => {
    const res = await decide(token(), PAID_P, PASS.paid);
    expect(res.status).toBe(200);
    expect(await passStatus(PASS.paid)).toBe('approved');
  });

  it.each([
    ['manager', () => propToken(USER.manager, PAID_P2, 'manager')],
    ['staff', () => propToken(USER.staff, PAID_P2, 'staff')],
  ])('lets the %s write to their second property from that workspace', async (_role, token) => {
    const res = await decide(token(), PAID_P2, PASS.paid2);
    expect(res.status).toBe(200);
    expect(await passStatus(PASS.paid2)).toBe('approved');
  });
});

describe('free organization after downgrade', () => {
  it('still lets staff write to the one manageable commercial property', async () => {
    const res = await decide(propToken(USER.oldestStaff, FREE_OLDEST, 'staff'), FREE_OLDEST, PASS.oldest);
    expect(res.status).toBe(200);
    expect(await passStatus(PASS.oldest)).toBe('approved');
  });

  it('freezes writes to a surplus property for staff and the owner alike', async () => {
    for (const token of [
      propToken(USER.frozenStaff, FREE_FROZEN, 'staff'),
      orgToken(USER.freeOwner, ORG_FREE, 'owner'),
    ]) {
      const res = await decide(token, FREE_FROZEN, PASS.frozen);
      expect(res.status).toBe(403);
      expect(res.body.code).toBe('SUBSCRIPTION_REQUIRED');
    }
    expect(await passStatus(PASS.frozen)).toBe('pending');
  });

  it.each([
    ['staff', () => propToken(USER.frozenStaff, FREE_FROZEN, 'staff')],
    ['owner', () => orgToken(USER.freeOwner, ORG_FREE, 'owner')],
  ])('keeps reads open on a frozen property for the %s', async (_role, token) => {
    const res = await list(token(), FREE_FROZEN);
    expect(res.status).toBe(200);
    expect(res.body.data.map((p: any) => p.id)).toEqual([PASS.frozen]);
  });
});

describe('scoping is unchanged', () => {
  it("rejects staff writing to a property they are not assigned to before the freeze check", async () => {
    const res = await decide(propToken(USER.staff, PAID_P, 'staff'), FREE_OLDEST, PASS.oldest);
    expect(res.status).toBe(403);
    expect(res.body.code).toBeUndefined();
    expect(await passStatus(PASS.oldest)).toBe('pending');
  });

  it.each([
    ['manager', () => propToken(USER.manager, PAID_P, 'manager')],
    ['staff', () => propToken(USER.staff, PAID_P, 'staff')],
  ])(
    "rejects the %s writing to another assigned property's routes from the first workspace",
    async (_role, token) => {
      const res = await decide(token(), PAID_P2, PASS.paid2);
      expect(res.status).toBe(403);
      expect(res.body).toEqual({ error: 'You do not have access to this property.' });
      expect(await passStatus(PASS.paid2)).toBe('pending');
    },
  );

  it("rejects an owner writing to another organization's property", async () => {
    const res = await decide(orgToken(USER.owner, ORG_PAID, 'owner'), FREE_OLDEST, PASS.oldest);
    expect(res.status).toBe(403);
    expect(await passStatus(PASS.oldest)).toBe('pending');
  });

  it('leaves reads scoped exactly as before', async () => {
    for (const token of [
      orgToken(USER.owner, ORG_PAID, 'owner'),
      orgToken(USER.admin, ORG_PAID, 'admin'),
      propToken(USER.manager, PAID_P, 'manager'),
      propToken(USER.staff, PAID_P, 'staff'),
    ]) {
      const res = await list(token, PAID_P);
      expect(res.status).toBe(200);
      expect(res.body.data.map((p: any) => p.id)).toEqual([PASS.paid]);
    }
    expect((await list(propToken(USER.manager, PAID_P, 'manager'), PAID_P2)).status).toBe(403);
    expect((await list(propToken(USER.staff, PAID_P, 'staff'), FREE_OLDEST)).status).toBe(403);
    expect((await list(orgToken(USER.owner, ORG_PAID, 'owner'), FREE_OLDEST)).status).toBe(403);
  });
});
