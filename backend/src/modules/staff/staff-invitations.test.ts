// Staff/manager invitations: nobody gets access until they accept, and every
// step is limited to the right user and property. In-memory Postgres only.
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';

const pg = vi.hoisted(() => ({ db: null as any }));
const sent = vi.hoisted(() => ({ notifications: [] as any[] }));

vi.mock('@config/db', () => {
  const run = async (sql: string, params?: unknown[]) =>
    (await pg.db.query(sql, params ?? [])).rows;
  return {
    query: run,
    withTransaction: async (fn: (q: typeof run) => Promise<unknown>) => fn(run),
  };
});

vi.mock('@modules/notifications/notify', () => ({
  createNotification: async (input: unknown) => {
    sent.notifications.push(input);
    return true;
  },
}));

import { StaffInviteError, StaffService } from './staff.service';
import { ContextService } from '@modules/auth/context.service';
import { activeStaffRole } from '@shared/middleware/auth-guard';

const ORG = 'd1000000-0000-4000-8000-000000000000';
const PROP = 'd2000000-0000-4000-8000-000000000000';
const OTHER_PROP = 'd3000000-0000-4000-8000-000000000000';
const OWNER = 'd4000000-0000-4000-8000-000000000000';
const INVITEE_PHONE = '+919111111111';
const STRANGER = 'd5000000-0000-4000-8000-000000000000';

const service = new StaffService();
const contexts = new ContextService();

async function inviteeId(): Promise<string> {
  return (await pg.db.query(`SELECT id FROM users WHERE phone = $1`, [INVITEE_PHONE])).rows[0].id;
}

async function expectInviteError(p: Promise<unknown>, status: number) {
  const err: any = await p.catch((e: unknown) => e);
  expect(err).toBeInstanceOf(StaffInviteError);
  expect(err.status).toBe(status);
}

describe('staff invitations', () => {
  beforeAll(async () => {
    const { PGlite } = await import('@electric-sql/pglite');
    pg.db = new PGlite();
    await pg.db.exec(`
      CREATE TABLE users (id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                          phone TEXT UNIQUE NOT NULL, name TEXT);
      CREATE TABLE organizations (id UUID PRIMARY KEY, name TEXT, owner_user_id UUID);
      CREATE TABLE memberships (user_id UUID, organization_id UUID, role TEXT);
      CREATE TABLE properties (id UUID PRIMARY KEY, organization_id UUID, name TEXT);
      CREATE TABLE hierarchy_nodes (id UUID PRIMARY KEY, name TEXT);
      CREATE TABLE tenancies (id UUID PRIMARY KEY, user_id UUID, property_id UUID,
                              node_id UUID, status TEXT);
      CREATE TABLE property_staff_assignments (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL, property_id UUID NOT NULL, role TEXT NOT NULL,
        assigned_by UUID, created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'active')));

      INSERT INTO users (id, phone, name) VALUES
        ('${OWNER}', '+919000000000', 'Owner'), ('${STRANGER}', '+919222222222', 'Someone');
      INSERT INTO organizations VALUES ('${ORG}', 'Org', '${OWNER}');
      INSERT INTO memberships VALUES ('${OWNER}', '${ORG}', 'owner');
      INSERT INTO properties VALUES ('${PROP}', '${ORG}', 'Sky Hostel'),
                                    ('${OTHER_PROP}', '${ORG}', 'Lake PG');
    `);
  }, 60_000);

  afterAll(async () => {
    await pg.db?.close();
  });

  beforeEach(() => {
    sent.notifications = [];
  });

  it('an invite is pending, notifies the invitee, and grants no access', async () => {
    const invite = await service.assign(PROP, INVITEE_PHONE, 'manager', OWNER);
    expect(invite.status).toBe('pending');
    const userId = await inviteeId();

    expect(sent.notifications).toEqual([
      expect.objectContaining({
        userId,
        propertyId: PROP,
        type: 'staff_invitation',
        data: { assignmentId: invite.id, role: 'manager' },
      }),
    ]);
    expect(await service.listPendingForUser(userId)).toEqual([
      expect.objectContaining({ id: invite.id, property_name: 'Sky Hostel' }),
    ]);
    expect(await contexts.listContextsForUser(userId)).toEqual([]);
    expect(await activeStaffRole(userId, PROP)).toBeNull();
  });

  it('only the invited user can accept, and only once', async () => {
    const userId = await inviteeId();
    const [invite] = await service.listPendingForUser(userId);

    await expectInviteError(service.accept(invite.id, STRANGER), 404);
    expect(await activeStaffRole(userId, PROP)).toBeNull();

    const accepted = await service.accept(invite.id, userId);
    expect(accepted.status).toBe('active');
    expect(await activeStaffRole(userId, PROP)).toBe('manager');
    expect(await contexts.listContextsForUser(userId)).toEqual([
      expect.objectContaining({ role: 'manager', propertyId: PROP }),
    ]);

    await expectInviteError(service.accept(invite.id, userId), 404);
    await expectInviteError(service.decline(invite.id, userId), 404);
  });

  it('re-inviting with the same role changes nothing and sends nothing', async () => {
    const again = await service.assign(PROP, INVITEE_PHONE, 'manager', OWNER);
    expect(again.status).toBe('active');
    expect(sent.notifications).toEqual([]);
  });

  it('a role change is a new invitation: access pauses until accepted', async () => {
    const userId = await inviteeId();
    const changed = await service.assign(PROP, INVITEE_PHONE, 'staff', OWNER);
    expect(changed).toMatchObject({ status: 'pending', role: 'staff' });
    expect(sent.notifications).toHaveLength(1);
    expect(await activeStaffRole(userId, PROP)).toBeNull();

    await service.accept(changed.id, userId);
    expect(await activeStaffRole(userId, PROP)).toBe('staff');
  });

  it('declining removes the invitation without granting access', async () => {
    const userId = await inviteeId();
    const invite = await service.assign(OTHER_PROP, INVITEE_PHONE, 'staff', OWNER);
    await expectInviteError(service.decline(invite.id, STRANGER), 404);
    await service.decline(invite.id, userId);
    expect(await activeStaffRole(userId, OTHER_PROP)).toBeNull();
    expect(await service.listPendingForUser(userId)).toEqual([]);
  });

  it("owners cannot invite their own number or the organization's owner", async () => {
    await expectInviteError(service.assign(PROP, '+919000000000', 'staff', OWNER), 400);
    await expectInviteError(service.assign(PROP, '+919000000000', 'manager', STRANGER), 400);
  });

  it('removal only works within the property it belongs to', async () => {
    const userId = await inviteeId();
    const [row] = (
      await pg.db.query(
        `SELECT id FROM property_staff_assignments WHERE user_id = $1 AND property_id = $2`,
        [userId, PROP],
      )
    ).rows;

    await expectInviteError(service.remove(OTHER_PROP, row.id), 404);
    expect(await activeStaffRole(userId, PROP)).toBe('staff');

    await service.remove(PROP, row.id);
    expect(await activeStaffRole(userId, PROP)).toBeNull();
    expect(await contexts.listContextsForUser(userId)).toEqual([]);
  });
});
