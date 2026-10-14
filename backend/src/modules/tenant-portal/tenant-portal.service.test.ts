// getMyTenancy SQL on an in-memory Postgres (PGlite) with the real
// hierarchy_nodes column names. No server process or real database.
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
import { TenantPortalService } from './tenant-portal.service';

const pg = vi.hoisted(() => ({ db: null as any }));

vi.mock('@config/db', () => ({
  query: async (sql: string, params?: unknown[]) =>
    (await pg.db.query(sql, params ?? [])).rows,
}));

vi.mock('@modules/notifications/move-out-notifications', () => ({
  notifyOwnersOfMoveOut: async () => 0,
}));

const ORG = '01000000-0000-4000-8000-000000000000';
const PROP = '11000000-0000-4000-8000-000000000000';
const OWNER = '31000000-0000-4000-8000-000000000001';
const TENANT = '31000000-0000-4000-8000-000000000002';
const FLOOR_LEVEL = '51000000-0000-4000-8000-000000000001';
const ROOM_LEVEL = '51000000-0000-4000-8000-000000000002';
const BED_LEVEL = '51000000-0000-4000-8000-000000000003';
const FLOOR = '61000000-0000-4000-8000-000000000001';
const ROOM = '61000000-0000-4000-8000-000000000002';
const BED = '61000000-0000-4000-8000-000000000003';
const TENANCY = '41000000-0000-4000-8000-000000000001';

beforeAll(async () => {
  const { PGlite } = await import('@electric-sql/pglite');
  pg.db = new PGlite();
  await pg.db.exec(`
    CREATE TABLE users (id UUID PRIMARY KEY, phone TEXT, name TEXT);
    CREATE TABLE organizations (id UUID PRIMARY KEY, owner_user_id UUID, name TEXT);
    CREATE TABLE properties (
      id UUID PRIMARY KEY, organization_id UUID, name TEXT, address TEXT,
      city TEXT, property_type_key TEXT
    );
    CREATE TABLE hierarchy_levels (id UUID PRIMARY KEY, internal_key TEXT);
    CREATE TABLE hierarchy_nodes (
      id UUID PRIMARY KEY, property_id UUID, level_id UUID,
      parent_node_id UUID REFERENCES hierarchy_nodes(id), name TEXT
    );
    CREATE TABLE tenancies (
      id UUID PRIMARY KEY, user_id UUID, property_id UUID, node_id UUID, status TEXT
    );
  `);
  await pg.db.exec(`
    INSERT INTO users VALUES ('${OWNER}', '+910000000001', 'Owner'),
                             ('${TENANT}', '+910000000002', 'Tenant');
    INSERT INTO organizations VALUES ('${ORG}', '${OWNER}', 'Org');
    INSERT INTO properties VALUES ('${PROP}', '${ORG}', 'Sky Hostel', 'Street', 'City', 'pg_hostel');
    INSERT INTO hierarchy_levels VALUES ('${FLOOR_LEVEL}', 'floor'),
                                        ('${ROOM_LEVEL}', 'room'),
                                        ('${BED_LEVEL}', 'bed');
    INSERT INTO hierarchy_nodes VALUES
      ('${FLOOR}', '${PROP}', '${FLOOR_LEVEL}', NULL, 'Floor 2'),
      ('${ROOM}', '${PROP}', '${ROOM_LEVEL}', '${FLOOR}', 'Room 204'),
      ('${BED}', '${PROP}', '${BED_LEVEL}', '${ROOM}', 'Bed B');
    INSERT INTO tenancies VALUES ('${TENANCY}', '${TENANT}', '${PROP}', '${BED}', 'active');
  `);
});

afterAll(async () => {
  await pg.db?.close();
});

describe('TenantPortalService.getMyTenancy', () => {
  it('resolves the bed with its room and floor ancestors', async () => {
    const row = await new TenantPortalService().getMyTenancy(TENANCY);
    expect(row).toMatchObject({
      node_name: 'Bed B',
      parent_node_name: 'Room 204',
      grandparent_node_name: 'Floor 2',
      node_level_key: 'bed',
      property_name: 'Sky Hostel',
    });
  });

  it('returns null for an unknown tenancy', async () => {
    const row = await new TenantPortalService().getMyTenancy(
      '49999999-0000-4000-8000-000000000000',
    );
    expect(row).toBeNull();
  });
});
