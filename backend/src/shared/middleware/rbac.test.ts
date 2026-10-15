// Manager / staff / tenant permissions through the real auth chain and the real
// property routers. Workspace, membership and record-ownership checks run on an
// in-memory Postgres; module services are stubs that record every call, so a
// refused request can be shown to have reached no business logic at all.
import type { AddressInfo } from 'net';
import express from 'express';
import jwt from 'jsonwebtoken';
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';

process.env.DATABASE_URL ??= 'postgres://test:test@127.0.0.1:1/test';
process.env.JWT_ACCESS_SECRET = 'rbac-test-secret';
process.env.JWT_REFRESH_SECRET ??= 'test';
process.env.RAZORPAY_KEY_ID ??= 'rzp_test_x';
process.env.RAZORPAY_KEY_SECRET ??= 'test';
process.env.RAZORPAY_WEBHOOK_SECRET ??= 'test';

const pg = vi.hoisted(() => ({ db: null as any }));

const stubs = vi.hoisted(() => {
  const calls: { name: string; args: unknown[] }[] = [];
  const results: Record<string, (...args: any[]) => unknown> = {};
  /** A service class whose every method records the call and returns results[name] or []. */
  const service = (className: string) =>
    class {
      constructor() {
        return new Proxy(
          {},
          {
            get: (_target, prop) => {
              if (typeof prop !== 'string' || prop === 'then') return undefined;
              const name = `${className}.${prop}`;
              return async (...args: unknown[]) => {
                calls.push({ name, args });
                return results[name] ? results[name](...args) : [];
              };
            },
          },
        );
      }
    };
  /** vi.mock factory: the real module with one service class replaced by a stub. */
  const replace = (exportName: string) => async (importOriginal: () => Promise<any>) => ({
    ...(await importOriginal()),
    [exportName]: service(exportName),
  });
  return { calls, results, service, replace };
});

vi.mock('@config/db', () => ({
  query: async (sql: string, params?: unknown[]) =>
    (await pg.db.query(sql, params ?? [])).rows,
}));

vi.mock('@modules/tenancies/tenancy.service', stubs.replace('TenancyService'));
vi.mock('@modules/billing/billing.service', stubs.replace('BillingService'));
vi.mock('@modules/gate-passes/gate-passes.service', stubs.replace('GatePassesService'));
vi.mock('@modules/mess-menu/mess-menu.service', stubs.replace('MessMenuService'));
vi.mock('@modules/meter-readings/meter-readings.service', stubs.replace('MeterReadingsService'));
vi.mock('@modules/staff/staff.service', stubs.replace('StaffService'));
vi.mock('@modules/expenses/expense.service', stubs.replace('ExpenseService'));
vi.mock('@modules/dashboard/dashboard.service', stubs.replace('DashboardService'));
vi.mock('@modules/analytics/analytics.service', stubs.replace('AnalyticsService'));
vi.mock('@modules/reports/reports.service', stubs.replace('ReportsService'));
vi.mock('@modules/properties/properties.service', stubs.replace('PropertiesService'));
vi.mock('@modules/subscriptions/subscription.service', stubs.replace('SubscriptionService'));
vi.mock('@modules/subscriptions/entitlement.service', stubs.replace('EntitlementService'));
vi.mock('@modules/tenant-portal/tenant-portal.service', stubs.replace('TenantPortalService'));
vi.mock('@core/structure-engine/services/structure.service', stubs.replace('StructureService'));
vi.mock('@modules/structure/apartment-quota', () => ({
  assertApartmentNodeQuota: async () => undefined,
}));
vi.mock('@modules/properties/property-manageability', () => ({
  assertCanManageProperty: async () => undefined,
}));

const ORG_1 = '01000000-0000-4000-8000-000000000000';
const ORG_2 = '02000000-0000-4000-8000-000000000000';
const P1 = '11000000-0000-4000-8000-000000000001';
const P2 = '12000000-0000-4000-8000-000000000002';
// Another property of ORG_1 that the manager and staff are not assigned to.
const P3 = '13000000-0000-4000-8000-000000000003';
const U = {
  owner1: '31000000-0000-4000-8000-000000000001',
  admin1: '31000000-0000-4000-8000-000000000002',
  owner2: '31000000-0000-4000-8000-000000000003',
  manager1: '31000000-0000-4000-8000-000000000004',
  staff1: '31000000-0000-4000-8000-000000000005',
  pending: '31000000-0000-4000-8000-000000000006',
  inactive: '31000000-0000-4000-8000-000000000007',
  revoked: '31000000-0000-4000-8000-000000000008',
  laterRemoved: '31000000-0000-4000-8000-000000000009',
  tenantA: '31000000-0000-4000-8000-00000000000a',
  tenant2: '31000000-0000-4000-8000-00000000000b',
};
const TEN_A = '41000000-0000-4000-8000-00000000000a';
const TEN_2 = '41000000-0000-4000-8000-00000000000b';
const INV_1 = '61000000-0000-4000-8000-000000000001';
const INV_2 = '62000000-0000-4000-8000-000000000002';
const GP_1 = '71000000-0000-4000-8000-000000000001';
const GP_2 = '72000000-0000-4000-8000-000000000002';
const UNIT_1 = '21000000-0000-4000-8000-000000000001';
const UNIT_2 = '22000000-0000-4000-8000-000000000002';
const LEVEL_1 = '91000000-0000-4000-8000-000000000001';
const LEVEL_2 = '92000000-0000-4000-8000-000000000002';
const CT_1 = '81000000-0000-4000-8000-000000000001';

const sign = (claims: Record<string, unknown>) =>
  jwt.sign(claims, process.env.JWT_ACCESS_SECRET!, { expiresIn: '5m' });
const orgToken = (sub: string, org: string, role: string) =>
  sign({ sub, ctxType: 'organization', ctxId: org, ctxRole: role, ctxPropertyId: null });
const propToken = (sub: string, property: string, role: string) =>
  sign({ sub, ctxType: 'organization', ctxId: property, ctxRole: role, ctxPropertyId: property });

const T = {
  owner1: () => orgToken(U.owner1, ORG_1, 'owner'),
  admin1: () => orgToken(U.admin1, ORG_1, 'admin'),
  owner2: () => orgToken(U.owner2, ORG_2, 'owner'),
  manager1: () => propToken(U.manager1, P1, 'manager'),
  staff1: () => propToken(U.staff1, P1, 'staff'),
  tenantA: () =>
    sign({ sub: U.tenantA, ctxType: 'tenancy', ctxId: TEN_A, ctxRole: 'tenant', ctxPropertyId: P1 }),
};

const SENSITIVE_TENANCY = {
  id: TEN_A,
  property_id: P1,
  full_name: 'Asha Tenant',
  phone: '9876500001',
  email: 'asha.private@example.com',
  address: '12 Hidden Lane, Pune',
  company_name: 'Asha Corp',
  occupation: 'Engineer',
  notes: 'Owner-only note',
  profile_photo_url: '/uploads/tenant-photos/a.jpg',
  emergency_contact_name: 'Ravi',
  emergency_contact_phone: '9876500099',
  node_name: 'Room 101',
  status: 'active',
  aadhaar_number: '1234-5678-9012',
  id_type: 'aadhaar',
  agreement_pdf_url: '/uploads/agreements/a.pdf',
  monthly_rent: '9000.00',
  security_deposit: '18000.00',
  has_due: true,
  earliest_open_due_date: '2026-10-05',
  has_overdue: true,
  has_draft: false,
  has_sent_invoice: true,
};

let baseUrl = '';
let server: ReturnType<express.Express['listen']>;

beforeAll(async () => {
  const { PGlite } = await import('@electric-sql/pglite');
  pg.db = new PGlite();
  await pg.db.exec(`
    CREATE TABLE properties (id uuid PRIMARY KEY, organization_id uuid);
    CREATE TABLE memberships (user_id uuid, organization_id uuid, role text);
    CREATE TABLE property_staff_assignments (user_id uuid, property_id uuid, role text, status text);
    CREATE TABLE tenancies (id uuid PRIMARY KEY, property_id uuid, user_id uuid, status text);
    CREATE TABLE invoices (id uuid PRIMARY KEY, property_id uuid);
    CREATE TABLE charge_types (id uuid PRIMARY KEY, property_id uuid);
    CREATE TABLE complaints (id uuid PRIMARY KEY, property_id uuid);
    CREATE TABLE gate_passes (id uuid PRIMARY KEY, property_id uuid);
    CREATE TABLE hierarchy_nodes (id uuid PRIMARY KEY, property_id uuid);
    CREATE TABLE hierarchy_levels (id uuid PRIMARY KEY, property_id uuid);
  `);
  await pg.db.query(`INSERT INTO hierarchy_nodes VALUES ($1, $2), ($3, $4)`, [UNIT_1, P1, UNIT_2, P2]);
  await pg.db.query(`INSERT INTO hierarchy_levels VALUES ($1, $2), ($3, $4)`, [LEVEL_1, P1, LEVEL_2, P2]);
  await pg.db.query(`INSERT INTO properties VALUES ($1, $2), ($3, $4), ($5, $2)`, [
    P1, ORG_1, P2, ORG_2, P3,
  ]);
  await pg.db.query(
    `INSERT INTO memberships VALUES ($1, $4, 'owner'), ($2, $4, 'admin'), ($3, $5, 'owner')`,
    [U.owner1, U.admin1, U.owner2, ORG_1, ORG_2],
  );
  await pg.db.query(
    `INSERT INTO property_staff_assignments VALUES
       ($1, $7, 'manager', 'active'),
       ($2, $7, 'staff', 'active'),
       ($3, $7, 'manager', 'pending'),
       ($4, $7, 'staff', 'inactive'),
       ($5, $7, 'manager', 'revoked'),
       ($6, $7, 'staff', 'active')`,
    [U.manager1, U.staff1, U.pending, U.inactive, U.revoked, U.laterRemoved, P1],
  );
  await pg.db.query(`INSERT INTO tenancies VALUES ($1, $2, $3, 'active'), ($4, $5, $6, 'active')`, [
    TEN_A, P1, U.tenantA, TEN_2, P2, U.tenant2,
  ]);
  await pg.db.query(`INSERT INTO invoices VALUES ($1, $2), ($3, $4)`, [INV_1, P1, INV_2, P2]);
  await pg.db.query(`INSERT INTO gate_passes VALUES ($1, $2), ($3, $4)`, [GP_1, P1, GP_2, P2]);
  await pg.db.query(`INSERT INTO charge_types VALUES ($1, $2)`, [CT_1, P1]);

  const { propertiesRouter } = await import('../../modules/properties/properties.routes.js');
  const { subscriptionRouter } = await import('../../modules/subscriptions/subscription.routes.js');
  const { orgAnalyticsRouter } = await import('../../modules/analytics/org-analytics.routes.js');
  const { errorHandler } = await import('./error-handler.js');

  const app = express();
  app.use(express.json());
  app.use('/v1/properties', propertiesRouter);
  app.use('/v1/organizations/:organizationId/analytics', orgAnalyticsRouter);
  app.use('/v1/subscriptions', subscriptionRouter);
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

beforeEach(() => {
  stubs.calls.length = 0;
  for (const key of Object.keys(stubs.results)) delete stubs.results[key];
  stubs.results['TenancyService.listByProperty'] = () => [SENSITIVE_TENANCY];
  stubs.results['TenancyService.getById'] = () => SENSITIVE_TENANCY;
  stubs.results['PropertiesService.getById'] = (id: string) => ({ id });
  stubs.results['PropertiesService.create'] = (input: any) => ({ id: P3, ...input });
});

async function call(method: string, urlPath: string, tok?: string, body?: unknown) {
  const res = await fetch(`${baseUrl}${urlPath}`, {
    method,
    headers: {
      ...(tok ? { authorization: `Bearer ${tok}` } : {}),
      ...(body !== undefined ? { 'content-type': 'application/json' } : {}),
    },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json: any = null;
  try {
    json = JSON.parse(text);
  } catch {
    json = null;
  }
  return { status: res.status, text, body: json };
}

const prop = (propertyId: string, rest = '') => `/v1/properties/${propertyId}${rest}`;
const serviceCalls = () => stubs.calls.map((c) => c.name);

/** Refused with `status` and no service method ran. */
async function expectRefused(
  method: string,
  urlPath: string,
  tok: string | undefined,
  status: number,
  body?: unknown,
) {
  stubs.calls.length = 0;
  const res = await call(method, urlPath, tok, body);
  expect({ route: `${method} ${urlPath}`, status: res.status }).toEqual({
    route: `${method} ${urlPath}`,
    status,
  });
  expect({ route: `${method} ${urlPath}`, calls: serviceCalls() }).toEqual({
    route: `${method} ${urlPath}`,
    calls: [],
  });
  return res;
}

/** Passed authorization and the handler reached its service. */
async function expectAllowed(method: string, urlPath: string, tok: string, body?: unknown) {
  stubs.calls.length = 0;
  const res = await call(method, urlPath, tok, body);
  expect({ route: `${method} ${urlPath}`, status: res.status < 300 }).toEqual({
    route: `${method} ${urlPath}`,
    status: true,
  });
  expect(serviceCalls().length).toBeGreaterThan(0);
  return res;
}

const DAY = { dayOfWeek: 1, breakfast: 'Idli', lunch: 'Rice', dinner: 'Roti' };

// Routes no manager may use: team membership, ownership and subscription.
const OWNER_ONLY: [string, string, unknown?][] = [
  ['POST', prop(P1, '/staff'), { phone: '9999999999', role: 'staff' }],
  ['POST', prop(P1, '/staff'), { phone: '9999999999', role: 'manager' }],
  ['DELETE', prop(P1, `/staff/${U.staff1}`)],
  ['POST', '/v1/properties', { propertyTypeKey: 'hostel', name: 'New' }],
  ['GET', '/v1/subscriptions/me'],
  ['POST', '/v1/subscriptions/create-order', { planKey: 'pro' }],
  ['POST', '/v1/subscriptions/cancel'],
  ['GET', `/v1/organizations/${ORG_1}/analytics`],
];

describe('authentication conventions', () => {
  it('401 without a token, with a forged token, or without a selected workspace', async () => {
    await expectRefused('GET', prop(P1, '/tenancies'), undefined, 401);
    const forged = jwt.sign(
      { sub: U.owner1, ctxType: 'organization', ctxId: ORG_1, ctxRole: 'owner' },
      'not-the-server-secret',
    );
    await expectRefused('GET', prop(P1, '/tenancies'), forged, 401);
    await expectRefused('GET', prop(P1, '/tenancies'), sign({ sub: U.owner1 }), 401);
  });
});

describe('manager on the assigned property', () => {
  it('runs day-to-day operations', async () => {
    const tok = T.manager1();
    await expectAllowed('GET', prop(P1), tok);
    await expectAllowed('GET', prop(P1, '/dashboard'), tok);
    await expectAllowed('GET', prop(P1, '/structure/nodes'), tok);
    await expectAllowed('POST', prop(P1, '/structure/nodes'), tok, { name: 'Room 102' });
    await expectAllowed('GET', prop(P1, '/tenancies'), tok);
    await expectAllowed('GET', prop(P1, `/tenancies/${TEN_A}`), tok);
    await expectAllowed('GET', prop(P1, `/tenancies/${TEN_A}/documents`), tok);
    await expectAllowed('GET', prop(P1, '/billing/invoices'), tok);
    await expectAllowed('GET', prop(P1, '/meter-readings'), tok);
    await expectAllowed('POST', prop(P1, '/meter-readings'), tok, {
      unitId: UNIT_1,
      readingValue: 120,
      ratePerUnit: 9,
    });
    await expectAllowed('GET', prop(P1, '/gate-passes'), tok);
    await expectAllowed('PATCH', prop(P1, `/gate-passes/${GP_1}`), tok, { status: 'approved' });
    await expectAllowed('PUT', prop(P1, '/mess-menu/day'), tok, DAY);
    await expectAllowed('GET', prop(P1, '/staff'), tok);
  });

  it('sees full tenancy records', async () => {
    const res = await expectAllowed('GET', prop(P1, '/tenancies'), T.manager1());
    expect(res.body.data[0]).toEqual(SENSITIVE_TENANCY);
  });

  it('cannot reach an unassigned property, even of the same organization', async () => {
    for (const property of [P2, P3]) {
      await expectRefused('GET', prop(property), T.manager1(), 403);
      await expectRefused('GET', prop(property, '/tenancies'), T.manager1(), 403);
      await expectRefused('PUT', prop(property, '/mess-menu/day'), T.manager1(), 403, DAY);
    }
  });

  it('cannot manage the team, ownership, settings or subscription', async () => {
    for (const [method, url, body] of OWNER_ONLY) {
      await expectRefused(method, url, T.manager1(), 403, body);
    }
  });

  it('keeps invoice approval, payments and charge types, but cannot delete expenses', async () => {
    const tok = T.manager1();
    await expectAllowed('POST', prop(P1, `/billing/invoices/${INV_1}/send`), tok);
    await expectAllowed('POST', prop(P1, `/billing/invoices/${INV_1}/payments`), tok, {
      amount: 100,
      method: 'cash',
    });
    await expectAllowed('DELETE', prop(P1, `/billing/charge-types/${CT_1}`), tok);
    await expectAllowed('GET', prop(P1, '/expenses'), tok);
    await expectRefused('DELETE', prop(P1, `/expenses/${INV_1}`), tok, 403);
    for (const owner of [T.owner1(), T.admin1()]) {
      await expectAllowed('DELETE', prop(P1, `/expenses/${INV_1}`), owner);
    }
  });

  it('owners and admins keep those owner-only operations', async () => {
    await expectAllowed('POST', prop(P1, '/staff'), T.owner1(), { phone: '9999999999', role: 'staff' });
    await expectAllowed('DELETE', prop(P1, `/staff/${U.staff1}`), T.admin1());
    await expectAllowed('GET', '/v1/subscriptions/me', T.admin1());
  });
});

describe('staff on the assigned property', () => {
  it('views the property, rooms, tenants and team, and runs operational workflows', async () => {
    const tok = T.staff1();
    await expectAllowed('GET', prop(P1), tok);
    await expectAllowed('GET', prop(P1, '/structure/levels'), tok);
    await expectAllowed('GET', prop(P1, '/structure/nodes'), tok);
    await expectAllowed('GET', prop(P1, '/tenancies'), tok);
    await expectAllowed('GET', prop(P1, '/meter-readings'), tok);
    await expectAllowed('POST', prop(P1, '/meter-readings'), tok, { unitId: UNIT_1, readingValue: 120 });
    await expectAllowed('GET', prop(P1, '/gate-passes'), tok);
    await expectAllowed('PATCH', prop(P1, `/gate-passes/${GP_1}`), tok, { status: 'denied' });
    await expectAllowed('GET', prop(P1, '/mess-menu'), tok);
    await expectAllowed('PUT', prop(P1, '/mess-menu'), tok, { days: [DAY] });
  });

  it('cannot list the team or its phone numbers', async () => {
    await expectRefused('GET', prop(P1, '/staff'), T.staff1(), 403);
  });

  it('receives only name, place and status fields of tenancies', async () => {
    const list = await expectAllowed('GET', prop(P1, '/tenancies'), T.staff1());
    const one = await expectAllowed('GET', prop(P1, `/tenancies/${TEN_A}`), T.staff1());
    for (const res of [list, one]) {
      const row = res === list ? res.body.data[0] : res.body.data;
      expect(row).toEqual({
        id: TEN_A,
        property_id: P1,
        full_name: 'Asha Tenant',
        node_name: 'Room 101',
        status: 'active',
      });
      for (const secret of [
        '1234-5678-9012', '9000.00', '18000.00', '98765000', 'asha.private@example.com',
        'Hidden Lane', 'Asha Corp', 'Owner-only note', 'tenant-photos', 'Ravi',
      ]) {
        expect(res.text).not.toContain(secret);
      }
    }
  });

  it('managers still receive the full tenancy record', async () => {
    const one = await expectAllowed('GET', prop(P1, `/tenancies/${TEN_A}`), T.manager1());
    expect(one.body.data).toEqual(SENSITIVE_TENANCY);
  });

  it('lists only this property\'s nodes, without rent, deposit or pricing metadata', async () => {
    const node = {
      id: UNIT_1,
      propertyId: P1,
      levelId: LEVEL_1,
      parentNodeId: null,
      name: 'Room 101',
      monthlyRent: 9000,
      securityDeposit: 18000,
      metadata: { bed_capacity: 3, space_type: 'room', monthly_rent: 9000, security_deposit: 18000 },
    };
    stubs.results['StructureService.listNodes'] = () => [node];

    const staff = await expectAllowed('GET', prop(P1, `/structure/nodes?levelId=${LEVEL_1}`), T.staff1());
    expect(stubs.calls.find((c) => c.name === 'StructureService.listNodes')?.args).toEqual([
      P1, LEVEL_1, null,
    ]);
    expect(staff.body.data).toEqual([
      {
        id: UNIT_1,
        propertyId: P1,
        levelId: LEVEL_1,
        parentNodeId: null,
        name: 'Room 101',
        metadata: { bed_capacity: 3, space_type: 'room' },
      },
    ]);
    expect(staff.text).not.toContain('9000');
    expect(staff.text).not.toContain('18000');

    const manager = await expectAllowed('GET', prop(P1, `/structure/nodes?levelId=${LEVEL_1}`), T.manager1());
    expect(manager.body.data).toEqual([node]);
  });

  it('meter readings come without rate, amount or invoice links', async () => {
    const reading = {
      id: 'r1',
      property_id: P1,
      unit_id: UNIT_1,
      unit_name: 'Room 101',
      meter_reading_value: '150.000',
      previous_reading: '100.000',
      units_consumed: '50.000',
      rate_per_unit: '8.7500',
      amount: '437.50',
      invoice_id: INV_1,
      invoice_line_item_id: CT_1,
      billing_cycle: '2026-10',
      created_at: '2026-10-14T10:00:00Z',
    };
    stubs.results['MeterReadingsService.listByProperty'] = () => [reading];
    stubs.results['MeterReadingsService.submit'] = () => reading;

    const list = await expectAllowed('GET', prop(P1, '/meter-readings'), T.staff1());
    const submitted = await expectAllowed('POST', prop(P1, '/meter-readings'), T.staff1(), {
      unitId: UNIT_1,
      readingValue: 150,
    });
    for (const row of [list.body.data[0], submitted.body.data]) {
      expect(row).toMatchObject({ id: 'r1', meter_reading_value: '150.000', previous_reading: '100.000' });
      for (const field of ['rate_per_unit', 'amount', 'invoice_id', 'invoice_line_item_id']) {
        expect(row).not.toHaveProperty(field);
      }
    }
    expect(list.text).not.toContain('437.50');

    const manager = await expectAllowed('GET', prop(P1, '/meter-readings'), T.manager1());
    expect(manager.body.data[0]).toMatchObject({ rate_per_unit: '8.7500', amount: '437.50' });
  });

  it('invalid readings are refused with a 400 code before any service call', async () => {
    for (const readingValue of [0, -5, 'abc', '', null, 'Infinity', 1e12]) {
      const res = await expectRefused('POST', prop(P1, '/meter-readings'), T.staff1(), 400, {
        unitId: UNIT_1,
        readingValue,
      });
      expect(res.body).toEqual({ error: 'Reading must be a positive number.', code: 'invalid_reading' });
    }
    const missing = await expectRefused('POST', prop(P1, '/meter-readings'), T.staff1(), 400, {
      unitId: UNIT_1,
    });
    expect(missing.body.code).toBe('invalid_reading');
  });

  it('cannot open tenant KYC documents', async () => {
    await expectRefused('GET', prop(P1, `/tenancies/${TEN_A}/documents`), T.staff1(), 403);
    await expectRefused(
      'GET',
      prop(P1, `/tenancies/${TEN_A}/documents/${INV_1}/file`),
      T.staff1(),
      403,
    );
  });

  it('cannot change rooms, beds, tenancies or rates', async () => {
    const tok = T.staff1();
    await expectRefused('POST', prop(P1, '/structure/nodes'), tok, 403, { name: 'Room 9' });
    await expectRefused('PATCH', prop(P1, `/structure/nodes/${UNIT_1}`), tok, 403, { name: 'X' });
    await expectRefused('DELETE', prop(P1, `/structure/nodes/${UNIT_1}`), tok, 403);
    await expectRefused('POST', prop(P1, '/structure/levels'), tok, 403, { displayName: 'Wing' });
    await expectRefused('POST', prop(P1, '/tenancies'), tok, 403, { fullName: 'X' });
    await expectRefused('PATCH', prop(P1, `/tenancies/${TEN_A}`), tok, 403, { monthlyRent: 1 });
    await expectRefused('POST', prop(P1, `/tenancies/${TEN_A}/end`), tok, 403);
    await expectRefused('POST', prop(P1, '/meter-readings'), tok, 403, {
      unitId: UNIT_1,
      readingValue: 120,
      ratePerUnit: 1,
    });
  });

  it('has no billing, payment, expense, dashboard or report access', async () => {
    const tok = T.staff1();
    for (const [method, url] of [
      ['GET', prop(P1, '/billing/invoices')],
      ['GET', prop(P1, `/billing/invoices/${INV_1}`)],
      ['POST', prop(P1, `/billing/invoices/${INV_1}/send`)],
      ['POST', prop(P1, `/billing/invoices/${INV_1}/payments`)],
      ['PATCH', prop(P1, `/billing/invoices/${INV_1}`)],
      ['POST', prop(P1, '/billing/charge-types')],
      ['GET', prop(P1, '/billing/payments')],
      ['GET', prop(P1, '/expenses')],
      ['DELETE', prop(P1, `/expenses/${INV_1}`)],
      ['GET', prop(P1, '/dashboard')],
      ['GET', prop(P1, '/reports/occupancy')],
      ['GET', prop(P1, '/analytics')],
    ]) {
      await expectRefused(method, url, tok, 403, method === 'GET' || method === 'DELETE' ? undefined : {});
    }
  });

  it('cannot manage the team, ownership or subscription', async () => {
    for (const [method, url, body] of OWNER_ONLY) {
      await expectRefused(method, url, T.staff1(), 403, body);
    }
  });

  it('cannot reach another property', async () => {
    await expectRefused('GET', prop(P3, '/tenancies'), T.staff1(), 403);
    await expectRefused('GET', prop(P2, '/gate-passes'), T.staff1(), 403);
    for (const path of ['/structure/levels', '/structure/nodes', '/meter-readings', '/tenancies']) {
      await expectRefused('GET', prop(P2, path), T.staff1(), 403);
      await expectRefused('GET', prop(P3, path), T.staff1(), 403);
    }
    await expectRefused('POST', prop(P2, '/meter-readings'), T.staff1(), 403, {
      unitId: UNIT_2,
      readingValue: 10,
    });
  });
});

describe('tenant isolation from management APIs', () => {
  const tok = () => T.tenantA();

  it('a tenant of the property cannot use any team route', async () => {
    for (const [method, url, body] of [
      ['GET', prop(P1, '/tenancies')],
      ['GET', prop(P1, `/tenancies/${TEN_A}`)],
      ['GET', prop(P1, `/tenancies/${TEN_A}/documents`)],
      ['GET', prop(P1, '/structure/levels')],
      ['GET', prop(P1, '/structure/nodes')],
      ['GET', prop(P1, '/gate-passes')],
      ['PATCH', prop(P1, `/gate-passes/${GP_1}`), { status: 'approved' }],
      ['GET', prop(P1, '/mess-menu')],
      ['PUT', prop(P1, '/mess-menu/day'), DAY],
      ['PUT', prop(P1, '/mess-menu'), { days: [DAY] }],
      ['GET', prop(P1, '/billing/invoices')],
      ['GET', prop(P1, '/staff')],
      ['GET', prop(P1, '/dashboard')],
      ['GET', prop(P1, '/expenses')],
    ] as [string, string, unknown?][]) {
      await expectRefused(method, url, tok(), 403, body);
    }
  });

  it("a tenant's own tenancy record is not reachable through the team route", async () => {
    const res = await expectRefused('GET', prop(P1, `/tenancies/${TEN_A}`), tok(), 403);
    expect(res.text).not.toContain('1234-5678-9012');
  });
});

describe('membership state is rechecked on every request', () => {
  it('pending, inactive and revoked assignments grant nothing', async () => {
    for (const [user, role] of [
      [U.pending, 'manager'],
      [U.inactive, 'staff'],
      [U.revoked, 'manager'],
    ]) {
      await expectRefused('GET', prop(P1, '/tenancies'), propToken(user, P1, role), 403);
      await expectRefused('GET', prop(P1), propToken(user, P1, role), 403);
    }
  });

  it('a user without any assignment or membership gets nothing', async () => {
    await expectRefused('GET', prop(P1, '/tenancies'), propToken(U.tenant2, P1, 'manager'), 403);
    await expectRefused('GET', prop(P1, '/tenancies'), orgToken(U.tenant2, ORG_1, 'owner'), 403);
  });

  it('removal takes effect on the next request with the same token', async () => {
    const tok = propToken(U.laterRemoved, P1, 'staff');
    await expectAllowed('GET', prop(P1, '/gate-passes'), tok);
    await pg.db.query(
      `UPDATE property_staff_assignments SET status = 'revoked' WHERE user_id = $1`,
      [U.laterRemoved],
    );
    await expectRefused('GET', prop(P1, '/gate-passes'), tok, 403);
  });
});

describe('workspace switching and manipulated identifiers', () => {
  it('a token claiming a higher role than the assignment is refused', async () => {
    await expectRefused('POST', prop(P1, '/structure/nodes'), propToken(U.staff1, P1, 'manager'), 403, {
      name: 'Escalated',
    });
    await expectRefused('GET', '/v1/subscriptions/me', orgToken(U.manager1, ORG_1, 'owner'), 403);
    await expectRefused('GET', '/v1/subscriptions/me', orgToken(U.manager1, ORG_1, 'admin'), 403);
  });

  it('a workspace token cannot be pointed at a different property', async () => {
    const crossed = sign({
      sub: U.manager1, ctxType: 'organization', ctxId: P1, ctxRole: 'manager', ctxPropertyId: P2,
    });
    await expectRefused('GET', prop(P2, '/tenancies'), crossed, 403);
    await expectRefused('GET', prop(P1, '/tenancies'), crossed, 403);
    await expectRefused('GET', prop(P3, '/tenancies'), propToken(U.manager1, P3, 'manager'), 403);
    await expectRefused('GET', prop(P1, '/tenancies'), orgToken(U.owner2, ORG_1, 'owner'), 403);
    await expectRefused('GET', prop(P1, '/tenancies'), T.owner2(), 403);
  });

  it("another property's records answer 404 through an authorized property", async () => {
    for (const tok of [T.owner1(), T.manager1()]) {
      await expectRefused('GET', prop(P1, `/tenancies/${TEN_2}`), tok, 404);
      await expectRefused('GET', prop(P1, `/billing/invoices/${INV_2}`), tok, 404);
      await expectRefused('PATCH', prop(P1, `/gate-passes/${GP_2}`), tok, 404, { status: 'approved' });
      await expectRefused('PATCH', prop(P1, '/gate-passes/not-a-uuid'), tok, 404, {
        status: 'approved',
      });
    }
    await expectRefused('PATCH', prop(P1, `/gate-passes/${GP_2}`), T.staff1(), 404, {
      status: 'approved',
    });
  });

  it("another property's rooms and levels answer 404 through an authorized property", async () => {
    for (const tok of [T.owner1(), T.manager1()]) {
      await expectRefused('PATCH', prop(P1, `/structure/nodes/${UNIT_2}`), tok, 404, { name: 'X' });
      await expectRefused('DELETE', prop(P1, `/structure/nodes/${UNIT_2}`), tok, 404);
      await expectRefused('PATCH', prop(P1, `/structure/levels/${LEVEL_2}`), tok, 404, {
        displayName: 'X',
      });
      await expectRefused('DELETE', prop(P1, `/structure/levels/${LEVEL_2}`), tok, 404);
      await expectRefused('PATCH', prop(P1, '/structure/nodes/not-a-uuid'), tok, 404, { name: 'X' });
    }
    await expectAllowed('PATCH', prop(P1, `/structure/nodes/${UNIT_1}`), T.manager1(), { name: 'Room 1' });
    await expectAllowed('PATCH', prop(P1, `/structure/levels/${LEVEL_1}`), T.owner1(), {
      displayName: 'Wing',
    });
  });

  it('request-body identity and role fields cannot escalate', async () => {
    stubs.calls.length = 0;
    const created = await call('POST', '/v1/properties', T.owner1(), {
      propertyTypeKey: 'hostel',
      name: 'Annex',
      organizationId: ORG_2,
    });
    expect(created.status).toBe(201);
    expect(stubs.calls.find((c) => c.name === 'PropertiesService.create')?.args[0]).toMatchObject({
      organizationId: ORG_1,
    });

    await expectRefused('POST', prop(P1, '/staff'), T.owner1(), 400, {
      phone: '9999999999',
      role: 'owner',
    });

    stubs.calls.length = 0;
    const reading = await call('POST', prop(P1, '/meter-readings'), T.manager1(), {
      unitId: UNIT_1,
      readingValue: 50,
      propertyId: P2,
      submittedBy: U.owner1,
      role: 'owner',
    });
    expect(reading.status).toBe(201);
    expect(stubs.calls.find((c) => c.name === 'MeterReadingsService.submit')?.args[0]).toMatchObject({
      propertyId: P1,
      submittedBy: U.manager1,
    });

    stubs.calls.length = 0;
    const decided = await call('PATCH', prop(P1, `/gate-passes/${GP_1}`), T.staff1(), {
      status: 'approved',
      decidedBy: U.owner1,
      propertyId: P2,
    });
    expect(decided.status).toBe(200);
    expect(stubs.calls.find((c) => c.name === 'GatePassesService.decide')?.args).toEqual([
      P1, GP_1, 'approved', U.staff1,
    ]);
  });
});
