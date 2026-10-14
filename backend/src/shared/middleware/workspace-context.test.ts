// Workspace tokens are only as good as the server's current memberships:
// selection is validated against ContextService, and every request rechecks
// the token's workspace (contextStillValid). In-memory Postgres only.
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';

const pg = vi.hoisted(() => ({ db: null as any }));

vi.mock('@config/db', () => {
  const run = async (sql: string, params?: unknown[]) =>
    (await pg.db.query(sql, params ?? [])).rows;
  return { query: run, withTransaction: async (fn: any) => fn(run) };
});

vi.mock('@config/env', () => ({
  env: { jwtAccessSecret: 'test-access', jwtAccessTtl: '15m' },
}));

import jwt from 'jsonwebtoken';
import { contextStillValid, type TokenContext } from './auth-guard';
import { ContextService } from '@modules/auth/context.service';
import { AuthContextController } from '@modules/auth/auth-context.controller';

const id = (n: number) => `f${String(n).padStart(7, '0')}-0000-4000-8000-000000000000`;
const ORG_A = id(1);
const ORG_B = id(2);
const ORG_EMPTY = id(3);
const PROP_A = id(4);
const PROP_B = id(5);
const NODE = id(6);
const OWNER = id(10);
const ADMIN = id(11);
const REMOVED_ADMIN = id(12);
const MANAGER = id(13);
const STAFF = id(14);
const INVITED = id(15);
const TENANT = id(16);
const STAFF_AND_TENANT = id(17);
const LEGACY = id(18);
const TEN_ACTIVE = id(20);
const TEN_PENDING = id(21);
const TEN_ENDED = id(22);
const TEN_MIXED = id(23);

const contexts = new ContextService();

const org = (userId: string, ctxId: string, ctxRole: string): TokenContext => ({
  userId, ctxType: 'organization', ctxId, ctxRole, ctxPropertyId: null,
});
const scoped = (userId: string, propertyId: string, ctxRole: string): TokenContext => ({
  userId, ctxType: 'organization', ctxId: propertyId, ctxRole, ctxPropertyId: propertyId,
});
const tenancy = (userId: string, tenancyId: string, propertyId = PROP_A): TokenContext => ({
  userId, ctxType: 'tenancy', ctxId: tenancyId, ctxRole: 'tenant', ctxPropertyId: propertyId,
});

beforeAll(async () => {
  const { PGlite } = await import('@electric-sql/pglite');
  pg.db = new PGlite();
  await pg.db.exec(`
    CREATE TABLE organizations (id uuid PRIMARY KEY, name text);
    CREATE TABLE memberships (user_id uuid, organization_id uuid, role text);
    CREATE TABLE properties (id uuid PRIMARY KEY, organization_id uuid, name text);
    CREATE TABLE hierarchy_nodes (id uuid PRIMARY KEY, name text);
    CREATE TABLE property_staff_assignments (user_id uuid, property_id uuid, role text, status text);
    CREATE TABLE tenancies (id uuid PRIMARY KEY, user_id uuid, property_id uuid, node_id uuid,
                            status text);

    INSERT INTO organizations VALUES ('${ORG_A}', 'A'), ('${ORG_B}', 'B'), ('${ORG_EMPTY}', 'Legacy');
    INSERT INTO properties VALUES ('${PROP_A}', '${ORG_A}', 'Sky Hostel'), ('${PROP_B}', '${ORG_B}', 'Lake PG');
    INSERT INTO hierarchy_nodes VALUES ('${NODE}', 'Room 1');
    INSERT INTO memberships VALUES ('${OWNER}', '${ORG_A}', 'owner'), ('${ADMIN}', '${ORG_A}', 'admin'),
                                   ('${LEGACY}', '${ORG_EMPTY}', 'owner');
    INSERT INTO property_staff_assignments VALUES
      ('${MANAGER}', '${PROP_A}', 'manager', 'active'),
      ('${STAFF}', '${PROP_A}', 'staff', 'active'),
      ('${INVITED}', '${PROP_A}', 'manager', 'pending'),
      ('${STAFF_AND_TENANT}', '${PROP_B}', 'staff', 'active');
    INSERT INTO tenancies VALUES
      ('${TEN_ACTIVE}', '${TENANT}', '${PROP_A}', '${NODE}', 'active'),
      ('${TEN_PENDING}', '${INVITED}', '${PROP_A}', '${NODE}', 'pending'),
      ('${TEN_ENDED}', '${LEGACY}', '${PROP_A}', '${NODE}', 'ended'),
      ('${TEN_MIXED}', '${STAFF_AND_TENANT}', '${PROP_A}', '${NODE}', 'active');
  `);
}, 60_000);

afterAll(async () => {
  await pg.db?.close();
});

describe('contextStillValid', () => {
  it('owner and admin: only their own organization, with their own role', async () => {
    expect(await contextStillValid(org(OWNER, ORG_A, 'owner'))).toBe(true);
    expect(await contextStillValid(org(ADMIN, ORG_A, 'admin'))).toBe(true);
    expect(await contextStillValid(org(OWNER, ORG_B, 'owner'))).toBe(false);
    expect(await contextStillValid(org(ADMIN, ORG_A, 'owner'))).toBe(false);
    expect(await contextStillValid(org(REMOVED_ADMIN, ORG_A, 'admin'))).toBe(false);
  });

  it('manager and staff: only an accepted assignment on their property, same role', async () => {
    expect(await contextStillValid(scoped(MANAGER, PROP_A, 'manager'))).toBe(true);
    expect(await contextStillValid(scoped(STAFF, PROP_A, 'staff'))).toBe(true);
    expect(await contextStillValid(scoped(STAFF, PROP_A, 'manager'))).toBe(false);
    expect(await contextStillValid(scoped(MANAGER, PROP_B, 'manager'))).toBe(false);
    expect(await contextStillValid(scoped(INVITED, PROP_A, 'manager'))).toBe(false);
    expect(
      await contextStillValid({ ...scoped(MANAGER, PROP_A, 'manager'), ctxPropertyId: PROP_B }),
    ).toBe(false);
    // A manager token can never pass as an organization-wide one.
    expect(await contextStillValid(org(MANAGER, ORG_A, 'manager'))).toBe(false);
  });

  it('tenant: only their own active tenancy on its property', async () => {
    expect(await contextStillValid(tenancy(TENANT, TEN_ACTIVE))).toBe(true);
    expect(await contextStillValid(tenancy(TENANT, TEN_ACTIVE, PROP_B))).toBe(false);
    expect(await contextStillValid(tenancy(OWNER, TEN_ACTIVE))).toBe(false);
    expect(await contextStillValid(tenancy(INVITED, TEN_PENDING))).toBe(false);
    expect(await contextStillValid(tenancy(LEGACY, TEN_ENDED))).toBe(false);
  });

  it('unknown roles, mismatched types and malformed ids grant nothing', async () => {
    expect(await contextStillValid(org(OWNER, ORG_A, 'viewer'))).toBe(false);
    expect(await contextStillValid({ ...tenancy(TENANT, TEN_ACTIVE), ctxType: 'organization' })).toBe(false);
    expect(await contextStillValid({ ...org(OWNER, ORG_A, 'owner'), ctxType: 'tenancy' })).toBe(false);
    expect(await contextStillValid(org('not-a-uuid', ORG_A, 'owner'))).toBe(false);
  });
});

describe('workspaces the server offers', () => {
  it('staff + tenant gets both workspaces; nothing pending or ended is listed', async () => {
    const list = await contexts.listContextsForUser(STAFF_AND_TENANT);
    expect(list.map((c) => [c.type, c.role, c.propertyId])).toEqual([
      ['organization', 'staff', PROP_B],
      ['tenancy', 'tenant', PROP_A],
    ]);
    expect(await contexts.listContextsForUser(INVITED)).toEqual([]);
  });

  it('a legacy empty owner workspace is listed with zero properties and reaches nothing else', async () => {
    const list = await contexts.listContextsForUser(LEGACY);
    expect(list).toEqual([
      expect.objectContaining({ id: ORG_EMPTY, role: 'owner', propertyCount: 0 }),
    ]);
    expect(await contextStillValid(org(LEGACY, ORG_A, 'owner'))).toBe(false);
  });
});

describe('selecting a workspace', () => {
  const controller = new AuthContextController();

  async function select(userId: string, contextType: string, contextId: string) {
    const res: any = { statusCode: 200, body: null };
    res.status = (code: number) => ((res.statusCode = code), res);
    res.json = (body: unknown) => ((res.body = body), res);
    let error: unknown;
    await controller.selectContext(
      { userId, body: { contextType, contextId } } as any,
      res,
      (err?: unknown) => {
        error = err;
      },
    );
    return { status: error ? 500 : res.statusCode, body: res.body };
  }

  it('issues a token only for a workspace the server lists for that user', async () => {
    const ok = await select(STAFF_AND_TENANT, 'tenancy', TEN_MIXED);
    expect(ok.status).toBe(200);
    const claims = jwt.verify(ok.body.data.accessToken, 'test-access') as any;
    expect(claims).toMatchObject({
      sub: STAFF_AND_TENANT, ctxType: 'tenancy', ctxId: TEN_MIXED, ctxRole: 'tenant', ctxPropertyId: PROP_A,
    });
  });

  it("rejects someone else's tenancy, a pending invite, an ended tenancy and a foreign org", async () => {
    expect((await select(STAFF_AND_TENANT, 'tenancy', TEN_ACTIVE)).status).toBe(403);
    expect((await select(INVITED, 'organization', PROP_A)).status).toBe(403);
    expect((await select(INVITED, 'tenancy', TEN_PENDING)).status).toBe(403);
    expect((await select(LEGACY, 'tenancy', TEN_ENDED)).status).toBe(403);
    expect((await select(OWNER, 'organization', ORG_B)).status).toBe(403);
    expect((await select(STAFF, 'organization', ORG_A)).status).toBe(403);
  });
});
