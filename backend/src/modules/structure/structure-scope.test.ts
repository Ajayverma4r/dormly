// Property scoping of structure nodes through the real repository SQL, on an
// in-memory Postgres (PGlite). No server process, network or real database.
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';

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

const P1 = '11000000-0000-4000-8000-000000000001';
const P2 = '12000000-0000-4000-8000-000000000002';
const LEVEL_1 = '91000000-0000-4000-8000-000000000001';
const LEVEL_2 = '92000000-0000-4000-8000-000000000002';
const ROOM_P1 = '21000000-0000-4000-8000-000000000001';
const ROOM_P2 = '22000000-0000-4000-8000-000000000002';
const STRAY = '23000000-0000-4000-8000-000000000003';

let service: any;
let StructureValidationError: any;

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
  await pg.db.query(
    `INSERT INTO hierarchy_levels (id, property_id, display_name, internal_key) VALUES
       ($1, $2, 'Room', 'room'), ($3, $4, 'Room', 'room')`,
    [LEVEL_1, P1, LEVEL_2, P2],
  );
  // STRAY: a P2 row pointing at P1's level, as a manipulated or legacy row could.
  await pg.db.query(
    `INSERT INTO hierarchy_nodes (id, property_id, level_id, name, monthly_rent) VALUES
       ($1, $4, $5, 'Room 101', 9000), ($2, $6, $7, 'Room 201', 7000),
       ($3, $6, $5, 'Stray', 5000)`,
    [ROOM_P1, ROOM_P2, STRAY, P1, LEVEL_1, P2, LEVEL_2],
  );

  const { StructureService, StructureValidationError: SVE } = await import(
    '../../core/structure-engine/services/structure.service.js'
  );
  const { PgHierarchyLevelRepository, PgHierarchyNodeRepository } = await import(
    './structure.repository.js'
  );
  StructureValidationError = SVE;
  service = new StructureService(new PgHierarchyLevelRepository(), new PgHierarchyNodeRepository());
}, 60_000);

afterAll(async () => {
  await pg.db?.close();
});

describe('node listing', () => {
  it("returns only the requested property's nodes, even for a shared level id", async () => {
    const nodes = await service.listNodes(P1, LEVEL_1, null);
    expect(nodes.map((n: any) => n.id)).toEqual([ROOM_P1]);
  });

  it("another property's level yields nothing", async () => {
    expect(await service.listNodes(P1, LEVEL_2, null)).toEqual([]);
  });

  it("a parent node from another property yields nothing", async () => {
    expect(await service.listNodes(P1, LEVEL_1, ROOM_P2)).toEqual([]);
  });
});

describe('node creation', () => {
  it("refuses a level of another property", async () => {
    await expect(
      service.createNode({ propertyId: P1, levelId: LEVEL_2, name: 'Sneaky' }),
    ).rejects.toBeInstanceOf(StructureValidationError);
  });

  it("refuses a parent node of another property", async () => {
    await expect(
      service.createNode({ propertyId: P1, levelId: LEVEL_1, parentNodeId: ROOM_P2, name: 'Sneaky' }),
    ).rejects.toBeInstanceOf(StructureValidationError);
  });

  it('still creates a node on its own property', async () => {
    const node = await service.createNode({ propertyId: P1, levelId: LEVEL_1, name: 'Room 102' });
    expect(node).toMatchObject({ propertyId: P1, levelId: LEVEL_1, name: 'Room 102' });
  });
});
