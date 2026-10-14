import type { AddressInfo } from 'net';
import express, { type NextFunction, type Response } from 'express';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import {
  propertyAccessGuard,
  requireOrganizationAccess,
  requireRole,
  type AuthedRequest,
  type PropertyOrganizationLookup,
  type StaffAssignmentLookup,
} from './auth-guard';

const ORG_A = 'a0000000-0000-4000-8000-000000000000';
const ORG_B = 'b0000000-0000-4000-8000-000000000000';
const PROP_A = 'a1000000-0000-4000-8000-000000000000';
const PROP_B = 'b1000000-0000-4000-8000-000000000000';

const propertyOrg: Record<string, string> = { [PROP_A]: ORG_A, [PROP_B]: ORG_B };
const lookup: PropertyOrganizationLookup = async (id) => propertyOrg[id] ?? null;

// Accepted assignments, keyed by user and property.
const activeAssignments: Record<string, string> = {
  [`manager-1:${PROP_A}`]: 'manager',
  [`staff-1:${PROP_A}`]: 'staff',
};
const staffLookup: StaffAssignmentLookup = async (userId, propertyId) =>
  activeAssignments[`${userId}:${propertyId}`] ?? null;

type Ctx = Pick<AuthedRequest, 'userId' | 'ctxType' | 'ctxId' | 'ctxRole' | 'ctxPropertyId'>;
const CONTEXTS: Record<string, Ctx> = {
  ownerA: { ctxType: 'organization', ctxId: ORG_A, ctxRole: 'owner', ctxPropertyId: null },
  adminB: { ctxType: 'organization', ctxId: ORG_B, ctxRole: 'admin', ctxPropertyId: null },
  managerA: {
    userId: 'manager-1', ctxType: 'organization', ctxId: PROP_A, ctxRole: 'manager', ctxPropertyId: PROP_A,
  },
  staffA: {
    userId: 'staff-1', ctxType: 'organization', ctxId: PROP_A, ctxRole: 'staff', ctxPropertyId: PROP_A,
  },
  // Token still says manager, but the assignment was removed or is pending.
  removedManagerA: {
    userId: 'removed-1', ctxType: 'organization', ctxId: PROP_A, ctxRole: 'manager', ctxPropertyId: PROP_A,
  },
  // Token says manager, but the accepted assignment is only staff.
  staffClaimingManagerA: {
    userId: 'staff-1', ctxType: 'organization', ctxId: PROP_A, ctxRole: 'manager', ctxPropertyId: PROP_A,
  },
  tenantA: { ctxType: 'tenancy', ctxId: 'tenancy-1', ctxRole: 'tenant', ctxPropertyId: PROP_A },
  // A forged owner role on a tenancy context must not get org-wide access.
  tenantClaimingOwner: { ctxType: 'tenancy', ctxId: ORG_A, ctxRole: 'owner', ctxPropertyId: PROP_A },
};

// Stands in for authGuard: the test picks the token's context by header.
function fakeAuth(req: AuthedRequest, _res: Response, next: NextFunction) {
  Object.assign(req, CONTEXTS[String(req.headers['x-ctx'])] ?? {});
  next();
}

let baseUrl = '';
let server: ReturnType<express.Express['listen']>;

beforeAll(async () => {
  const financial = express.Router({ mergeParams: true });
  financial.use(requireRole('owner', 'admin', 'manager'));
  financial.get('/', (_req, res) => res.json({ ok: true }));

  const open = express.Router({ mergeParams: true });
  open.get('/', (_req, res) => res.json({ ok: true }));

  const app = express();
  app.use(fakeAuth);
  const guard = propertyAccessGuard(lookup, staffLookup);
  app.use('/v1/properties/:propertyId/dashboard', guard, financial);
  app.use('/v1/properties/:propertyId/mess-menu', guard, open);
  app.get('/v1/organizations/:organizationId/analytics', requireOrganizationAccess, (_req, res) =>
    res.json({ ok: true }),
  );
  await new Promise<void>((resolve) => {
    server = app.listen(0, resolve);
  });
  baseUrl = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});

afterAll(() => {
  server.close();
});

const get = async (ctx: string, path: string) =>
  (await fetch(`${baseUrl}${path}`, { headers: { 'x-ctx': ctx } })).status;

describe('property access', () => {
  it("owners and admins reach only their own organization's properties", async () => {
    expect(await get('ownerA', `/v1/properties/${PROP_A}/dashboard`)).toBe(200);
    expect(await get('ownerA', `/v1/properties/${PROP_B}/dashboard`)).toBe(403);
    expect(await get('adminB', `/v1/properties/${PROP_B}/dashboard`)).toBe(200);
    expect(await get('adminB', `/v1/properties/${PROP_A}/dashboard`)).toBe(403);
  });

  it('rejects unknown or malformed property ids for owners', async () => {
    expect(await get('ownerA', '/v1/properties/c1000000-0000-4000-8000-000000000000/dashboard')).toBe(403);
    expect(await get('ownerA', '/v1/properties/not-a-uuid/dashboard')).toBe(403);
  });

  it('managers reach the dashboard of their assigned property only', async () => {
    expect(await get('managerA', `/v1/properties/${PROP_A}/dashboard`)).toBe(200);
    expect(await get('managerA', `/v1/properties/${PROP_B}/dashboard`)).toBe(403);
  });

  it('staff and tenants cannot read financial dashboards, but keep their own property routes', async () => {
    expect(await get('staffA', `/v1/properties/${PROP_A}/dashboard`)).toBe(403);
    expect(await get('tenantA', `/v1/properties/${PROP_A}/dashboard`)).toBe(403);
    expect(await get('tenantA', `/v1/properties/${PROP_A}/mess-menu`)).toBe(200);
    expect(await get('tenantA', `/v1/properties/${PROP_B}/mess-menu`)).toBe(403);
  });

  it('a removed or pending manager loses access even with an unexpired token', async () => {
    expect(await get('staffA', `/v1/properties/${PROP_A}/mess-menu`)).toBe(200);
    expect(await get('removedManagerA', `/v1/properties/${PROP_A}/mess-menu`)).toBe(403);
    expect(await get('removedManagerA', `/v1/properties/${PROP_A}/dashboard`)).toBe(403);
  });

  it('a token role must match the accepted assignment role', async () => {
    expect(await get('staffClaimingManagerA', `/v1/properties/${PROP_A}/dashboard`)).toBe(403);
    expect(await get('staffClaimingManagerA', `/v1/properties/${PROP_A}/mess-menu`)).toBe(403);
  });

  it('a tenancy context never gets organization-wide access', async () => {
    expect(await get('tenantClaimingOwner', `/v1/properties/${PROP_B}/mess-menu`)).toBe(403);
  });
});

describe('organization analytics access', () => {
  it("only that organization's owner/admin", async () => {
    expect(await get('ownerA', `/v1/organizations/${ORG_A}/analytics`)).toBe(200);
    expect(await get('ownerA', `/v1/organizations/${ORG_B}/analytics`)).toBe(403);
    expect(await get('adminB', `/v1/organizations/${ORG_B}/analytics`)).toBe(200);
    expect(await get('managerA', `/v1/organizations/${ORG_A}/analytics`)).toBe(403);
    expect(await get('tenantA', `/v1/organizations/${ORG_A}/analytics`)).toBe(403);
  });
});

describe('route registration', () => {
  it('dashboard and analytics routers carry the owner/admin/manager role guard', async () => {
    process.env.DATABASE_URL ??= 'postgres://test:test@127.0.0.1:1/test';
    process.env.JWT_ACCESS_SECRET ??= 'test';
    process.env.JWT_REFRESH_SECRET ??= 'test';
    process.env.RAZORPAY_KEY_ID ??= 'rzp_test_x';
    process.env.RAZORPAY_KEY_SECRET ??= 'test';
    process.env.RAZORPAY_WEBHOOK_SECRET ??= 'test';

    const { dashboardRouter } = await import('../../modules/dashboard/dashboard.routes.js');
    const { analyticsRouter } = await import('../../modules/analytics/analytics.routes.js');

    for (const router of [dashboardRouter, analyticsRouter]) {
      const app = express();
      app.use((req: AuthedRequest, _res, next) => {
        Object.assign(req, CONTEXTS.tenantA);
        next();
      });
      app.use('/x', router);
      const srv = app.listen(0);
      await new Promise((r) => srv.once('listening', r));
      const port = (srv.address() as AddressInfo).port;
      const status = (await fetch(`http://127.0.0.1:${port}/x`)).status;
      srv.close();
      expect(status).toBe(403);
    }
  });
});
