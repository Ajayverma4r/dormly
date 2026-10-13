import type { AddressInfo } from 'net';
import express from 'express';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import {
  scopeParamToProperty,
  type RecordPropertyLookup,
} from './property-scope';

const PROPERTY_A = '11111111-1111-1111-1111-111111111111';
const PROPERTY_B = '22222222-2222-2222-2222-222222222222';
const INVOICE_A = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const INVOICE_B = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const TENANCY_A = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

const owners: Record<string, string> = {
  [INVOICE_A]: PROPERTY_A,
  [INVOICE_B]: PROPERTY_B,
  [TENANCY_A]: PROPERTY_A,
};
const calls: string[] = [];
const lookup: RecordPropertyLookup = async (table, id, propertyId) => {
  calls.push(`${table}:${id}`);
  return owners[id] === propertyId;
};

let baseUrl = '';
let server: ReturnType<express.Express['listen']>;

beforeAll(async () => {
  const router = express.Router({ mergeParams: true });
  router.param('invoiceId', scopeParamToProperty('invoices', lookup));
  router.param('tenancyId', scopeParamToProperty('tenancies', lookup));
  router.get('/invoices/:invoiceId', (req, res) =>
    res.json({ id: req.params.invoiceId }),
  );
  router.post('/invoices/:invoiceId/payments', (_req, res) =>
    res.json({ paid: true }),
  );
  router.patch('/tenancies/:tenancyId', (_req, res) => res.json({ ok: true }));

  const app = express();
  app.use('/v1/properties/:propertyId/billing', router);
  await new Promise<void>((resolve) => {
    server = app.listen(0, resolve);
  });
  baseUrl = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});

afterAll(() => {
  server.close();
});

const url = (propertyId: string, rest: string) =>
  `${baseUrl}/v1/properties/${propertyId}/billing${rest}`;

describe('scopeParamToProperty', () => {
  it('allows a record that belongs to the URL property', async () => {
    const res = await fetch(url(PROPERTY_A, `/invoices/${INVOICE_A}`));
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ id: INVOICE_A });
  });

  it("404s another property's invoice instead of exposing it", async () => {
    const res = await fetch(url(PROPERTY_A, `/invoices/${INVOICE_B}`));
    expect(res.status).toBe(404);
    expect(await res.json()).toEqual({ error: 'Not found' });
  });

  it("blocks recording a payment on another property's invoice", async () => {
    const res = await fetch(url(PROPERTY_A, `/invoices/${INVOICE_B}/payments`), {
      method: 'POST',
    });
    expect(res.status).toBe(404);
  });

  it("blocks editing another property's tenancy", async () => {
    const res = await fetch(url(PROPERTY_B, `/tenancies/${TENANCY_A}`), {
      method: 'PATCH',
    });
    expect(res.status).toBe(404);
  });

  it('rejects malformed ids without querying the database', async () => {
    calls.length = 0;
    const res = await fetch(url(PROPERTY_A, '/invoices/not-a-uuid'));
    expect(res.status).toBe(404);
    expect(calls).toEqual([]);
  });
});

describe('route registration', () => {
  it('billing and tenancy routers scope every record id param', async () => {
    process.env.DATABASE_URL ??= 'postgres://test:test@127.0.0.1:1/test';
    process.env.JWT_ACCESS_SECRET ??= 'test';
    process.env.JWT_REFRESH_SECRET ??= 'test';
    process.env.RAZORPAY_KEY_ID ??= 'rzp_test_x';
    process.env.RAZORPAY_KEY_SECRET ??= 'test';
    process.env.RAZORPAY_WEBHOOK_SECRET ??= 'test';

    const { billingRouter } = await import('../../modules/billing/billing.routes.js');
    const { tenancyRouter } = await import('../../modules/tenancies/tenancy.routes.js');
    const billingParams = (billingRouter as any).params as Record<string, unknown[]>;
    const tenancyParams = (tenancyRouter as any).params as Record<string, unknown[]>;

    expect(billingParams.invoiceId).toHaveLength(1);
    expect(billingParams.tenancyId).toHaveLength(1);
    expect(billingParams.chargeTypeId).toHaveLength(1);
    expect(tenancyParams.tenancyId).toHaveLength(1);
  });
});
