// Complaint comments and assignment through the real guards, SQL and migration 027
// on an in-memory Postgres: the team works internally, tenants only ever see
// what was shared with them and never who was assigned.
import { readFileSync } from 'fs';
import path from 'path';
import type { AddressInfo } from 'net';
import express from 'express';
import jwt from 'jsonwebtoken';
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';

process.env.DATABASE_URL ??= 'postgres://test:test@127.0.0.1:1/test';
process.env.JWT_ACCESS_SECRET = 'complaint-comments-test-secret';
process.env.JWT_REFRESH_SECRET ??= 'test';
process.env.RAZORPAY_KEY_ID ??= 'rzp_test_x';
process.env.RAZORPAY_KEY_SECRET ??= 'test';
process.env.RAZORPAY_WEBHOOK_SECRET ??= 'test';

const pg = vi.hoisted(() => ({ db: null as any }));
const notify = vi.hoisted(() => ({ createNotification: vi.fn(async () => true) }));

vi.mock('@config/db', () => ({
  query: async (sql: string, params?: unknown[]) =>
    (await pg.db.query(sql, params ?? [])).rows,
}));

vi.mock('@modules/notifications/notify', () => ({
  ensureLiveOpsSchema: async () => undefined,
  notifyPropertyOwners: async () => 0,
  createNotification: notify.createNotification,
}));

const ORG_1 = '01000000-0000-4000-8000-000000000000';
const ORG_2 = '02000000-0000-4000-8000-000000000000';
const P1 = '11000000-0000-4000-8000-000000000001';
const P2 = '12000000-0000-4000-8000-000000000002';
// A second property of the same organisation as P1.
const P3 = '13000000-0000-4000-8000-000000000003';
const N1 = '21000000-0000-4000-8000-000000000001';
const N2 = '22000000-0000-4000-8000-000000000002';
const USER = {
  owner1: '31000000-0000-4000-8000-000000000001',
  admin1: '31000000-0000-4000-8000-000000000002',
  owner2: '31000000-0000-4000-8000-000000000003',
  manager1: '31000000-0000-4000-8000-000000000004',
  staff1: '31000000-0000-4000-8000-000000000005',
  staffP2: '31000000-0000-4000-8000-000000000006',
  staffP3: '31000000-0000-4000-8000-000000000007',
  pendingStaff: '31000000-0000-4000-8000-000000000008',
  removedStaff: '31000000-0000-4000-8000-000000000009',
  tenantA: '31000000-0000-4000-8000-00000000000a',
  tenantB: '31000000-0000-4000-8000-00000000000b',
  tenant2: '31000000-0000-4000-8000-00000000000c',
};
const NAME: Record<keyof typeof USER, string> = {
  owner1: 'Olivia Owner',
  admin1: 'Adam Admin',
  owner2: 'Other Owner',
  manager1: 'Maya Manager',
  staff1: 'Sam Staff',
  staffP2: 'Paul OtherProperty',
  staffP3: 'Priya SisterProperty',
  pendingStaff: 'Pending Person',
  removedStaff: 'Rita Removed',
  tenantA: 'Asha Tenant',
  tenantB: 'Bina Private',
  tenant2: 'Tenant Two',
};
const PHONE_PREFIX = '98765';
const TEN_A = '41000000-0000-4000-8000-00000000000a';
const TEN_B = '41000000-0000-4000-8000-00000000000b';
const TEN_2 = '41000000-0000-4000-8000-00000000000c';
const C = {
  tenantA: '51000000-0000-4000-8000-00000000000a',
  tenantB: '51000000-0000-4000-8000-00000000000b',
  p2: '52000000-0000-4000-8000-000000000002',
};

const sign = (claims: Record<string, unknown>) =>
  jwt.sign(claims, process.env.JWT_ACCESS_SECRET!, { expiresIn: '5m' });
const tenantToken = (sub: string, tenancy: string, property: string) =>
  sign({ sub, ctxType: 'tenancy', ctxId: tenancy, ctxRole: 'tenant', ctxPropertyId: property });
const orgToken = (sub: string, org: string, role: string) =>
  sign({ sub, ctxType: 'organization', ctxId: org, ctxRole: role, ctxPropertyId: null });
const propToken = (sub: string, property: string, role: string) =>
  sign({ sub, ctxType: 'organization', ctxId: property, ctxRole: role, ctxPropertyId: property });

const TOKENS = {
  owner1: () => orgToken(USER.owner1, ORG_1, 'owner'),
  admin1: () => orgToken(USER.admin1, ORG_1, 'admin'),
  owner2: () => orgToken(USER.owner2, ORG_2, 'owner'),
  manager1: () => propToken(USER.manager1, P1, 'manager'),
  staff1: () => propToken(USER.staff1, P1, 'staff'),
  staffP2: () => propToken(USER.staffP2, P2, 'staff'),
  tenantA: () => tenantToken(USER.tenantA, TEN_A, P1),
  tenantB: () => tenantToken(USER.tenantB, TEN_B, P1),
  tenant2: () => tenantToken(USER.tenant2, TEN_2, P2),
};

const MIGRATION_027 = readFileSync(
  path.join(__dirname, '../../db/migrations/027_complaint_comments_assignment.sql'),
  'utf8',
);

let baseUrl = '';
let server: ReturnType<express.Express['listen']>;

beforeAll(async () => {
  const { PGlite } = await import('@electric-sql/pglite');
  pg.db = new PGlite();
  await pg.db.exec(`
    CREATE TYPE complaint_status AS ENUM ('open', 'assigned', 'in_progress', 'resolved', 'closed');
    CREATE TABLE properties (id uuid PRIMARY KEY, organization_id uuid);
    CREATE TABLE memberships (user_id uuid, organization_id uuid, role text);
    CREATE TABLE property_staff_assignments (id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id uuid, property_id uuid, role text, status text, created_at timestamptz DEFAULT now());
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
  await pg.db.exec(MIGRATION_027);

  await pg.db.query(`INSERT INTO properties VALUES ($1, $2), ($3, $4), ($5, $2)`, [
    P1, ORG_1, P2, ORG_2, P3,
  ]);
  await pg.db.query(
    `INSERT INTO memberships VALUES ($1, $4, 'owner'), ($2, $4, 'admin'), ($3, $5, 'owner')`,
    [USER.owner1, USER.admin1, USER.owner2, ORG_1, ORG_2],
  );
  await pg.db.query(
    `INSERT INTO property_staff_assignments (user_id, property_id, role, status) VALUES
       ($1, $7, 'manager', 'active'),
       ($2, $7, 'staff', 'active'),
       ($3, $8, 'staff', 'active'),
       ($4, $9, 'staff', 'active'),
       ($5, $7, 'staff', 'pending'),
       ($6, $7, 'staff', 'active')`,
    [USER.manager1, USER.staff1, USER.staffP2, USER.staffP3, USER.pendingStaff,
      USER.removedStaff, P1, P2, P3],
  );
  let i = 0;
  for (const [key, id] of Object.entries(USER)) {
    i += 1;
    await pg.db.query(`INSERT INTO users VALUES ($1, $2, $3)`, [
      id,
      `${PHONE_PREFIX}${String(i).padStart(5, '0')}`,
      NAME[key as keyof typeof USER],
    ]);
  }
  await pg.db.query(
    `INSERT INTO hierarchy_nodes VALUES ($1, $3, 'Room 101'), ($2, $4, 'Room 201')`,
    [N1, N2, P1, P2],
  );
  await pg.db.query(
    `INSERT INTO tenancies (id, property_id, node_id, user_id, full_name, status) VALUES
       ($1, $4, $6, $7, 'Asha Tenant', 'active'),
       ($2, $4, $6, $8, 'Bina Private', 'active'),
       ($3, $5, $10, $9, 'Tenant Two', 'active')`,
    [TEN_A, TEN_B, TEN_2, P1, P2, N1, USER.tenantA, USER.tenantB, USER.tenant2, N2],
  );
  await pg.db.query(
    `INSERT INTO complaints (id, property_id, node_id, raised_by, category, description, created_at) VALUES
       ($1, $4, $6, $8, 'Electricity', 'Tenant A fan', '2026-10-11T10:00:00Z'),
       ($2, $4, $6, $9, 'Other', 'Tenant B private matter', '2026-10-12T10:00:00Z'),
       ($3, $5, $7, $10, 'Cleaning', 'Only P2', '2026-10-13T10:00:00Z')`,
    [C.tenantA, C.tenantB, C.p2, P1, P2, N1, N2, USER.tenantA, USER.tenantB, USER.tenant2],
  );

  const { authGuard, requireContext, requirePropertyAccess, requireRole } = await import(
    '../../shared/middleware/auth-guard.js'
  );
  const { complaintRouter } = await import('./complaint.routes.js');
  const { ComplaintController } = await import('./complaint.controller.js');
  const { staffRouter } = await import('../staff/staff.routes.js');
  const { errorHandler } = await import('../../shared/middleware/error-handler.js');
  const tenantController = new ComplaintController();

  const app = express();
  app.use(express.json());
  const propertyChain = [authGuard, requireContext, requirePropertyAccess];
  app.use('/v1/properties/:propertyId/complaints', ...propertyChain, complaintRouter);
  app.use('/v1/properties/:propertyId/staff', ...propertyChain, staffRouter);
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

beforeEach(() => {
  notify.createNotification.mockClear();
});

async function call(method: string, urlPath: string, tok: string, body?: unknown) {
  const res = await fetch(`${baseUrl}${urlPath}`, {
    method,
    headers: {
      authorization: `Bearer ${tok}`,
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

const base = (propertyId: string) => `/v1/properties/${propertyId}/complaints`;
const assign = (propertyId: string, complaintId: string, tok: string, assigneeUserId: unknown) =>
  call('PUT', `${base(propertyId)}/${complaintId}/assignment`, tok, { assigneeUserId });
const comments = (propertyId: string, complaintId: string, tok: string) =>
  call('GET', `${base(propertyId)}/${complaintId}/comments`, tok);
const comment = (
  propertyId: string,
  complaintId: string,
  tok: string,
  body: Record<string, unknown>,
) => call('POST', `${base(propertyId)}/${complaintId}/comments`, tok, body);
const assignedTo = async (id: string) =>
  (await pg.db.query(`SELECT assigned_to FROM complaints WHERE id = $1`, [id])).rows[0]
    ?.assigned_to ?? null;
const eventCount = async (id: string, kind: string) =>
  Number(
    (
      await pg.db.query(
        `SELECT COUNT(*)::int AS n FROM complaint_comments WHERE complaint_id = $1 AND kind = $2`,
        [id, kind],
      )
    ).rows[0].n,
  );
const commentCount = async () =>
  Number(
    (await pg.db.query(`SELECT COUNT(*)::int AS n FROM complaint_comments WHERE kind = 'comment'`))
      .rows[0].n,
  );

const ASSIGNMENT_KEYS = ['assigned_to', 'assigned_by', 'assigned_at', 'assignee_name', 'assignee_role', 'assignee_active'];

describe('assignee list', () => {
  it('lists the active property team and org owners/admins with id, name and role only', async () => {
    const res = await call('GET', `${base(P1)}/assignees`, TOKENS.owner1());
    expect(res.status).toBe(200);
    expect(res.body.data).toEqual([
      { user_id: USER.owner1, name: NAME.owner1, role: 'owner' },
      { user_id: USER.admin1, name: NAME.admin1, role: 'admin' },
      { user_id: USER.manager1, name: NAME.manager1, role: 'manager' },
      { user_id: USER.removedStaff, name: NAME.removedStaff, role: 'staff' },
      { user_id: USER.staff1, name: NAME.staff1, role: 'staff' },
    ]);
    expect(res.text).not.toContain(PHONE_PREFIX);
    expect(res.text).not.toContain(NAME.pendingStaff);
    expect(res.text).not.toContain(NAME.staffP2);
    expect(res.text).not.toContain(NAME.staffP3);
    expect(res.text).not.toContain(NAME.owner2);
  });

  it('is available to managers but not to staff or tenants', async () => {
    expect((await call('GET', `${base(P1)}/assignees`, TOKENS.manager1())).status).toBe(200);
    expect((await call('GET', `${base(P1)}/assignees`, TOKENS.admin1())).status).toBe(200);
    expect((await call('GET', `${base(P1)}/assignees`, TOKENS.staff1())).status).toBe(403);
    const tenant = await call('GET', `${base(P1)}/assignees`, TOKENS.tenantA());
    expect(tenant.status).toBe(403);
    expect(tenant.text).not.toContain(NAME.staff1);
  });

  it("another organisation's owner cannot list this property's team", async () => {
    expect((await call('GET', `${base(P1)}/assignees`, TOKENS.owner2())).status).toBe(403);
  });
});

describe('assigning complaints', () => {
  it('staff and tenants cannot assign, and nothing changes', async () => {
    expect((await assign(P1, C.tenantA, TOKENS.staff1(), USER.staff1)).status).toBe(403);
    expect((await assign(P1, C.tenantA, TOKENS.tenantA(), USER.staff1)).status).toBe(403);
    expect((await assign(P1, C.tenantB, TOKENS.tenantA(), null)).status).toBe(403);
    expect(await assignedTo(C.tenantA)).toBeNull();
    expect(await eventCount(C.tenantA, 'assigned')).toBe(0);
  });

  it('rejects assignees outside the property team without changing the complaint', async () => {
    const outsiders = [
      USER.staffP2, // staff of another organisation's property
      USER.staffP3, // staff of a sister property in the same organisation
      USER.owner2, // owner of another organisation
      USER.pendingStaff, // invitation not accepted
      USER.tenantA, // a tenant
      '39999999-0000-4000-8000-000000000000', // nobody
    ];
    for (const id of outsiders) {
      const res = await assign(P1, C.tenantA, TOKENS.owner1(), id);
      expect(res.status).toBe(422);
    }
    expect((await assign(P1, C.tenantA, TOKENS.owner1(), 'not-a-uuid')).status).toBe(400);
    expect((await assign(P1, C.tenantA, TOKENS.owner1(), undefined)).status).toBe(400);
    expect(await assignedTo(C.tenantA)).toBeNull();
    expect(await eventCount(C.tenantA, 'assigned')).toBe(0);
    expect(notify.createNotification).not.toHaveBeenCalled();
  });

  it('owners assign to active staff, record an internal event and notify the assignee', async () => {
    const res = await assign(P1, C.tenantA, TOKENS.owner1(), USER.staff1);
    expect(res.status).toBe(200);
    expect(res.body.data).toMatchObject({
      id: C.tenantA,
      assigned_to: USER.staff1,
      assigned_by: USER.owner1,
      assignee_name: NAME.staff1,
      assignee_role: 'staff',
      assignee_active: true,
      status: 'open',
    });
    expect(await eventCount(C.tenantA, 'assigned')).toBe(1);
    expect(notify.createNotification).toHaveBeenCalledTimes(1);
    expect(notify.createNotification).toHaveBeenCalledWith(
      expect.objectContaining({ userId: USER.staff1, type: 'complaint_assigned', propertyId: P1 }),
    );
  });

  it('re-assigning the same person is a no-op', async () => {
    const res = await assign(P1, C.tenantA, TOKENS.owner1(), USER.staff1);
    expect(res.status).toBe(200);
    expect(await eventCount(C.tenantA, 'assigned')).toBe(1);
    expect(notify.createNotification).not.toHaveBeenCalled();
  });

  it('managers and admins can reassign, including to an org admin', async () => {
    const manager = await assign(P1, C.tenantA, TOKENS.manager1(), USER.admin1);
    expect(manager.status).toBe(200);
    expect(manager.body.data).toMatchObject({ assigned_to: USER.admin1, assignee_role: 'admin' });
    const admin = await assign(P1, C.tenantA, TOKENS.admin1(), USER.staff1);
    expect(admin.status).toBe(200);
    expect(admin.body.data.assignee_name).toBe(NAME.staff1);
    expect(await eventCount(C.tenantA, 'assigned')).toBe(3);
  });

  it('self-assignment does not notify yourself', async () => {
    const res = await assign(P1, C.tenantA, TOKENS.manager1(), USER.manager1);
    expect(res.status).toBe(200);
    expect(notify.createNotification).not.toHaveBeenCalled();
  });

  it('unassigning clears the assignee once and records it', async () => {
    const res = await assign(P1, C.tenantA, TOKENS.owner1(), null);
    expect(res.status).toBe(200);
    expect(res.body.data.assigned_to).toBeNull();
    expect(res.body.data.assignee_active).toBeNull();
    expect(await eventCount(C.tenantA, 'unassigned')).toBe(1);
    expect((await assign(P1, C.tenantA, TOKENS.owner1(), null)).status).toBe(200);
    expect(await eventCount(C.tenantA, 'unassigned')).toBe(1);
  });

  it('cross-property complaints are unreachable and other-property assignees are refused', async () => {
    expect((await assign(P1, C.p2, TOKENS.owner1(), USER.staff1)).status).toBe(404);
    expect((await assign(P2, C.tenantA, TOKENS.owner2(), USER.staffP2)).status).toBe(404);
    expect((await assign(P2, C.p2, TOKENS.owner2(), USER.staff1)).status).toBe(422);
    expect((await assign(P2, C.p2, TOKENS.owner1(), USER.staffP2)).status).toBe(403);
    expect(await assignedTo(C.p2)).toBeNull();
  });

  it('a removed member stays on the record, flagged inactive, until reassigned', async () => {
    expect((await assign(P1, C.tenantB, TOKENS.owner1(), USER.removedStaff)).status).toBe(200);
    await pg.db.query(`DELETE FROM property_staff_assignments WHERE user_id = $1`, [
      USER.removedStaff,
    ]);

    const list = await call('GET', base(P1), TOKENS.manager1());
    const row = list.body.data.find((c: any) => c.id === C.tenantB);
    expect(row).toMatchObject({
      assigned_to: USER.removedStaff,
      assignee_name: NAME.removedStaff,
      assignee_role: null,
      assignee_active: false,
    });
    expect((await call('GET', `${base(P1)}/assignees`, TOKENS.owner1())).text).not.toContain(
      NAME.removedStaff,
    );
    // They can no longer be picked again, but the complaint can be reassigned.
    expect((await assign(P1, C.tenantA, TOKENS.owner1(), USER.removedStaff)).status).toBe(422);
    const reassigned = await assign(P1, C.tenantB, TOKENS.owner1(), USER.staff1);
    expect(reassigned.status).toBe(200);
    expect(reassigned.body.data.assignee_active).toBe(true);
  });

  it('assignment does not touch status, photos or other complaint fields', async () => {
    const [row] = (
      await pg.db.query(`SELECT status, description, category FROM complaints WHERE id = $1`, [
        C.tenantB,
      ])
    ).rows;
    expect(row).toEqual({ status: 'open', description: 'Tenant B private matter', category: 'Other' });
  });
});

describe('comments', () => {
  it('team comments default to internal and can be shared with the tenant', async () => {
    const before = await commentCount();
    const unassigned = await comment(P1, C.tenantA, TOKENS.staff1(), { body: 'Not mine yet' });
    expect(unassigned.status).toBe(403);
    expect(await commentCount()).toBe(before);
    expect((await assign(P1, C.tenantA, TOKENS.owner1(), USER.staff1)).status).toBe(200);

    const internal = await comment(P1, C.tenantA, TOKENS.staff1(), { body: 'Checked wiring - internal' });
    expect(internal.status).toBe(201);
    expect(internal.body.data).toMatchObject({
      kind: 'comment',
      visibility: 'internal',
      author_role: 'staff',
      author_name: NAME.staff1,
      body: 'Checked wiring - internal',
    });
    const shared = await comment(P1, C.tenantA, TOKENS.manager1(), {
      body: 'Electrician visits tomorrow',
      visibility: 'tenant_visible',
    });
    expect(shared.status).toBe(201);
    expect(shared.body.data.visibility).toBe('tenant_visible');
  });

  it("a tenant's comment on their own complaint is always visible to them", async () => {
    const res = await comment(P1, C.tenantA, TOKENS.tenantA(), {
      body: 'Thanks, I will be home',
      visibility: 'internal',
    });
    expect(res.status).toBe(201);
    expect(res.body.data).toEqual({
      id: expect.any(String),
      complaint_id: C.tenantA,
      kind: 'comment',
      body: 'Thanks, I will be home',
      created_at: expect.any(String),
      author_role: 'tenant',
    });
    const [stored] = (
      await pg.db.query(`SELECT visibility FROM complaint_comments WHERE id = $1`, [res.body.data.id])
    ).rows;
    expect(stored.visibility).toBe('tenant_visible');
  });

  it('the team sees every entry in order, including internal notes and assignment events', async () => {
    const res = await comments(P1, C.tenantA, TOKENS.owner1());
    expect(res.status).toBe(200);
    const kinds = res.body.data.map((c: any) => c.kind);
    expect(kinds.filter((k: string) => k === 'assigned')).toHaveLength(5);
    expect(kinds).toContain('unassigned');
    expect(res.body.data.filter((c: any) => c.kind === 'comment').map((c: any) => c.body)).toEqual([
      'Checked wiring - internal',
      'Electrician visits tomorrow',
      'Thanks, I will be home',
    ]);
    const times = res.body.data.map((c: any) => Date.parse(c.created_at));
    expect([...times].sort((a, b) => a - b)).toEqual(times);
    expect(res.text).not.toContain(PHONE_PREFIX);
  });

  it('the tenant sees only shared comments, with team authors kept anonymous', async () => {
    const res = await comments(P1, C.tenantA, TOKENS.tenantA());
    expect(res.status).toBe(200);
    expect(res.body.data.map((c: any) => [c.author_role, c.body])).toEqual([
      ['team', 'Electrician visits tomorrow'],
      ['tenant', 'Thanks, I will be home'],
    ]);
    for (const row of res.body.data) {
      expect(Object.keys(row).sort()).toEqual(
        ['author_role', 'body', 'complaint_id', 'created_at', 'id', 'kind'],
      );
    }
    expect(res.text).not.toContain('internal');
    expect(res.text).not.toContain(NAME.manager1);
    expect(res.text).not.toContain(NAME.staff1);
    expect(res.text).not.toContain(USER.staff1);
    expect(res.text).not.toContain(USER.manager1);
    expect(res.text).not.toContain(PHONE_PREFIX);
  });

  it("a tenant cannot read or comment on a roommate's complaint", async () => {
    await comment(P1, C.tenantB, TOKENS.owner1(), { body: 'Bina secret', visibility: 'tenant_visible' });
    const read = await comments(P1, C.tenantB, TOKENS.tenantA());
    expect(read.status).toBe(403);
    expect(read.text).not.toContain('Bina secret');
    const before = await commentCount();
    expect((await comment(P1, C.tenantB, TOKENS.tenantA(), { body: 'Snooping' })).status).toBe(403);
    expect(await commentCount()).toBe(before);
    expect((await comments(P1, C.tenantB, TOKENS.tenantB())).status).toBe(200);
  });

  it('tenants of another property and cross-property ids are refused', async () => {
    expect((await comments(P1, C.tenantA, TOKENS.tenant2())).status).toBe(403);
    expect((await comments(P1, C.p2, TOKENS.owner1())).status).toBe(404);
    expect((await comment(P1, C.p2, TOKENS.manager1(), { body: 'Wrong property' })).status).toBe(404);
    expect((await comments(P1, C.tenantA, TOKENS.staffP2())).status).toBe(403);
    expect((await comments(P1, C.tenantA, TOKENS.owner2())).status).toBe(403);
    expect((await comments(P2, C.p2, TOKENS.tenant2())).body.data).toEqual([]);
  });

  it('rejects empty and over-long comments without storing anything', async () => {
    const before = await commentCount();
    expect((await comment(P1, C.tenantA, TOKENS.owner1(), { body: '' })).status).toBe(400);
    expect((await comment(P1, C.tenantA, TOKENS.owner1(), { body: '   ' })).status).toBe(400);
    expect((await comment(P1, C.tenantA, TOKENS.owner1(), { body: 'x'.repeat(2001) })).status).toBe(400);
    expect((await comment(P1, C.tenantA, TOKENS.owner1(), {})).status).toBe(400);
    expect(
      (await comment(P1, C.tenantA, TOKENS.owner1(), { body: 'ok', visibility: 'public' })).status,
    ).toBe(400);
    expect(await commentCount()).toBe(before);
    expect((await comment(P1, C.tenantA, TOKENS.owner1(), { body: 'x'.repeat(2000) })).status).toBe(201);
  });
});

describe('tenant complaint responses never reveal the assignee', () => {
  it('the property list gives tenants only an is_assigned flag', async () => {
    const res = await call('GET', base(P1), TOKENS.tenantB());
    expect(res.status).toBe(200);
    expect(res.body.data).toHaveLength(1);
    expect(res.body.data[0].is_assigned).toBe(true);
    for (const key of ASSIGNMENT_KEYS) expect(res.body.data[0]).not.toHaveProperty(key);
    expect(res.text).not.toContain(USER.staff1);
    expect(res.text).not.toContain(NAME.staff1);
  });

  it('the tenant portal list and create responses carry no assignee fields', async () => {
    const mine = await call('GET', '/v1/tenant-portal/complaints', TOKENS.tenantB());
    expect(mine.status).toBe(200);
    expect(mine.body.data[0].is_assigned).toBe(true);
    for (const key of ASSIGNMENT_KEYS) expect(mine.body.data[0]).not.toHaveProperty(key);
    expect(mine.text).not.toContain(USER.staff1);

    const created = await call('POST', '/v1/tenant-portal/complaints', TOKENS.tenantA(), {
      category: 'Other',
      description: 'New from portal',
    });
    expect(created.status).toBe(201);
    for (const key of ASSIGNMENT_KEYS) expect(created.body.data).not.toHaveProperty(key);
  });

  it('the team list still includes assignee details', async () => {
    const res = await call('GET', base(P1), TOKENS.staff1());
    const row = res.body.data.find((c: any) => c.id === C.tenantB);
    expect(row).toMatchObject({ assigned_to: USER.staff1, assignee_name: NAME.staff1 });
  });
});

describe('property staff list privacy', () => {
  const staffList = (propertyId: string, tok: string) =>
    call('GET', `/v1/properties/${propertyId}/staff`, tok);

  it('tenants cannot list the property team or their phone numbers', async () => {
    const res = await staffList(P1, TOKENS.tenantA());
    expect(res.status).toBe(403);
    expect(res.text).not.toContain(PHONE_PREFIX);
    expect(res.text).not.toContain(NAME.staff1);
  });

  it('staff cannot list the team or their phone numbers either', async () => {
    const res = await staffList(P1, TOKENS.staff1());
    expect(res.status).toBe(403);
    expect(res.text).not.toContain(PHONE_PREFIX);
    expect(res.text).not.toContain(NAME.manager1);
  });

  it('owners, admins and managers still can', async () => {
    for (const tok of [TOKENS.owner1(), TOKENS.admin1(), TOKENS.manager1()]) {
      const res = await staffList(P1, tok);
      expect(res.status).toBe(200);
      expect(res.body.data.some((r: any) => r.user_id === USER.staff1)).toBe(true);
    }
    expect((await staffList(P1, TOKENS.owner2())).status).toBe(403);
  });
});

describe('staff complaint updates', () => {
  const patch = (complaintId: string, tok: string, body: Record<string, unknown>) =>
    call('PATCH', `${base(P1)}/${complaintId}`, tok, body);
  const statusOf = async (id: string) =>
    (await pg.db.query(`SELECT status FROM complaints WHERE id = $1`, [id])).rows[0].status;
  const UNASSIGNED = '51000000-0000-4000-8000-0000000000ff';

  beforeAll(async () => {
    await pg.db.query(
      `INSERT INTO complaints (id, property_id, node_id, raised_by, category, description)
       VALUES ($1, $2, $3, $4, 'Plumbing', 'Nobody assigned yet')`,
      [UNASSIGNED, P1, N1, USER.tenantA],
    );
  });

  it('staff update the status of complaints assigned to them', async () => {
    expect(await assignedTo(C.tenantB)).toBe(USER.staff1);
    const res = await patch(C.tenantB, TOKENS.staff1(), { status: 'in_progress' });
    expect(res.status).toBe(200);
    expect(await statusOf(C.tenantB)).toBe('in_progress');
  });

  it('staff cannot update or comment on complaints assigned to nobody or someone else', async () => {
    const before = await commentCount();
    expect((await patch(UNASSIGNED, TOKENS.staff1(), { status: 'resolved' })).status).toBe(403);
    expect(
      (await comment(P1, UNASSIGNED, TOKENS.staff1(), { body: 'Done' })).status,
    ).toBe(403);
    expect((await assign(P1, UNASSIGNED, TOKENS.manager1(), USER.removedStaff)).status).toBe(422);
    expect((await assign(P1, UNASSIGNED, TOKENS.manager1(), USER.manager1)).status).toBe(200);
    expect((await patch(UNASSIGNED, TOKENS.staff1(), { status: 'resolved' })).status).toBe(403);
    expect(await statusOf(UNASSIGNED)).toBe('open');
    expect(await commentCount()).toBe(before);
  });

  it('staff cannot reassign a complaint to themselves through the update body', async () => {
    const res = await patch(UNASSIGNED, TOKENS.staff1(), {
      status: 'in_progress',
      assigned_to: USER.staff1,
      assigneeUserId: USER.staff1,
    });
    expect(res.status).toBe(403);
    expect(await assignedTo(UNASSIGNED)).toBe(USER.manager1);
  });

  it('staff list only complaints assigned to them or to nobody', async () => {
    const OPEN = '51000000-0000-4000-8000-0000000000fe';
    await pg.db.query(
      `INSERT INTO complaints (id, property_id, node_id, raised_by, category, description)
       VALUES ($1, $2, $3, $4, 'Cleaning', 'Waiting for someone')`,
      [OPEN, P1, N1, USER.tenantB],
    );
    const res = await call('GET', base(P1), TOKENS.staff1());
    expect(res.status).toBe(200);
    const byId = new Map(res.body.data.map((c: any) => [c.id, c]));
    expect(byId.has(UNASSIGNED)).toBe(false); // assigned to the manager
    expect(byId.get(C.tenantB)).toMatchObject({
      assigned_to: USER.staff1,
      raised_by_phone: expect.stringMatching(new RegExp(`^${PHONE_PREFIX}`)),
    });
    expect(byId.get(OPEN)).toMatchObject({ assigned_to: null, raised_by_name: NAME.tenantB });
    expect(byId.get(OPEN)).not.toHaveProperty('raised_by_phone');

    const manager = await call('GET', base(P1), TOKENS.manager1());
    expect(manager.body.data.map((c: any) => c.id)).toEqual(
      expect.arrayContaining([UNASSIGNED, C.tenantB, OPEN]),
    );
    expect(manager.body.data.every((c: any) => typeof c.raised_by_phone === 'string')).toBe(true);
  });

  it("staff cannot read the activity of someone else's complaint", async () => {
    const res = await comments(P1, UNASSIGNED, TOKENS.staff1());
    expect(res.status).toBe(403);
    expect((await comments(P1, C.tenantB, TOKENS.staff1())).status).toBe(200);
    expect((await comments(P1, UNASSIGNED, TOKENS.manager1())).status).toBe(200);
  });

  it('managers update any complaint of their property, and staff of another property none', async () => {
    expect((await patch(UNASSIGNED, TOKENS.manager1(), { status: 'in_progress' })).status).toBe(200);
    expect((await patch(C.tenantB, TOKENS.staffP2(), { status: 'closed' })).status).toBe(403);
    expect(await statusOf(C.tenantB)).toBe('in_progress');
  });
});

// The API suite above runs as PGlite's superuser, which skips RLS entirely. Here
// a separate database is set up the way Supabase is: a non-superuser owner
// without BYPASSRLS runs the real migration, anon/authenticated receive
// default grants on new public tables, and other roles are checked against it.
describe('migration 027 row-level security', () => {
  let rls: any;
  const OWNER_P = '61000000-0000-4000-8000-000000000001';
  const OWNER_U = '62000000-0000-4000-8000-000000000001';
  const OWNER_C = '63000000-0000-4000-8000-000000000001';

  /** Runs [sql] as [role] in a transaction that is rolled back on failure. */
  const asRole = (role: string, sql: string, params: unknown[] = []) =>
    rls.transaction(async (tx: any) => {
      await tx.query(`SET LOCAL ROLE ${role}`);
      return (await tx.query(sql, params)).rows;
    });

  const insertComment = (role: string, body: string) =>
    asRole(
      role,
      `INSERT INTO complaint_comments
         (complaint_id, property_id, author_user_id, author_role, visibility, body)
       VALUES ($1, $2, $3, 'staff', 'internal', $4) RETURNING id`,
      [OWNER_C, OWNER_P, OWNER_U, body],
    );

  beforeAll(async () => {
    const { PGlite } = await import('@electric-sql/pglite');
    rls = new PGlite();
    await rls.exec(`
      CREATE ROLE app_owner NOLOGIN NOSUPERUSER NOBYPASSRLS;
      CREATE ROLE anon NOLOGIN NOSUPERUSER NOBYPASSRLS;
      CREATE ROLE authenticated NOLOGIN NOSUPERUSER NOBYPASSRLS;
      CREATE ROLE other_app NOLOGIN NOSUPERUSER NOBYPASSRLS;
      CREATE ROLE bypass_app NOLOGIN NOSUPERUSER BYPASSRLS;
      GRANT USAGE, CREATE ON SCHEMA public TO app_owner;
      GRANT USAGE ON SCHEMA public TO anon, authenticated, other_app, bypass_app;
      ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA public
        GRANT ALL ON TABLES TO anon, authenticated;
    `);
    await rls.exec(`
      SET ROLE app_owner;
      CREATE TABLE users (id uuid PRIMARY KEY);
      CREATE TABLE properties (id uuid PRIMARY KEY);
      CREATE TABLE complaints (id uuid PRIMARY KEY, property_id uuid);
      CREATE TABLE control_no_rls (n int);
      INSERT INTO control_no_rls VALUES (1);
      GRANT SELECT ON control_no_rls TO other_app;
    `);
    await rls.exec(MIGRATION_027);
    await rls.query(`INSERT INTO users VALUES ($1)`, [OWNER_U]);
    await rls.query(`INSERT INTO properties VALUES ($1)`, [OWNER_P]);
    await rls.query(`INSERT INTO complaints VALUES ($1, $2)`, [OWNER_C, OWNER_P]);
    await rls.query(
      `INSERT INTO complaint_comments
         (complaint_id, property_id, author_user_id, author_role, visibility, body)
       VALUES ($1, $2, $3, 'staff', 'internal', 'Internal note')`,
      [OWNER_C, OWNER_P, OWNER_U],
    );
    // A non-API role that has table grants but neither owns the table nor bypasses RLS.
    await rls.exec(`
      GRANT SELECT, INSERT, UPDATE, DELETE ON complaint_comments TO other_app, bypass_app;
      RESET ROLE;
    `);
  }, 60_000);

  afterAll(async () => {
    await rls?.close();
  });

  it('the simulation is real: SET ROLE takes effect and grants are honoured', async () => {
    expect((await asRole('other_app', 'SELECT current_user AS u'))[0].u).toBe('other_app');
    expect(await asRole('other_app', 'SELECT n FROM control_no_rls')).toEqual([{ n: 1 }]);
    // Supabase-style default grants reached the other new tables.
    expect(await asRole('anon', 'SELECT id FROM complaints')).toEqual([{ id: OWNER_C }]);
    const [owner] = (
      await rls.query(`SELECT rolsuper, rolbypassrls FROM pg_roles WHERE rolname = 'app_owner'`)
    ).rows;
    expect(owner).toEqual({ rolsuper: false, rolbypassrls: false });
  });

  it('enables RLS without forcing it, owned by the migrating role', async () => {
    const [row] = (
      await rls.query(
        `SELECT relrowsecurity, relforcerowsecurity, pg_get_userbyid(relowner) AS owner
         FROM pg_class WHERE oid = 'public.complaint_comments'::regclass`,
      )
    ).rows;
    expect(row).toEqual({ relrowsecurity: true, relforcerowsecurity: false, owner: 'app_owner' });
  });

  it('creates no policies', async () => {
    const { rows } = await rls.query(
      `SELECT policyname FROM pg_policies
       WHERE schemaname = 'public' AND tablename = 'complaint_comments'`,
    );
    expect(rows).toEqual([]);
  });

  it('revokes every privilege from anon and authenticated', async () => {
    for (const role of ['anon', 'authenticated']) {
      const [privs] = (
        await rls.query(
          `SELECT has_table_privilege($1, 'public.complaint_comments', 'SELECT') AS s,
                  has_table_privilege($1, 'public.complaint_comments', 'INSERT') AS i,
                  has_table_privilege($1, 'public.complaint_comments', 'UPDATE') AS u,
                  has_table_privilege($1, 'public.complaint_comments', 'DELETE') AS d`,
          [role],
        )
      ).rows;
      expect(privs).toEqual({ s: false, i: false, u: false, d: false });
      await expect(asRole(role, 'SELECT body FROM complaint_comments')).rejects.toThrow(
        /permission denied/,
      );
      await expect(insertComment(role, 'From the API')).rejects.toThrow(/permission denied/);
    }
  });

  it('a role with grants but no ownership or BYPASSRLS sees and writes nothing', async () => {
    expect(await asRole('other_app', 'SELECT body FROM complaint_comments')).toEqual([]);
    await expect(insertComment('other_app', 'Sneaky')).rejects.toThrow(/row-level security/);
    expect(
      await asRole('other_app', `UPDATE complaint_comments SET body = 'x' RETURNING id`),
    ).toEqual([]);
    expect(await asRole('other_app', 'DELETE FROM complaint_comments RETURNING id')).toEqual([]);
  });

  it('a BYPASSRLS role keeps access', async () => {
    expect(await asRole('bypass_app', 'SELECT body FROM complaint_comments')).toEqual([
      { body: 'Internal note' },
    ]);
  });

  it('the table-owning backend role keeps full access without superuser or BYPASSRLS', async () => {
    expect(await asRole('app_owner', 'SELECT body FROM complaint_comments')).toEqual([
      { body: 'Internal note' },
    ]);
    const [inserted] = await insertComment('app_owner', 'Owner write');
    expect(inserted.id).toEqual(expect.any(String));
    expect(
      await asRole('app_owner', `UPDATE complaint_comments SET body = 'Owner edit' WHERE id = $1 RETURNING body`, [
        inserted.id,
      ]),
    ).toEqual([{ body: 'Owner edit' }]);
    expect(
      await asRole('app_owner', 'DELETE FROM complaint_comments WHERE id = $1 RETURNING id', [
        inserted.id,
      ]),
    ).toEqual([{ id: inserted.id }]);
    const [{ n }] = (await rls.query(`SELECT COUNT(*)::int AS n FROM complaint_comments`)).rows;
    expect(n).toBe(1);
  });

  it('re-running the migration keeps the same protections and data', async () => {
    await rls.exec(`SET ROLE app_owner;`);
    await rls.exec(MIGRATION_027);
    await rls.exec(`RESET ROLE;`);
    const [row] = (
      await rls.query(
        `SELECT relrowsecurity, relforcerowsecurity,
                (SELECT COUNT(*)::int FROM pg_policies WHERE tablename = 'complaint_comments') AS policies,
                has_table_privilege('anon', oid, 'SELECT') AS anon_select
         FROM pg_class WHERE oid = 'public.complaint_comments'::regclass`,
      )
    ).rows;
    expect(row).toEqual({
      relrowsecurity: true,
      relforcerowsecurity: false,
      policies: 0,
      anon_select: false,
    });
    expect(await asRole('app_owner', 'SELECT body FROM complaint_comments')).toEqual([
      { body: 'Internal note' },
    ]);
  });

  it('on plain PostgreSQL without Supabase roles the guarded revoke is skipped', async () => {
    const { rows } = await pg.db.query(
      `SELECT rolname FROM pg_roles WHERE rolname IN ('anon', 'authenticated')`,
    );
    expect(rows).toEqual([]);
    const [row] = (
      await pg.db.query(
        `SELECT relrowsecurity, relforcerowsecurity FROM pg_class
         WHERE oid = 'public.complaint_comments'::regclass`,
      )
    ).rows;
    expect(row).toEqual({ relrowsecurity: true, relforcerowsecurity: false });
  });

  it('the migration text adds no policies, FORCE or API-role grants', () => {
    const sql = MIGRATION_027.replace(/--[^\n]*/g, '');
    expect(sql).toMatch(/ALTER TABLE public\.complaint_comments ENABLE ROW LEVEL SECURITY/);
    expect(sql).not.toMatch(/CREATE\s+POLICY/i);
    expect(sql).not.toMatch(/FORCE\s+ROW\s+LEVEL\s+SECURITY/i);
    expect(sql).not.toMatch(/GRANT[^;]*\b(anon|authenticated)\b/i);
  });
});
