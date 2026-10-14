// Tenant payment history and statements through the real auth guard, context
// recheck and SQL, on an in-memory Postgres (PGlite). No real database.
import type { AddressInfo } from 'net';
import express from 'express';
import jwt from 'jsonwebtoken';
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
import { renderStatementPdf, statementContent } from './tenant-statement.pdf';

process.env.DATABASE_URL ??= 'postgres://test:test@127.0.0.1:1/test';
process.env.JWT_ACCESS_SECRET = 'tenant-statement-test-secret';
process.env.JWT_REFRESH_SECRET ??= 'test';
process.env.RAZORPAY_KEY_ID ??= 'rzp_test_x';
process.env.RAZORPAY_KEY_SECRET ??= 'test';
process.env.RAZORPAY_WEBHOOK_SECRET ??= 'test';

const pg = vi.hoisted(() => ({ db: null as any }));

vi.mock('@config/db', () => ({
  query: async (sql: string, params?: unknown[]) =>
    (await pg.db.query(sql, params ?? [])).rows,
}));

const ORG = '01000000-0000-4000-8000-000000000000';
const P_CUR = '11000000-0000-4000-8000-000000000001'; // Sky Hostel (current)
const P_OLD = '11000000-0000-4000-8000-000000000002'; // River PG (past)
const P_FOREIGN = '11000000-0000-4000-8000-000000000003'; // never stayed
const USER = {
  rahul: '31000000-0000-4000-8000-000000000001',
  other: '31000000-0000-4000-8000-000000000002',
  owner: '31000000-0000-4000-8000-000000000003',
};
const TEN = {
  cur: '41000000-0000-4000-8000-000000000001',
  old: '41000000-0000-4000-8000-000000000002',
  pending: '41000000-0000-4000-8000-000000000003',
  other: '41000000-0000-4000-8000-000000000004',
  foreign: '41000000-0000-4000-8000-000000000005',
};
const INV = {
  old: '51000000-0000-4000-8000-000000000001',
  cur: '51000000-0000-4000-8000-000000000002',
  draft: '51000000-0000-4000-8000-000000000003',
  other: '51000000-0000-4000-8000-000000000004',
};
const ROOM = '61000000-0000-4000-8000-000000000001';
const BED = '61000000-0000-4000-8000-000000000002';

const sign = (claims: Record<string, unknown>) =>
  jwt.sign(claims, process.env.JWT_ACCESS_SECRET!, { expiresIn: '5m' });
const tenantToken = (user: string, tenancy: string, property: string) =>
  sign({ sub: user, ctxType: 'tenancy', ctxId: tenancy, ctxRole: 'tenant', ctxPropertyId: property });

const TOKENS = {
  rahul: () => tenantToken(USER.rahul, TEN.cur, P_CUR),
  other: () => tenantToken(USER.other, TEN.other, P_OLD),
  // Rahul presenting his ended tenancy as the context.
  rahulEnded: () => tenantToken(USER.rahul, TEN.old, P_OLD),
  owner: () => sign({ sub: USER.owner, ctxType: 'organization', ctxId: ORG, ctxRole: 'owner', ctxPropertyId: null }),
};

let baseUrl = '';
let server: ReturnType<express.Express['listen']>;

beforeAll(async () => {
  const { PGlite } = await import('@electric-sql/pglite');
  pg.db = new PGlite();
  await pg.db.exec(`
    CREATE TABLE properties (id uuid PRIMARY KEY, organization_id uuid, name text,
      city text, timezone text);
    CREATE TABLE users (id uuid PRIMARY KEY, phone text);
    CREATE TABLE memberships (user_id uuid, organization_id uuid, role text);
    CREATE TABLE hierarchy_levels (id uuid PRIMARY KEY, internal_key text);
    CREATE TABLE hierarchy_nodes (id uuid PRIMARY KEY, property_id uuid, level_id uuid,
      parent_node_id uuid, name text);
    CREATE TABLE tenancies (id uuid PRIMARY KEY, property_id uuid, node_id uuid,
      user_id uuid, full_name text, status text, move_in_at timestamptz,
      move_out_at timestamptz);
    CREATE TABLE invoices (id uuid PRIMARY KEY, tenancy_id uuid, property_id uuid,
      period_start date, period_end date, due_date date, total_amount numeric(12,2),
      sent_at timestamptz);
    CREATE TABLE payments (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), invoice_id uuid,
      amount numeric(12,2), method text DEFAULT 'cash', note text, paid_at timestamptz);
  `);
  await pg.db.query(
    `INSERT INTO properties VALUES
       ($1, $4, 'Sky Hostel', 'Hyderabad', 'Asia/Kolkata'),
       ($2, $4, 'River PG', 'Delhi', 'Asia/Kolkata'),
       ($3, $4, 'Other Place', 'Pune', 'Asia/Kolkata')`,
    [P_CUR, P_OLD, P_FOREIGN, ORG],
  );
  await pg.db.query(`INSERT INTO users VALUES ($1, '+919000000001'), ($2, '+919000000002'), ($3, NULL)`,
    [USER.rahul, USER.other, USER.owner]);
  await pg.db.query(`INSERT INTO memberships VALUES ($1, $2, 'owner')`, [USER.owner, ORG]);
  await pg.db.query(`INSERT INTO hierarchy_nodes VALUES ($1, $3, NULL, NULL, 'Room 101'),
    ($2, $3, NULL, $1, 'Bed 1')`, [ROOM, BED, P_CUR]);
  await pg.db.query(
    `INSERT INTO tenancies VALUES
       ($1, $6, $8, $9, 'Rahul Sharma', 'active', '2026-09-01T00:00:00Z', NULL),
       ($2, $7, NULL, $9, 'Rahul Sharma', 'ended', '2026-01-01T00:00:00Z', '2026-08-31T00:00:00Z'),
       ($3, $11, NULL, $9, 'Rahul Sharma', 'pending', NULL, NULL),
       ($4, $7, NULL, $10, 'Other Tenant', 'active', '2026-02-01T00:00:00Z', NULL),
       ($5, $11, NULL, $10, 'Other Tenant', 'ended', '2025-01-01T00:00:00Z', '2025-06-01T00:00:00Z')`,
    [TEN.cur, TEN.old, TEN.pending, TEN.other, TEN.foreign, P_CUR, P_OLD, BED,
      USER.rahul, USER.other, P_FOREIGN],
  );
  await pg.db.query(
    `INSERT INTO invoices VALUES
       ($1, $5, $8, '2026-05-01', '2026-05-31', '2026-05-06', 6000, '2026-05-01T05:00:00Z'),
       ($2, $6, $9, '2026-10-01', '2026-10-31', '2026-10-06', 6500, '2026-10-01T05:00:00Z'),
       ($3, $6, $9, '2026-11-01', '2026-11-30', '2026-11-06', 9000, NULL),
       ($4, $7, $8, '2026-05-01', '2026-05-31', '2026-05-06', 7000, '2026-05-01T05:00:00Z')`,
    [INV.old, INV.cur, INV.draft, INV.other, TEN.old, TEN.cur, TEN.other, P_OLD, P_CUR],
  );
  await pg.db.query(
    `INSERT INTO payments (invoice_id, amount, method, note, paid_at) VALUES
       ($1, 3000, 'upi', 'owner note', '2026-05-10T04:00:00Z'),
       ($1, 3000, 'cash', NULL, '2026-05-20T04:00:00Z'),
       -- 30 Sep 20:00 UTC is 1 Oct 01:30 in Asia/Kolkata.
       ($2, 2000, 'upi', NULL, '2026-09-30T20:00:00Z'),
       ($3, 100, 'cash', NULL, '2026-11-02T04:00:00Z'),
       ($4, 7000, 'cash', NULL, '2026-05-12T04:00:00Z')`,
    [INV.old, INV.cur, INV.draft, INV.other],
  );

  const { authGuard, requireContext, requireRole } = await import(
    '../../shared/middleware/auth-guard.js'
  );
  const { TenantStatementController } = await import('./tenant-statement.controller.js');
  const { errorHandler } = await import('../../shared/middleware/error-handler.js');

  // Same middleware chain as tenant-portal.routes.ts.
  const c = new TenantStatementController();
  const router = express.Router();
  router.use(authGuard, requireContext, requireRole('tenant'));
  router.get('/stays', c.stays);
  router.get('/payment-history', c.paymentHistory);
  router.get('/payment-statement.pdf', c.statementPdf);

  const app = express();
  app.use('/v1/tenant-portal', router);
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

async function get(path: string, tok?: string) {
  const res = await fetch(`${baseUrl}${path}`, {
    headers: tok ? { authorization: `Bearer ${tok}` } : {},
  });
  return { status: res.status, body: (await res.json().catch(() => null)) as any };
}

describe('stays', () => {
  it('lists current and past stays of the caller only', async () => {
    const res = await get('/v1/tenant-portal/stays', TOKENS.rahul());
    expect(res.status).toBe(200);
    const stays = res.body.data;
    expect(stays.map((s: any) => s.tenancy_id)).toEqual([TEN.cur, TEN.old]);
    expect(stays[0]).toMatchObject({
      property_name: 'Sky Hostel',
      node_name: 'Bed 1',
      parent_node_name: 'Room 101',
      is_current: true,
      status: 'active',
    });
    expect(stays[1]).toMatchObject({ property_name: 'River PG', is_current: false, status: 'ended' });
  });
});

describe('payment history', () => {
  it('returns every actual payment across stays, drafts and other tenants excluded', async () => {
    const res = await get('/v1/tenant-portal/payment-history', TOKENS.rahul());
    expect(res.status).toBe(200);
    const { payments, summary } = res.body.data;
    expect(payments.map((p: any) => p.amount)).toEqual([2000, 3000, 3000]);
    expect(summary).toEqual({
      total_received: 8000,
      payment_count: 3,
      invoice_count: 2,
      current_outstanding: 4500,
    });
    expect(payments.some((p: any) => p.invoice_id === INV.other)).toBe(false);
    expect(payments.some((p: any) => p.invoice_id === INV.draft)).toBe(false);
    expect(payments[0]).not.toHaveProperty('note');
  });

  it('two payments on one invoice stay two transactions totalling the invoice', async () => {
    const res = await get(`/v1/tenant-portal/payment-history?propertyId=${P_OLD}`, TOKENS.rahul());
    expect(res.status).toBe(200);
    const { payments, summary } = res.body.data;
    expect(payments).toHaveLength(2);
    expect(payments.map((p: any) => p.amount)).toEqual([3000, 3000]);
    expect(payments.every((p: any) => p.invoice_total === 6000 && p.invoice_balance === 0)).toBe(true);
    expect(summary.total_received).toBe(6000);
    expect(summary.current_outstanding).toBe(0);
  });

  it('partial payment leaves the remaining balance outstanding', async () => {
    const res = await get(`/v1/tenant-portal/payment-history?propertyId=${P_CUR}`, TOKENS.rahul());
    const [p] = res.body.data.payments;
    expect(p).toMatchObject({ amount: 2000, invoice_total: 6500, invoice_balance: 4500 });
    expect(res.body.data.summary.current_outstanding).toBe(4500);
  });

  it('filters by the property-local payment date', async () => {
    const oct = await get('/v1/tenant-portal/payment-history?from=2026-10-01&to=2026-10-31', TOKENS.rahul());
    expect(oct.body.data.payments.map((p: any) => p.paid_on)).toEqual(['2026-10-01']);
    expect(oct.body.data.summary.total_received).toBe(2000);
    // Outstanding is current, not limited to the range.
    expect(oct.body.data.summary.current_outstanding).toBe(4500);

    const sep30 = await get('/v1/tenant-portal/payment-history?from=2026-09-30&to=2026-09-30', TOKENS.rahul());
    expect(sep30.body.data.payments).toEqual([]);
    expect(sep30.body.data.summary.total_received).toBe(0);
  });

  it('rejects invalid dates and ranges', async () => {
    for (const q of ['from=2026-10-31&to=2026-10-01', 'from=2026-02-30', 'to=yesterday']) {
      const res = await get(`/v1/tenant-portal/payment-history?${q}`, TOKENS.rahul());
      expect(res.status).toBe(400);
    }
  });

  it("never returns another tenant's records for a property id", async () => {
    for (const pid of [P_FOREIGN, 'not-a-uuid', '11000000-0000-4000-8000-00000000ffff']) {
      const res = await get(`/v1/tenant-portal/payment-history?propertyId=${pid}`, TOKENS.rahul());
      expect(res.status).toBe(404);
    }
    // Other tenant lives at Rahul's past property: they see only their own payment.
    const res = await get(`/v1/tenant-portal/payment-history?propertyId=${P_OLD}`, TOKENS.other());
    expect(res.status).toBe(200);
    expect(res.body.data.payments.map((p: any) => p.amount)).toEqual([7000]);
    // ...and cannot use Rahul's current property at all.
    const cross = await get(`/v1/tenant-portal/payment-history?propertyId=${P_CUR}`, TOKENS.other());
    expect(cross.status).toBe(404);
  });

  it('requires an authenticated, still-valid tenant context', async () => {
    expect((await get('/v1/tenant-portal/payment-history')).status).toBe(401);
    expect((await get('/v1/tenant-portal/payment-history', TOKENS.owner())).status).toBe(403);
    expect((await get('/v1/tenant-portal/payment-history', TOKENS.rahulEnded())).status).toBe(403);
  });
});

describe('statement pdf', () => {
  it('streams a PDF for the selection', async () => {
    const res = await fetch(
      `${baseUrl}/v1/tenant-portal/payment-statement.pdf?propertyId=${P_OLD}&token=${TOKENS.rahul()}`,
    );
    expect(res.status).toBe(200);
    expect(res.headers.get('content-type')).toContain('application/pdf');
    const bytes = Buffer.from(await res.arrayBuffer());
    expect(bytes.subarray(0, 5).toString()).toBe('%PDF-');
  });

  it('is not generated for an empty selection or a foreign property', async () => {
    const empty = await get(
      '/v1/tenant-portal/payment-statement.pdf?from=2020-01-01&to=2020-01-31',
      TOKENS.rahul(),
    );
    expect(empty.status).toBe(404);
    const foreign = await get(
      `/v1/tenant-portal/payment-statement.pdf?propertyId=${P_FOREIGN}`,
      TOKENS.rahul(),
    );
    expect(foreign.status).toBe(404);
  });
});

describe('statement content', () => {
  it('prints real dates, property, period, amounts and labelled outstanding', () => {
    const content = statementContent({
      holder: { name: 'Rahul Sharma', phone: '+919000000001' },
      scopeLabel: 'River PG',
      from: '2026-05-01',
      to: '2026-05-31',
      generatedOn: '2026-10-14',
      result: {
        filter: { propertyId: P_OLD, from: '2026-05-01', to: '2026-05-31' },
        summary: { total_received: 6000, payment_count: 2, invoice_count: 1, current_outstanding: 4500 },
        payments: [
          {
            id: 'a', amount: 3000, method: 'upi', paid_at: '', paid_on: '2026-05-20',
            invoice_id: INV.old, period_start: '2026-05-01', period_end: '2026-05-31',
            invoice_total: 6000, invoice_balance: 0, property_id: P_OLD,
            property_name: 'River PG', tenancy_id: TEN.old,
          },
        ],
      },
    });
    expect(content.details).toContainEqual(['Period', '1 May 2026 - 31 May 2026']);
    expect(content.details).toContainEqual(['Generated on', '14 Oct 2026']);
    expect(content.rows[0]).toEqual(['20 May 2026', 'River PG', 'May 2026', 'UPI', 'Rs. 3,000.00', 'Received']);
    expect(content.total).toBe('Rs. 6,000.00');
    expect(content.summary).toContainEqual([
      'Current outstanding balance (as of 14 Oct 2026)',
      'Rs. 4,500.00',
    ]);
  });

  it('paginates long statements with page numbers', async () => {
    const payments = Array.from({ length: 120 }, (_, i) => ({
      id: String(i), amount: 100, method: 'cash', paid_at: '', paid_on: '2026-05-01',
      invoice_id: 'x', period_start: '2026-05-01', period_end: '2026-05-31',
      invoice_total: 100, invoice_balance: 0, property_id: P_OLD,
      property_name: 'River PG', tenancy_id: TEN.old,
    }));
    const doc = renderStatementPdf({
      holder: { name: 'Rahul', phone: null },
      scopeLabel: 'River PG',
      from: null,
      to: null,
      generatedOn: '2026-10-14',
      result: {
        filter: { propertyId: null, from: null, to: null },
        summary: { total_received: 12000, payment_count: 120, invoice_count: 1, current_outstanding: 0 },
        payments,
      },
    });
    const chunks: Buffer[] = [];
    await new Promise<void>((resolve) => {
      doc.on('data', (c: Buffer) => chunks.push(c));
      doc.on('end', resolve);
    });
    const pdf = Buffer.concat(chunks).toString('latin1');
    expect(pdf.startsWith('%PDF-')).toBe(true);
    // ~35 rows per page: several pages, and the footer must not spill onto blank ones.
    const pages = pdf.match(/\/Type \/Page\b/g)?.length ?? 0;
    expect(pages).toBeGreaterThanOrEqual(3);
    expect(pages).toBeLessThanOrEqual(5);
  });
});
