// Complaint access through the real guards and SQL on an in-memory Postgres:
// property teams keep their workflows, tenants only ever see or touch their own.
import type { AddressInfo } from 'net';
import express from 'express';
import jwt from 'jsonwebtoken';
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';

process.env.DATABASE_URL ??= 'postgres://test:test@127.0.0.1:1/test';
process.env.JWT_ACCESS_SECRET = 'complaints-access-test-secret';
process.env.JWT_REFRESH_SECRET ??= 'test';
process.env.RAZORPAY_KEY_ID ??= 'rzp_test_x';
process.env.RAZORPAY_KEY_SECRET ??= 'test';
process.env.RAZORPAY_WEBHOOK_SECRET ??= 'test';

const pg = vi.hoisted(() => ({ db: null as any }));

vi.mock('@config/db', () => ({
  query: async (sql: string, params?: unknown[]) =>
    (await pg.db.query(sql, params ?? [])).rows,
}));

vi.mock('@modules/notifications/notify', () => ({
  ensureLiveOpsSchema: async () => undefined,
  notifyPropertyOwners: async () => 0,
  createNotification: async () => true,
}));

const ORG_1 = '01000000-0000-4000-8000-000000000000';
const ORG_2 = '02000000-0000-4000-8000-000000000000';
const P1 = '11000000-0000-4000-8000-000000000001';
const P2 = '12000000-0000-4000-8000-000000000002';
const N1 = '21000000-0000-4000-8000-000000000001';
const N1B = '21000000-0000-4000-8000-00000000000b';
const N2 = '22000000-0000-4000-8000-000000000002';
const USER = {
  owner1: '31000000-0000-4000-8000-000000000001',
  owner2: '31000000-0000-4000-8000-000000000002',
  manager1: '31000000-0000-4000-8000-000000000003',
  staff1: '31000000-0000-4000-8000-000000000004',
  tenant2: '31000000-0000-4000-8000-000000000005',
  tenantA: '31000000-0000-4000-8000-000000000006',
  tenantB: '31000000-0000-4000-8000-000000000007',
};
const TEN_2 = '41000000-0000-4000-8000-000000000001';
const TEN_A = '41000000-0000-4000-8000-00000000000a';
const TEN_B = '41000000-0000-4000-8000-00000000000b';
const C = {
  ownerOld: '51000000-0000-4000-8000-000000000001',
  tenantA: '51000000-0000-4000-8000-00000000000a',
  tenantB: '51000000-0000-4000-8000-00000000000b',
  p2: '52000000-0000-4000-8000-000000000002',
};
const TENANT_B_PHONE = '9999900002';

const sign = (claims: Record<string, unknown>) =>
  jwt.sign(claims, process.env.JWT_ACCESS_SECRET!, { expiresIn: '5m' });
const tenantToken = (sub: string, tenancy: string, property: string) =>
  sign({ sub, ctxType: 'tenancy', ctxId: tenancy, ctxRole: 'tenant', ctxPropertyId: property });

const TOKENS = {
  owner1: () => sign({ sub: USER.owner1, ctxType: 'organization', ctxId: ORG_1, ctxRole: 'owner', ctxPropertyId: null }),
  owner2: () => sign({ sub: USER.owner2, ctxType: 'organization', ctxId: ORG_2, ctxRole: 'owner', ctxPropertyId: null }),
  manager1: () => sign({ sub: USER.manager1, ctxType: 'organization', ctxId: P1, ctxRole: 'manager', ctxPropertyId: P1 }),
  staff1: () => sign({ sub: USER.staff1, ctxType: 'organization', ctxId: P1, ctxRole: 'staff', ctxPropertyId: P1 }),
  // Manager token presented for a property they are not assigned to.
  manager1OnP2: () => sign({ sub: USER.manager1, ctxType: 'organization', ctxId: P2, ctxRole: 'manager', ctxPropertyId: P2 }),
  tenant2: () => tenantToken(USER.tenant2, TEN_2, P2),
  tenantA: () => tenantToken(USER.tenantA, TEN_A, P1),
  // Tenant A claiming tenant B's tenancy, or another property.
  tenantAWithBTenancy: () => tenantToken(USER.tenantA, TEN_B, P1),
  tenantAOnP2: () => tenantToken(USER.tenantA, TEN_A, P2),
};

let baseUrl = '';
let server: ReturnType<express.Express['listen']>;

beforeAll(async () => {
  const { PGlite } = await import('@electric-sql/pglite');
  pg.db = new PGlite();
  await pg.db.exec(`
    CREATE TYPE complaint_status AS ENUM ('open', 'assigned', 'in_progress', 'resolved', 'closed');
    CREATE TABLE properties (id uuid PRIMARY KEY, organization_id uuid);
    CREATE TABLE memberships (user_id uuid, organization_id uuid, role text);
    CREATE TABLE property_staff_assignments (user_id uuid, property_id uuid, role text, status text);
    CREATE TABLE users (id uuid PRIMARY KEY, phone text, name text);
    CREATE TABLE hierarchy_nodes (id uuid PRIMARY KEY, property_id uuid, name text);
    CREATE TABLE tenancies (id uuid PRIMARY KEY, property_id uuid, node_id uuid, user_id uuid,
      full_name text, status text, created_at timestamptz DEFAULT now());
    CREATE TABLE complaints (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), property_id uuid,
      node_id uuid, raised_by uuid, category text, description text,
      priority text DEFAULT 'medium', status complaint_status DEFAULT 'open',
      photo_urls text[], ticket_number text, resolution_note text, resolved_at timestamptz,
      created_at timestamptz DEFAULT now(), updated_at timestamptz DEFAULT now());
  `);
  await pg.db.query(`INSERT INTO properties VALUES ($1, $2), ($3, $4)`, [P1, ORG_1, P2, ORG_2]);
  await pg.db.query(`INSERT INTO memberships VALUES ($1, $2, 'owner'), ($3, $4, 'owner')`,
    [USER.owner1, ORG_1, USER.owner2, ORG_2]);
  await pg.db.query(
    `INSERT INTO property_staff_assignments VALUES ($1, $3, 'manager', 'active'), ($2, $3, 'staff', 'active')`,
    [USER.manager1, USER.staff1, P1],
  );
  for (const [key, id] of Object.entries(USER)) {
    await pg.db.query(`INSERT INTO users VALUES ($1, $2, $3)`, [
      id,
      key === 'tenantB' ? TENANT_B_PHONE : null,
      key === 'tenantB' ? 'Bina Private' : 'u',
    ]);
  }
  await pg.db.query(
    `INSERT INTO hierarchy_nodes VALUES ($1, $4, 'Room 101'), ($2, $4, 'Room 102'), ($3, $5, 'Room 201')`,
    [N1, N1B, N2, P1, P2],
  );
  // Tenants A and B share Room 101.
  await pg.db.query(
    `INSERT INTO tenancies (id, property_id, node_id, user_id, full_name, status, created_at) VALUES
       ($1, $4, $6, $8, 'Tenant Two', 'active', now()),
       ($2, $5, $7, $9, 'Asha Tenant', 'active', now() - interval '1 day'),
       ($3, $5, $7, $10, 'Bina Private', 'active', now())`,
    [TEN_2, TEN_A, TEN_B, P2, P1, N2, N1, USER.tenant2, USER.tenantA, USER.tenantB],
  );
  await pg.db.query(
    `INSERT INTO complaints (id, property_id, node_id, raised_by, category, description, status, created_at) VALUES
       ($1, $5, $7, $9, 'Plumbing', 'Older P1', 'resolved', '2026-10-01T10:00:00Z'),
       ($2, $5, $7, $10, 'Electricity', 'Tenant A fan', 'open', '2026-10-11T10:00:00Z'),
       ($3, $5, $7, $11, 'Other', 'Tenant B private matter', 'open', '2026-10-12T10:00:00Z'),
       ($4, $6, $8, $12, 'Cleaning', 'Only P2', 'open', '2026-10-13T10:00:00Z')`,
    [C.ownerOld, C.tenantA, C.tenantB, C.p2, P1, P2, N1, N2,
      USER.owner1, USER.tenantA, USER.tenantB, USER.tenant2],
  );

  const { authGuard, requireContext, requirePropertyAccess, requireRole } = await import(
    '../../shared/middleware/auth-guard.js'
  );
  const { complaintRouter } = await import('./complaint.routes.js');
  const { ComplaintController } = await import('./complaint.controller.js');
  const { errorHandler } = await import('../../shared/middleware/error-handler.js');
  const tenantController = new ComplaintController();

  const app = express();
  app.use(express.json());
  // Same chain as properties.routes.ts (requireWritableProperty only gates frozen properties).
  app.use(
    '/v1/properties/:propertyId/complaints',
    authGuard,
    requireContext,
    requirePropertyAccess,
    complaintRouter,
  );
  // Same chain as tenant-portal.routes.ts.
  const portal = express.Router();
  portal.use(authGuard, requireContext, requireRole('tenant'));
  portal.get('/complaints', tenantController.myComplaints);
  portal.post('/complaints', tenantController.createMine);
  app.use('/v1/tenant-portal', portal);
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

async function call(method: string, path: string, tok: string, body?: unknown) {
  const res = await fetch(`${baseUrl}${path}`, {
    method,
    headers: {
      authorization: `Bearer ${tok}`,
      ...(body ? { 'content-type': 'application/json' } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
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

const list = (propertyId: string, tok: string) =>
  call('GET', `/v1/properties/${propertyId}/complaints`, tok);
const patch = (propertyId: string, complaintId: string, tok: string, status = 'in_progress') =>
  call('PATCH', `/v1/properties/${propertyId}/complaints/${complaintId}`, tok, { status });
const statusOf = async (id: string) =>
  (await pg.db.query(`SELECT status FROM complaints WHERE id = $1`, [id])).rows[0]?.status;
const countByDescription = async (description: string) =>
  Number((await pg.db.query(`SELECT COUNT(*)::int AS n FROM complaints WHERE description = $1`, [description])).rows[0].n);

describe('property complaint listing', () => {
  it("owners see every complaint of their property, newest first, with reporter details", async () => {
    const res = await list(P1, TOKENS.owner1());
    expect(res.status).toBe(200);
    expect(res.body.data.map((c: any) => c.description)).toEqual([
      'Tenant B private matter',
      'Tenant A fan',
      'Older P1',
    ]);
    expect(res.body.data[0].node_name).toBe('Room 101');
    expect(res.body.data[0].raised_by_phone).toBe(TENANT_B_PHONE);
  });

  it("another organization's property is refused", async () => {
    expect((await list(P2, TOKENS.owner1())).status).toBe(403);
    expect((await list(P1, TOKENS.owner2())).status).toBe(403);
  });

  it('managers and staff reach only their assigned property', async () => {
    const manager = await list(P1, TOKENS.manager1());
    expect(manager.status).toBe(200);
    expect(manager.body.data).toHaveLength(3);
    expect((await list(P1, TOKENS.staff1())).body.data).toHaveLength(3);
    expect((await list(P2, TOKENS.manager1())).status).toBe(403);
    expect((await list(P2, TOKENS.manager1OnP2())).status).toBe(403);
  });

  it("a tenant only gets their own complaints, never a roommate's", async () => {
    const res = await list(P1, TOKENS.tenantA());
    expect(res.status).toBe(200);
    expect(res.body.data.map((c: any) => c.id)).toEqual([C.tenantA]);
    for (const row of res.body.data) {
      expect(row).not.toHaveProperty('raised_by_phone');
      expect(row).not.toHaveProperty('raised_by_name');
      expect(row).not.toHaveProperty('tenant_name');
    }
    expect(res.text).not.toContain('Tenant B private matter');
    expect(res.text).not.toContain(TENANT_B_PHONE);
    expect(res.text).not.toContain('Bina Private');
  });

  it("a tenant cannot read another property's complaints", async () => {
    expect((await list(P1, TOKENS.tenant2())).status).toBe(403);
  });

  it('forged tenant tokens are refused', async () => {
    expect((await list(P1, TOKENS.tenantAWithBTenancy())).status).toBe(403);
    expect((await list(P2, TOKENS.tenantAOnP2())).status).toBe(403);
  });

  it('there is no per-complaint read endpoint to open a private complaint', async () => {
    const res = await call('GET', `/v1/properties/${P1}/complaints/${C.tenantB}`, TOKENS.tenantA());
    expect(res.status).toBe(404);
    expect(res.text).not.toContain('Tenant B private matter');
  });
});

describe('complaint status updates', () => {
  it("tenants cannot change any complaint, including a roommate's or their own", async () => {
    expect((await patch(P1, C.tenantB, TOKENS.tenantA(), 'closed')).status).toBe(403);
    expect((await patch(P1, C.tenantA, TOKENS.tenantA(), 'closed')).status).toBe(403);
    expect(await statusOf(C.tenantB)).toBe('open');
    expect(await statusOf(C.tenantA)).toBe('open');
  });

  it("a complaint id from another property is not reachable through this property's URL", async () => {
    expect((await patch(P1, C.p2, TOKENS.owner1(), 'closed')).status).toBe(404);
    expect((await patch(P1, C.p2, TOKENS.manager1(), 'closed')).status).toBe(404);
    expect((await patch(P2, C.tenantB, TOKENS.owner2(), 'closed')).status).toBe(404);
    expect(await statusOf(C.p2)).toBe('open');
    expect(await statusOf(C.tenantB)).toBe('open');
  });

  it('owners, managers and staff keep updating complaints of their property', async () => {
    const staff = await patch(P1, C.tenantB, TOKENS.staff1(), 'in_progress');
    expect(staff.status).toBe(200);
    expect(staff.body.data.status).toBe('in_progress');
    expect((await patch(P1, C.tenantB, TOKENS.manager1(), 'resolved')).status).toBe(200);
    expect((await patch(P1, C.tenantB, TOKENS.owner1(), 'closed')).status).toBe(200);
    expect(await statusOf(C.tenantB)).toBe('closed');
    expect((await patch(P2, C.p2, TOKENS.manager1OnP2(), 'closed')).status).toBe(403);
  });
});

describe('before migration 027 is applied', () => {
  it('comment and assignment endpoints report the feature as unavailable', async () => {
    const path = `/v1/properties/${P1}/complaints`;
    const unavailable = [
      await call('GET', `${path}/assignees`, TOKENS.owner1()),
      await call('GET', `${path}/${C.tenantA}/comments`, TOKENS.owner1()),
      await call('POST', `${path}/${C.tenantA}/comments`, TOKENS.manager1(), { body: 'hi' }),
      await call('GET', `${path}/${C.tenantA}/comments`, TOKENS.tenantA()),
      await call('PUT', `${path}/${C.tenantA}/assignment`, TOKENS.owner1(), {
        assigneeUserId: USER.staff1,
      }),
    ];
    for (const res of unavailable) {
      expect(res.status).toBe(503);
      expect(res.body.error).toBe('This feature is not available yet.');
    }
  });

  it('role checks still apply before availability', async () => {
    const path = `/v1/properties/${P1}/complaints`;
    expect((await call('GET', `${path}/assignees`, TOKENS.tenantA())).status).toBe(403);
    expect(
      (await call('PUT', `${path}/${C.tenantA}/assignment`, TOKENS.staff1(), { assigneeUserId: null }))
        .status,
    ).toBe(403);
  });

  it('complaint lists carry no assignment fields', async () => {
    const team = await list(P1, TOKENS.owner1());
    expect(team.body.data[0]).not.toHaveProperty('assignee_name');
    const tenant = await list(P1, TOKENS.tenantA());
    expect(tenant.body.data[0]).not.toHaveProperty('is_assigned');
  });
});

describe('raising complaints', () => {
  const raise = (propertyId: string, tok: string, nodeId: string, description: string) =>
    call('POST', `/v1/properties/${propertyId}/complaints`, tok, {
      nodeId,
      category: 'Other',
      description,
    });
  const raiseMine = (tok: string, body: Record<string, unknown>) =>
    call('POST', '/v1/tenant-portal/complaints', tok, { category: 'Other', ...body });

  it('the property team can raise for any unit of their property, not another property', async () => {
    expect((await raise(P1, TOKENS.manager1(), N1B, 'Team raised')).status).toBe(201);
    expect((await raise(P1, TOKENS.manager1(), N2, 'Cross-property unit')).status).toBe(400);
    expect(await countByDescription('Cross-property unit')).toBe(0);
  });

  it("tenants can only raise for their own unit on the property route", async () => {
    expect((await raise(P1, TOKENS.tenantA(), N1, 'Own unit via property')).status).toBe(201);
    expect((await raise(P1, TOKENS.tenantA(), N1B, 'Someone else unit')).status).toBe(403);
    expect((await raise(P2, TOKENS.tenantA(), N2, 'Other property')).status).toBe(403);
    expect(await countByDescription('Someone else unit')).toBe(0);
    expect(await countByDescription('Other property')).toBe(0);
  });

  it('the tenant portal uses the verified tenancy and rejects mismatched client ids', async () => {
    const spoofed = await raiseMine(TOKENS.tenantA(), {
      propertyId: P2,
      nodeId: N2,
      description: 'Spoofed placement',
    });
    expect(spoofed.status).toBe(403);
    expect(await countByDescription('Spoofed placement')).toBe(0);

    const otherRoom = await raiseMine(TOKENS.tenantA(), {
      propertyId: P1,
      nodeId: N1B,
      description: 'Spoofed room',
    });
    expect(otherRoom.status).toBe(403);

    const matching = await raiseMine(TOKENS.tenantA(), {
      propertyId: P1,
      nodeId: N1,
      description: 'Portal own unit',
    });
    expect(matching.status).toBe(201);
    expect(matching.body.data).toMatchObject({ property_id: P1, node_id: N1, raised_by: USER.tenantA });

    const derived = await raiseMine(TOKENS.tenantA(), { description: 'Portal derived unit' });
    expect(derived.status).toBe(201);
    expect(derived.body.data).toMatchObject({ property_id: P1, node_id: N1 });

    expect((await raiseMine(TOKENS.tenantAWithBTenancy(), { description: 'Forged' })).status).toBe(403);
  });

  it("a tenant's own list never includes complaints raised by others", async () => {
    const res = await call('GET', '/v1/tenant-portal/complaints', TOKENS.tenantA());
    expect(res.status).toBe(200);
    expect(res.body.data.every((c: any) => c.raised_by === USER.tenantA)).toBe(true);
    expect(res.text).not.toContain('Tenant B private matter');
    expect(res.text).not.toContain('Team raised');
  });
});
