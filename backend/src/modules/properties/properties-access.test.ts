// Property list/read/create are scoped to the selected workspace; the client
// can never name another organization.
import type { AddressInfo } from 'net';
import express, { type NextFunction, type Response } from 'express';
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';

const calls = vi.hoisted(() => ({ list: [] as string[], create: [] as any[] }));
const ORG_A = 'e1000000-0000-4000-8000-000000000000';
const ORG_B = 'e2000000-0000-4000-8000-000000000000';
const PROP_A = 'e3000000-0000-4000-8000-000000000000';
const PROP_B = 'e4000000-0000-4000-8000-000000000000';

vi.mock('@config/env', () => ({ env: { jwtAccessSecret: 'x' } }));

vi.mock('@config/db', () => ({
  query: async (sql: string, params: unknown[]) => {
    if (sql.includes('FROM properties WHERE id')) {
      return params[0] === PROP_A ? [{ organization_id: ORG_A }]
        : params[0] === PROP_B ? [{ organization_id: ORG_B }] : [];
    }
    if (sql.includes('FROM property_staff_assignments')) {
      return params[0] === 'manager-1' && params[1] === PROP_A ? [{ role: 'manager' }] : [];
    }
    return [];
  },
}));

vi.mock('./properties.service', () => ({
  PropertiesService: class {
    async listForOrganization(orgId: string) {
      calls.list.push(orgId);
      return [{ id: `prop-of-${orgId}` }];
    }
    async getById(id: string) {
      return { id };
    }
    async create(input: any) {
      calls.create.push(input);
      return { id: 'new' };
    }
  },
}));

vi.mock('@shared/middleware/require-writable-property', () => ({
  requireWritableProperty: (_req: unknown, _res: unknown, next: NextFunction) => next(),
}));

import { PropertiesController } from './properties.controller';
import { requirePropertyAccess, type AuthedRequest } from '@shared/middleware/auth-guard';

const CONTEXTS: Record<string, Partial<AuthedRequest>> = {
  ownerA: { userId: 'owner-1', ctxType: 'organization', ctxId: ORG_A, ctxRole: 'owner', ctxPropertyId: null },
  managerA: { userId: 'manager-1', ctxType: 'organization', ctxId: PROP_A, ctxRole: 'manager', ctxPropertyId: PROP_A },
  removedManagerA: { userId: 'gone-1', ctxType: 'organization', ctxId: PROP_A, ctxRole: 'manager', ctxPropertyId: PROP_A },
  tenantA: { userId: 'tenant-1', ctxType: 'tenancy', ctxId: 'ten-1', ctxRole: 'tenant', ctxPropertyId: PROP_A },
};

let baseUrl = '';
let server: ReturnType<express.Express['listen']>;

beforeAll(async () => {
  const controller = new PropertiesController();
  const app = express();
  app.use(express.json());
  app.use((req: AuthedRequest, _res: Response, next: NextFunction) => {
    Object.assign(req, CONTEXTS[String(req.headers['x-ctx'])] ?? {});
    next();
  });
  app.get('/v1/properties', controller.list);
  app.get('/v1/properties/:propertyId', requirePropertyAccess, controller.getById);
  app.post('/v1/properties', controller.create);
  await new Promise<void>((resolve) => {
    server = app.listen(0, resolve);
  });
  baseUrl = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});

afterAll(() => {
  server.close();
});

const call = async (ctx: string, path: string, body?: unknown) => {
  const res = await fetch(`${baseUrl}${path}`, {
    method: body ? 'POST' : 'GET',
    headers: { 'x-ctx': ctx, 'content-type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, body: (await res.json()) as any };
};

describe('property list', () => {
  it("owners list only their own organization's properties, whatever they ask for", async () => {
    const res = await call('ownerA', `/v1/properties?organizationId=${ORG_B}`);
    expect(res.status).toBe(200);
    expect(calls.list).toEqual([ORG_A]);
  });

  it('a tenant cannot list properties of any organization', async () => {
    const res = await call('tenantA', `/v1/properties?organizationId=${ORG_B}`);
    expect(res.status).toBe(403);
    expect(calls.list).toEqual([ORG_A]);
  });

  it('a manager sees only the property they accepted; a removed one sees nothing', async () => {
    expect((await call('managerA', '/v1/properties')).body.data).toEqual([{ id: PROP_A }]);
    expect((await call('removedManagerA', '/v1/properties')).status).toBe(403);
  });
});

describe('property read', () => {
  it('is limited to properties the workspace can reach', async () => {
    expect((await call('ownerA', `/v1/properties/${PROP_A}`)).status).toBe(200);
    expect((await call('ownerA', `/v1/properties/${PROP_B}`)).status).toBe(403);
    expect((await call('tenantA', `/v1/properties/${PROP_A}`)).status).toBe(200);
    expect((await call('tenantA', `/v1/properties/${PROP_B}`)).status).toBe(403);
    expect((await call('managerA', `/v1/properties/${PROP_B}`)).status).toBe(403);
    expect((await call('removedManagerA', `/v1/properties/${PROP_A}`)).status).toBe(403);
  });
});

describe('property create', () => {
  it('only owners/admins, always into their own organization', async () => {
    expect(
      (await call('tenantA', '/v1/properties', { organizationId: ORG_B, propertyTypeKey: 'pg' })).status,
    ).toBe(403);
    expect(
      (await call('managerA', '/v1/properties', { organizationId: ORG_A, propertyTypeKey: 'pg' })).status,
    ).toBe(403);
    const res = await call('ownerA', '/v1/properties', { organizationId: ORG_B, propertyTypeKey: 'pg' });
    expect(res.status).toBe(201);
    expect(calls.create).toEqual([expect.objectContaining({ organizationId: ORG_A })]);
  });
});
