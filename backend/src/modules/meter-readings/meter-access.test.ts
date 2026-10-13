// Meter-reading access through the real routers, auth guard and SQL, on an
// in-memory Postgres (PGlite). No server process, network or real database.
import type { AddressInfo } from 'net';
import express from 'express';
import jwt from 'jsonwebtoken';
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';

process.env.DATABASE_URL ??= 'postgres://test:test@127.0.0.1:1/test';
process.env.JWT_ACCESS_SECRET = 'meter-access-test-secret';
process.env.JWT_REFRESH_SECRET ??= 'test';
process.env.RAZORPAY_KEY_ID ??= 'rzp_test_x';
process.env.RAZORPAY_KEY_SECRET ??= 'test';
process.env.RAZORPAY_WEBHOOK_SECRET ??= 'test';

const pg = vi.hoisted(() => ({ db: null as any }));

vi.mock('@config/db', () => {
  const run = async (sql: string, params?: unknown[]) =>
    (await pg.db.query(sql, params ?? [])).rows;
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

// Billing internals are covered elsewhere; here only the meter access path runs.
vi.mock('@modules/billing/billing.service', () => {
  class Stub extends Error {}
  return {
    BillingService: class {
      async listChargeTypes() {
        return [];
      }
    },
    billingSchemaCaps: async () => ({ invoiceKind: true, approvedBy: true }),
    ensureBillingSchema: async () => undefined,
    InvoiceConflictError: Stub,
    InvoiceLockedError: Stub,
    MoveInDateLockedError: Stub,
  };
});

const ORG_1 = '01000000-0000-4000-8000-000000000000';
const ORG_2 = '02000000-0000-4000-8000-000000000000';
const P1 = '11000000-0000-4000-8000-000000000000';
const P2 = '12000000-0000-4000-8000-000000000000';
const U1 = '21000000-0000-4000-8000-000000000001'; // tenant A's unit
const U2 = '21000000-0000-4000-8000-000000000002'; // tenant B's unit, same property
const U3 = '22000000-0000-4000-8000-000000000003'; // other property
const USER = {
  owner: '31000000-0000-4000-8000-000000000001',
  a: '31000000-0000-4000-8000-000000000002',
  b: '31000000-0000-4000-8000-000000000003',
  c: '31000000-0000-4000-8000-000000000004',
  old: '31000000-0000-4000-8000-000000000005',
  manager: '31000000-0000-4000-8000-000000000006',
};
const TEN = {
  a: '41000000-0000-4000-8000-000000000001',
  b: '41000000-0000-4000-8000-000000000002',
  c: '42000000-0000-4000-8000-000000000003',
  ended: '41000000-0000-4000-8000-000000000004',
};
const READING = {
  old: '51000000-0000-4000-8000-000000000000',
  a: '51000000-0000-4000-8000-000000000001',
  b: '51000000-0000-4000-8000-000000000002',
  c: '52000000-0000-4000-8000-000000000003',
};

const token = (claims: Record<string, unknown>) =>
  jwt.sign(claims, process.env.JWT_ACCESS_SECRET!, { expiresIn: '5m' });

const tenantToken = (user: string, tenancy: string, property: string) =>
  token({ sub: user, ctxType: 'tenancy', ctxId: tenancy, ctxRole: 'tenant', ctxPropertyId: property });

const TOKENS = {
  tenantA: () => tenantToken(USER.a, TEN.a, P1),
  tenantB: () => tenantToken(USER.b, TEN.b, P1),
  endedTenant: () => tenantToken(USER.old, TEN.ended, P1),
  // Signed context for tenancy B presented by user A.
  tenantAWithBsTenancy: () => tenantToken(USER.a, TEN.b, P1),
  owner1: () => token({ sub: USER.owner, ctxType: 'organization', ctxId: ORG_1, ctxRole: 'owner', ctxPropertyId: null }),
  admin1: () => token({ sub: USER.owner, ctxType: 'organization', ctxId: ORG_1, ctxRole: 'admin', ctxPropertyId: null }),
  manager1: () => token({ sub: USER.manager, ctxType: 'organization', ctxId: P1, ctxRole: 'manager', ctxPropertyId: P1 }),
  staff1: () => token({ sub: USER.manager, ctxType: 'organization', ctxId: P1, ctxRole: 'staff', ctxPropertyId: P1 }),
};

let baseUrl = '';
let server: ReturnType<express.Express['listen']>;

async function resetData() {
  await pg.db.exec(`
    TRUNCATE meter_readings, tenancies, hierarchy_nodes, properties, users, invoices;
  `);
  await pg.db.query(
    `INSERT INTO properties VALUES ($1, $2, 'Asia/Kolkata', 'rental_house'),
                                   ($3, $4, 'Asia/Kolkata', 'rental_house')`,
    [P1, ORG_1, P2, ORG_2],
  );
  await pg.db.query(
    `INSERT INTO hierarchy_nodes VALUES ($1, $4, 'House A'), ($2, $4, 'House B'), ($3, $5, 'House C')`,
    [U1, U2, U3, P1, P2],
  );
  for (const id of Object.values(USER)) {
    await pg.db.query(`INSERT INTO users VALUES ($1, 'u')`, [id]);
  }
  await pg.db.query(
    `INSERT INTO tenancies (id, property_id, node_id, user_id, status, created_at) VALUES
       ($1, $5, $7, $9,  'ended',  now() - interval '400 days'),
       ($2, $5, $7, $10, 'active', now() - interval '100 days'),
       ($3, $5, $8, $11, 'active', now() - interval '100 days'),
       ($4, $6, $12, $13, 'active', now() - interval '100 days')`,
    [TEN.ended, TEN.a, TEN.b, TEN.c, P1, P2, U1, U2, USER.old, USER.a, USER.b, U3, USER.c],
  );
  await pg.db.query(
    `INSERT INTO meter_readings (id, property_id, unit_id, tenancy_id, meter_reading_value,
                                 billing_cycle, submitted_by, created_at) VALUES
       ($1, $5, $7, $9,  40,  '2025-09', $13, now() - interval '200 days'),
       ($2, $5, $7, $10, 100, '2026-09', $14, now() - interval '20 days'),
       ($3, $5, $8, $11, 300, '2026-09', $15, now() - interval '20 days'),
       ($4, $6, $12, $16, 900, '2026-09', $17, now() - interval '20 days')`,
    [
      READING.old, READING.a, READING.b, READING.c, P1, P2, U1, U2,
      TEN.ended, TEN.a, TEN.b, U3, USER.old, USER.a, USER.b, TEN.c, USER.c,
    ],
  );
}

beforeAll(async () => {
  const { PGlite } = await import('@electric-sql/pglite');
  pg.db = new PGlite();
  await pg.db.exec(`
    CREATE TABLE properties (id uuid PRIMARY KEY, organization_id uuid, timezone text,
      property_type_key text);
    CREATE TABLE hierarchy_nodes (id uuid PRIMARY KEY, property_id uuid, name text);
    CREATE TABLE users (id uuid PRIMARY KEY, name text);
    CREATE TABLE tenancies (id uuid PRIMARY KEY, property_id uuid, node_id uuid, user_id uuid,
      status text, created_at timestamptz DEFAULT now());
    CREATE TABLE invoices (id uuid PRIMARY KEY, tenancy_id uuid, property_id uuid,
      period_start date, period_end date, status text, sent_at timestamptz,
      invoice_kind text, is_auto_generated boolean, total_amount numeric(12,2),
      created_at timestamptz DEFAULT now());
    CREATE TABLE meter_readings (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      property_id uuid NOT NULL, unit_id uuid NOT NULL, tenancy_id uuid,
      meter_reading_value numeric(14,3) NOT NULL, previous_reading numeric(14,3),
      units_consumed numeric(14,3), rate_per_unit numeric(12,4), amount numeric(12,2),
      meter_image_url text, billing_cycle text NOT NULL, submitted_by uuid NOT NULL,
      invoice_id uuid, invoice_line_item_id uuid,
      created_at timestamptz NOT NULL DEFAULT now());
  `);

  const { authGuard, requireContext, requireRole, requirePropertyAccess } = await import(
    '../../shared/middleware/auth-guard.js'
  );
  const { meterReadingsRouter } = await import('./meter-readings.routes.js');
  const { MeterReadingsController, uploadMeterImageMiddleware } = await import(
    './meter-readings.controller.js'
  );
  const { errorHandler } = await import('../../shared/middleware/error-handler.js');

  // Same middleware chain as properties.routes.ts and tenant-portal.routes.ts.
  const tenantPortal = express.Router();
  const meter = new MeterReadingsController();
  tenantPortal.use(authGuard, requireContext, requireRole('tenant'));
  tenantPortal.get('/meter-readings', meter.myReadings);
  tenantPortal.post('/meter-readings', uploadMeterImageMiddleware, meter.submitMine);

  const app = express();
  app.use(express.json());
  app.use(
    '/v1/properties/:propertyId/meter-readings',
    authGuard,
    requireContext,
    requirePropertyAccess,
    meterReadingsRouter,
  );
  app.use('/v1/tenant-portal', tenantPortal);
  app.use(errorHandler);
  await new Promise<void>((resolve) => {
    server = app.listen(0, resolve);
  });
  baseUrl = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  // PGlite boot is slow when several in-memory databases start in parallel.
}, 60_000);

afterAll(async () => {
  server?.close();
  await pg.db?.close();
});

beforeEach(async () => {
  await resetData();
  vi.spyOn(console, 'error').mockImplementation(() => undefined);
});

async function call(method: 'GET' | 'POST', path: string, tok: string, body?: unknown) {
  const res = await fetch(`${baseUrl}${path}`, {
    method,
    headers: {
      authorization: `Bearer ${tok}`,
      ...(body ? { 'content-type': 'application/json' } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, body: (await res.json().catch(() => null)) as any };
}

const ids = (rows: any[]) => rows.map((r) => r.id).sort();
const readingCount = async () =>
  Number((await pg.db.query(`SELECT COUNT(*)::int AS n FROM meter_readings`)).rows[0].n);

describe('tenant listing', () => {
  it("a tenant sees only their own tenancy's readings on their unit (tenant portal)", async () => {
    const res = await call('GET', '/v1/tenant-portal/meter-readings', TOKENS.tenantA());
    expect(res.status).toBe(200);
    // Not tenant B's unit, and not the previous occupant's reading on the same unit.
    expect(ids(res.body.data)).toEqual([READING.a]);
  });

  it("the property route gives a tenant the same scope, never another tenant's readings", async () => {
    const res = await call('GET', `/v1/properties/${P1}/meter-readings`, TOKENS.tenantA());
    expect(res.status).toBe(200);
    expect(ids(res.body.data)).toEqual([READING.a]);

    const b = await call('GET', `/v1/properties/${P1}/meter-readings`, TOKENS.tenantB());
    expect(ids(b.body.data)).toEqual([READING.b]);
  });

  it('cross-property listing is refused', async () => {
    const res = await call('GET', `/v1/properties/${P2}/meter-readings`, TOKENS.tenantA());
    expect(res.status).toBe(403);
    expect(JSON.stringify(res.body)).not.toContain(READING.c);
  });

  it('an ended tenancy or a tenancy token held by another user grants nothing', async () => {
    expect((await call('GET', '/v1/tenant-portal/meter-readings', TOKENS.endedTenant())).status).toBe(404);
    expect((await call('GET', `/v1/properties/${P1}/meter-readings`, TOKENS.endedTenant())).status).toBe(404);
    const forged = await call('GET', '/v1/tenant-portal/meter-readings', TOKENS.tenantAWithBsTenancy());
    expect(forged.status).toBe(404);
    expect(JSON.stringify(forged.body)).not.toContain(READING.b);
  });
});

describe('tenant submitting', () => {
  it('records a reading on their own unit and tenancy; a client rate is ignored', async () => {
    const res = await call('POST', '/v1/tenant-portal/meter-readings', TOKENS.tenantA(), {
      readingValue: 150,
      billingCycle: '2026-10',
      ratePerUnit: 0.01,
    });
    expect(res.status).toBe(201);
    expect(res.body.data).toMatchObject({ unit_id: U1, tenancy_id: TEN.a, property_id: P1 });
    expect(Number(res.body.data.rate_per_unit)).toBe(8);
  });

  it('accepts their own unit on the property route', async () => {
    const res = await call('POST', `/v1/properties/${P1}/meter-readings`, TOKENS.tenantA(), {
      unitId: U1,
      readingValue: 120,
    });
    expect(res.status).toBe(201);
    expect(res.body.data).toMatchObject({ unit_id: U1, tenancy_id: TEN.a });
  });

  it("refuses another tenant's unit in the same property with a plain 404", async () => {
    const before = await readingCount();
    const res = await call('POST', `/v1/properties/${P1}/meter-readings`, TOKENS.tenantA(), {
      unitId: U2,
      readingValue: 500,
    });
    expect(res.status).toBe(404);
    expect(res.body).toEqual({ error: 'Not found' });
    expect(await readingCount()).toBe(before);
  });

  it("refuses another tenant's tenancy id", async () => {
    const res = await call('POST', `/v1/properties/${P1}/meter-readings`, TOKENS.tenantA(), {
      unitId: U1,
      tenancyId: TEN.b,
      readingValue: 500,
    });
    expect(res.status).toBe(404);
  });

  it('refuses another property', async () => {
    const before = await readingCount();
    const res = await call('POST', `/v1/properties/${P2}/meter-readings`, TOKENS.tenantA(), {
      unitId: U3,
      readingValue: 950,
    });
    expect(res.status).toBe(403);
    expect(await readingCount()).toBe(before);
  });

  it('an ended tenancy cannot submit', async () => {
    const res = await call('POST', '/v1/tenant-portal/meter-readings', TOKENS.endedTenant(), {
      readingValue: 150,
    });
    expect(res.status).toBe(404);
  });
});

describe('owner / admin / manager permissions', () => {
  it('owner and admin list every reading of their own property only', async () => {
    for (const tok of [TOKENS.owner1(), TOKENS.admin1()]) {
      const res = await call('GET', `/v1/properties/${P1}/meter-readings`, tok);
      expect(res.status).toBe(200);
      expect(ids(res.body.data)).toEqual([READING.old, READING.a, READING.b].sort());
      expect((await call('GET', `/v1/properties/${P2}/meter-readings`, tok)).status).toBe(403);
    }
  });

  it('owner records a reading for any unit of the property; the active tenancy is resolved', async () => {
    const res = await call('POST', `/v1/properties/${P1}/meter-readings`, TOKENS.owner1(), {
      unitId: U2,
      readingValue: 350,
      ratePerUnit: 10,
    });
    expect(res.status).toBe(201);
    expect(res.body.data).toMatchObject({ unit_id: U2, tenancy_id: TEN.b });
    expect(Number(res.body.data.rate_per_unit)).toBe(10);
  });

  it("owner cannot use another property's unit or a tenancy from a different unit", async () => {
    const before = await readingCount();
    const foreignUnit = await call('POST', `/v1/properties/${P1}/meter-readings`, TOKENS.owner1(), {
      unitId: U3,
      readingValue: 950,
    });
    expect(foreignUnit.status).toBe(404);
    const wrongTenancy = await call('POST', `/v1/properties/${P1}/meter-readings`, TOKENS.owner1(), {
      unitId: U1,
      tenancyId: TEN.b,
      readingValue: 150,
    });
    expect(wrongTenancy.status).toBe(404);
    expect(await readingCount()).toBe(before);
  });

  it('manager keeps list and submit on the assigned property only', async () => {
    const list = await call('GET', `/v1/properties/${P1}/meter-readings`, TOKENS.manager1());
    expect(list.status).toBe(200);
    expect(list.body.data).toHaveLength(3);
    const submit = await call('POST', `/v1/properties/${P1}/meter-readings`, TOKENS.manager1(), {
      unitId: U1,
      readingValue: 130,
    });
    expect(submit.status).toBe(201);
    expect((await call('GET', `/v1/properties/${P2}/meter-readings`, TOKENS.manager1())).status).toBe(403);
  });

  it('staff access to the property meter routes is unchanged', async () => {
    const list = await call('GET', `/v1/properties/${P1}/meter-readings`, TOKENS.staff1());
    expect(list.status).toBe(200);
    expect(list.body.data).toHaveLength(3);
  });
});
