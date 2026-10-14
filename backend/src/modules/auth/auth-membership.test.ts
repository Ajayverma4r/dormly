// Post-login membership data the app routes on: OTP login must not create an
// owner workspace, /auth/me reports the user's tenancies by status, and owner
// contexts carry their property count. In-memory Postgres (PGlite) only.
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

vi.mock('@config/env', () => ({
  env: {
    jwtAccessSecret: 'test-access',
    jwtRefreshSecret: 'test-refresh',
    jwtAccessTtl: '15m',
    jwtRefreshTtl: '30d',
    otpTtlSeconds: 300,
    otpBypass: true,
  },
}));

vi.mock('../subscriptions/subscription.service', () => ({
  SubscriptionService: class {
    async createTrialSubscription() {}
    async getOrgSubscription() {
      return null;
    }
  },
}));

import { AuthService } from './auth.service';
import { ContextService } from './context.service';

const OWNER_PHONE = '+919000000001';
const TENANT_PHONE = '+919000000002';
const ENDED_PHONE = '+919000000003';
const NEW_PHONE = '+919000000004';

const ORG = 'c1000000-0000-4000-8000-000000000000';
const PROP = 'c2000000-0000-4000-8000-000000000000';
const NODE = 'c3000000-0000-4000-8000-000000000000';

const service = new AuthService();
const contexts = new ContextService();

async function userId(phone: string): Promise<string> {
  return (await pg.db.query(`SELECT id FROM users WHERE phone = $1`, [phone])).rows[0].id;
}

async function ownerMemberships(phone: string): Promise<number> {
  const rows = (
    await pg.db.query(
      `SELECT COUNT(*)::int AS n FROM memberships m JOIN users u ON u.id = m.user_id
       WHERE u.phone = $1 AND m.role IN ('owner', 'admin')`,
      [phone],
    )
  ).rows;
  return rows[0].n;
}

describe('login membership data', () => {
  beforeAll(async () => {
    const { PGlite } = await import('@electric-sql/pglite');
    pg.db = new PGlite();
    await pg.db.exec(`
      CREATE TABLE users (id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                          phone TEXT UNIQUE NOT NULL, name TEXT, email TEXT, avatar_url TEXT);
      CREATE TABLE organizations (id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                                  name TEXT NOT NULL, owner_user_id UUID NOT NULL,
                                  created_at TIMESTAMPTZ NOT NULL DEFAULT now());
      CREATE TABLE memberships (id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                                user_id UUID NOT NULL, organization_id UUID NOT NULL,
                                role TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
                                UNIQUE (user_id, organization_id));
      CREATE TABLE properties (id UUID PRIMARY KEY, organization_id UUID NOT NULL, name TEXT);
      CREATE TABLE hierarchy_nodes (id UUID PRIMARY KEY, name TEXT);
      CREATE TABLE property_staff_assignments (user_id UUID, property_id UUID,
                                               role TEXT, status TEXT);
      CREATE TABLE tenancies (id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                              user_id UUID, property_id UUID, node_id UUID, status TEXT);

      INSERT INTO users (phone, name) VALUES
        ('${OWNER_PHONE}', 'Owner'), ('${TENANT_PHONE}', 'Tenant'),
        ('${ENDED_PHONE}', 'Former');
      INSERT INTO organizations (id, name, owner_user_id)
        SELECT '${ORG}', 'Owner Org', id FROM users WHERE phone = '${OWNER_PHONE}';
      INSERT INTO memberships (user_id, organization_id, role)
        SELECT id, '${ORG}', 'owner' FROM users WHERE phone = '${OWNER_PHONE}';
      INSERT INTO properties VALUES ('${PROP}', '${ORG}', 'Sky Hostel');
      INSERT INTO hierarchy_nodes VALUES ('${NODE}', 'Room 101');
      INSERT INTO tenancies (user_id, property_id, node_id, status)
        SELECT id, '${PROP}', '${NODE}', 'active' FROM users WHERE phone = '${TENANT_PHONE}';
      INSERT INTO tenancies (user_id, property_id, node_id, status)
        SELECT id, '${PROP}', '${NODE}', 'ended' FROM users WHERE phone = '${ENDED_PHONE}';
    `);
  }, 60_000);

  afterAll(async () => {
    await pg.db?.close();
  });

  it('a tenant logging in gets no owner workspace and sees only their tenancy', async () => {
    const result = await service.verifyOtp(TENANT_PHONE, '123456');
    expect(result.organizationId).toBeUndefined();
    expect(result.user.tenancies).toEqual({ active: 1, pending: 0, ended: 0 });
    expect(await ownerMemberships(TENANT_PHONE)).toBe(0);

    const list = await contexts.listContextsForUser(await userId(TENANT_PHONE));
    expect(list).toEqual([
      expect.objectContaining({ type: 'tenancy', role: 'tenant', propertyId: PROP }),
    ]);
  });

  it('an existing owner keeps their workspace and its property count', async () => {
    const result = await service.verifyOtp(OWNER_PHONE, '123456');
    expect(result.organizationId).toBe(ORG);
    expect(result.user.propertyCount).toBe(1);
    expect(result.user.tenancies).toEqual({ active: 0, pending: 0, ended: 0 });

    const list = await contexts.listContextsForUser(await userId(OWNER_PHONE));
    expect(list).toEqual([
      expect.objectContaining({ type: 'organization', id: ORG, role: 'owner', propertyCount: 1 }),
    ]);
  });

  it('a former tenant gets no workspace and their ended stay is reported', async () => {
    const result = await service.verifyOtp(ENDED_PHONE, '123456');
    expect(result.user.tenancies).toEqual({ active: 0, pending: 0, ended: 1 });
    expect(await ownerMemberships(ENDED_PHONE)).toBe(0);
    expect(await contexts.listContextsForUser(await userId(ENDED_PHONE))).toEqual([]);
  });

  it('a brand-new phone gets one account and a workspace only when it asks for one', async () => {
    await service.verifyOtp(NEW_PHONE, '123456');
    await service.verifyOtp(NEW_PHONE, '123456');
    const users = (await pg.db.query(`SELECT id FROM users WHERE phone = $1`, [NEW_PHONE])).rows;
    expect(users).toHaveLength(1);
    expect(await ownerMemberships(NEW_PHONE)).toBe(0);

    const id = users[0].id;
    const orgId = await service.ensureOwnerOrganization(id, NEW_PHONE);
    expect(await service.ensureOwnerOrganization(id, NEW_PHONE)).toBe(orgId);
    const list = await contexts.listContextsForUser(id);
    expect(list).toEqual([
      expect.objectContaining({ id: orgId, role: 'owner', propertyCount: 0 }),
    ]);
  });
});
