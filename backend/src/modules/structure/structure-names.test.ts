// Renaming and naming rules for structure nodes (rooms, flats, beds) through
// the real structure router, service and repository SQL on an in-memory
// Postgres (PGlite). No server process, network or real database.
import type { AddressInfo } from 'net';
import express from 'express';
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';

process.env.DATABASE_URL ??= 'postgres://test:test@127.0.0.1:1/test';
process.env.JWT_ACCESS_SECRET ??= 'test';
process.env.JWT_REFRESH_SECRET ??= 'test';
process.env.RAZORPAY_KEY_ID ??= 'rzp_test_x';
process.env.RAZORPAY_KEY_SECRET ??= 'test';
process.env.RAZORPAY_WEBHOOK_SECRET ??= 'test';

const pg = vi.hoisted(() => ({ db: null as any }));

vi.mock('@config/db', () => ({
  query: async (sql: string, params?: unknown[]) => (await pg.db.query(sql, params ?? [])).rows,
}));

vi.mock('./apartment-quota', () => ({ assertApartmentNodeQuota: async () => undefined }));

const P1 = '11000000-0000-4000-8000-000000000001';
const P2 = '12000000-0000-4000-8000-000000000002';
const FLOOR_LEVEL = '91000000-0000-4000-8000-000000000001';
const ROOM_LEVEL = '91000000-0000-4000-8000-000000000002';
const P2_ROOM_LEVEL = '92000000-0000-4000-8000-000000000003';
const FLOOR_1 = '21000000-0000-4000-8000-000000000001';
const FLOOR_2 = '21000000-0000-4000-8000-000000000002';
const ROOM_101 = '21000000-0000-4000-8000-000000000003';
const ROOM_102 = '21000000-0000-4000-8000-000000000004';
const ROOM_101_F2 = '21000000-0000-4000-8000-000000000005';
const P2_ROOM = '22000000-0000-4000-8000-000000000006';

let baseUrl = '';
let server: ReturnType<express.Express['listen']>;

async function resetData() {
  await pg.db.exec(`TRUNCATE hierarchy_levels, hierarchy_nodes;`);
  await pg.db.query(
    `INSERT INTO hierarchy_levels (id, property_id, display_name, internal_key, parent_level_id) VALUES
       ($1, $4, 'Floor', 'floor', NULL), ($2, $4, 'Room', 'room', $1), ($3, $5, 'Room', 'room', NULL)`,
    [FLOOR_LEVEL, ROOM_LEVEL, P2_ROOM_LEVEL, P1, P2],
  );
  await pg.db.query(
    `INSERT INTO hierarchy_nodes (id, property_id, level_id, parent_node_id, name) VALUES
       ($1, $7, $8, NULL, 'Floor 1'), ($2, $7, $8, NULL, 'Floor 2'),
       ($3, $7, $9, $1, 'Room 101'), ($4, $7, $9, $1, 'Room 102'),
       ($5, $7, $9, $2, 'Room 101'), ($6, $10, $11, NULL, 'Room 102')`,
    [FLOOR_1, FLOOR_2, ROOM_101, ROOM_102, ROOM_101_F2, P2_ROOM, P1, FLOOR_LEVEL, ROOM_LEVEL, P2, P2_ROOM_LEVEL],
  );
}

beforeAll(async () => {
  const { PGlite } = await import('@electric-sql/pglite');
  pg.db = new PGlite();
  await pg.db.exec(`
    CREATE TABLE hierarchy_levels (
      id uuid PRIMARY KEY, property_id uuid, display_name text, internal_key text,
      icon text, color text, order_index int DEFAULT 0, parent_level_id uuid,
      is_enabled boolean DEFAULT true, allow_multiple_children boolean DEFAULT true,
      supports_occupancy boolean DEFAULT false, supports_assets boolean DEFAULT false,
      supports_complaints boolean DEFAULT false, visibility text, metadata jsonb,
      created_at timestamptz DEFAULT now(), updated_at timestamptz DEFAULT now());
    CREATE TABLE hierarchy_nodes (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(), property_id uuid, level_id uuid,
      parent_node_id uuid, name text, code text, order_index int DEFAULT 0,
      is_active boolean DEFAULT true, metadata jsonb, space_type text,
      monthly_rent numeric(12,2), security_deposit numeric(12,2),
      created_at timestamptz DEFAULT now(), updated_at timestamptz DEFAULT now());
  `);

  const { structureRouter } = await import('./structure.routes.js');
  const { errorHandler } = await import('../../shared/middleware/error-handler.js');
  const app = express();
  app.use(express.json());
  app.use(
    '/v1/properties/:propertyId/structure',
    (req: any, _res, next) => {
      req.userId = '31000000-0000-4000-8000-000000000001';
      req.ctxRole = req.headers['x-role'] ?? 'manager';
      next();
    },
    structureRouter,
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

async function send(method: 'PATCH' | 'POST', path: string, body: unknown, role = 'manager') {
  const res = await fetch(`${baseUrl}/v1/properties/${path}`, {
    method,
    headers: { 'content-type': 'application/json', 'x-role': role },
    body: JSON.stringify(body),
  });
  return { status: res.status, body: (await res.json().catch(() => null)) as any };
}

const rename = (nodeId: string, name: unknown, property = P1, role = 'manager') =>
  send('PATCH', `${property}/structure/nodes/${nodeId}`, { name }, role);

const nameOf = async (id: string) =>
  (await pg.db.query(`SELECT name FROM hierarchy_nodes WHERE id = $1`, [id])).rows[0]?.name;

describe('renaming a room', () => {
  it.each(['manager', 'owner', 'admin'])('lets the %s rename a room', async (role) => {
    const res = await rename(ROOM_101, 'Room 105', P1, role);
    expect(res.status).toBe(200);
    expect(res.body.data).toMatchObject({ id: ROOM_101, name: 'Room 105' });
    expect(await nameOf(ROOM_101)).toBe('Room 105');
  });

  it('trims and collapses spaces in the new name', async () => {
    const res = await rename(ROOM_101, '   Room    105  ');
    expect(res.status).toBe(200);
    expect(await nameOf(ROOM_101)).toBe('Room 105');
  });

  it('refuses a name already used on the same floor, ignoring case and spaces', async () => {
    for (const name of ['Room 102', 'room 102', '  ROOM   102 ']) {
      const res = await rename(ROOM_101, name);
      expect(res.status).toBe(409);
      expect(res.body).toEqual({
        error: 'A Room named "Room 102" already exists in Floor 1. Choose a different name.',
      });
    }
    expect(await nameOf(ROOM_101)).toBe('Room 101');
  });

  it('allows keeping or re-casing its own name', async () => {
    expect((await rename(ROOM_101, 'Room 101')).status).toBe(200);
    expect((await rename(ROOM_101, 'ROOM 101')).status).toBe(200);
    expect(await nameOf(ROOM_101)).toBe('ROOM 101');
  });

  it('allows the same name on a different floor', async () => {
    const res = await rename(ROOM_101_F2, 'Room 102');
    expect(res.status).toBe(200);
    expect(await nameOf(ROOM_101_F2)).toBe('Room 102');
  });

  it("is not blocked by another property's rooms", async () => {
    const res = await rename(ROOM_102, 'Room 103');
    expect(res.status).toBe(200);
    expect(await nameOf(P2_ROOM)).toBe('Room 102');
  });

  it.each([
    ['', 'Name cannot be empty.'],
    ['    ', 'Name cannot be empty.'],
    ['x'.repeat(81), 'Name can be at most 80 characters.'],
    [42, 'Name is required.'],
  ])('refuses the invalid name %j', async (name, message) => {
    const res = await rename(ROOM_101, name);
    expect(res.status).toBe(409);
    expect(res.body).toEqual({ error: message });
    expect(await nameOf(ROOM_101)).toBe('Room 101');
  });

  it('keeps staff and tenants out', async () => {
    for (const role of ['staff', 'tenant']) {
      const res = await rename(ROOM_101, 'Room 999', P1, role);
      expect(res.status).toBe(403);
    }
    expect(await nameOf(ROOM_101)).toBe('Room 101');
  });

  it("cannot rename another property's room through this property", async () => {
    const res = await rename(P2_ROOM, 'Hijacked');
    expect(res.status).toBe(404);
    expect(await nameOf(P2_ROOM)).toBe('Room 102');
  });

  it('changes the room number, e.g. Room 101 to Room 109', async () => {
    const res = await rename(ROOM_101, 'Room 109');
    expect(res.status).toBe(200);
    expect(await nameOf(ROOM_101)).toBe('Room 109');
  });

  it('treats a bare number and "Room <number>" as the same room', async () => {
    // The app shows a room stored as "102" as "Room 102".
    await pg.db.query(`UPDATE hierarchy_nodes SET name = '102' WHERE id = $1`, [ROOM_102]);
    const res = await rename(ROOM_101, 'Room 102');
    expect(res.status).toBe(409);
    expect(res.body.error).toBe(
      'A Room named "102" already exists in Floor 1. Choose a different name.',
    );

    await pg.db.query(`UPDATE hierarchy_nodes SET name = '108' WHERE id = $1`, [ROOM_101]);
    expect((await rename(ROOM_101, '102')).status).toBe(409);
    expect((await rename(ROOM_101, 'Room 108')).status).toBe(200);
    expect((await rename(ROOM_101, '109')).status).toBe(200);
    expect(await nameOf(ROOM_101)).toBe('109');
  });

  it('does not confuse a Floor label with a bare room number', async () => {
    await pg.db.query(
      `INSERT INTO hierarchy_nodes (property_id, level_id, parent_node_id, name)
       VALUES ($1, $2, NULL, '3')`,
      [P1, ROOM_LEVEL],
    );
    // "Room 3" and "Floor 3" share the top level but read differently.
    const res = await send('POST', `${P1}/structure/nodes`, {
      levelId: FLOOR_LEVEL,
      parentNodeId: null,
      name: 'Floor 3',
    });
    expect(res.status).toBe(201);
    // A bare "1" on the Floor level reads "Floor 1", which exists.
    expect((await rename(FLOOR_2, '1')).status).toBe(409);
  });

  it('still saves other changes without a name', async () => {
    const res = await send('PATCH', `${P1}/structure/nodes/${ROOM_101}`, { monthlyRent: 7500 });
    expect(res.status).toBe(200);
    expect(res.body.data.monthlyRent).toBe(7500);
    expect(await nameOf(ROOM_101)).toBe('Room 101');
  });
});

describe('creating a room', () => {
  const create = (parentNodeId: string | null, name: string) =>
    send('POST', `${P1}/structure/nodes`, { levelId: ROOM_LEVEL, parentNodeId, name });

  it('refuses a duplicate on the same floor', async () => {
    const res = await create(FLOOR_1, ' room 101 ');
    expect(res.status).toBe(409);
    expect(res.body.error).toBe(
      'A Room named "Room 101" already exists in Floor 1. Choose a different name.',
    );
    const count = await pg.db.query(
      `SELECT count(*)::int AS n FROM hierarchy_nodes WHERE parent_node_id = $1`,
      [FLOOR_1],
    );
    expect(count.rows[0].n).toBe(2);
  });

  it('creates a new name, stored trimmed', async () => {
    const res = await create(FLOOR_1, '  Room   103 ');
    expect(res.status).toBe(201);
    expect(res.body.data.name).toBe('Room 103');
  });

  it('allows a name used on another floor', async () => {
    const res = await create(FLOOR_2, 'Room 102');
    expect(res.status).toBe(201);
  });

  it('refuses a duplicate floor at the top level', async () => {
    const res = await send('POST', `${P1}/structure/nodes`, {
      levelId: FLOOR_LEVEL,
      parentNodeId: null,
      name: 'floor 1',
    });
    expect(res.status).toBe(409);
    expect(res.body.error).toBe(
      'A Floor named "Floor 1" already exists in this property. Choose a different name.',
    );
  });
});
