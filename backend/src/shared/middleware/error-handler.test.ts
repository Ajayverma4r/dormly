import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { DatabaseError } from 'pg';
import { z } from 'zod';

vi.mock('@config/db', () => ({
  query: vi.fn(async () => {
    throw new Error('database must not be used by error-handler tests');
  }),
  withTransaction: vi.fn(async () => {
    throw new Error('database must not be used by error-handler tests');
  }),
}));

import { errorHandler } from './error-handler';
import { InvoiceConflictError, InvoiceLockedError, MoveInDateLockedError } from '@modules/billing/billing.service';
import { MeterAccessError } from '@modules/meter-readings/meter-access';
import { SubscriptionRequiredError } from '@shared/property-monetization';
import { FeatureNotAllowedError } from '@modules/tenant-portal/property-type-access';

function run(err: unknown) {
  const res: any = {
    statusCode: 0,
    body: undefined as unknown,
    status(code: number) {
      this.statusCode = code;
      return this;
    },
    json(body: unknown) {
      this.body = body;
      return this;
    },
  };
  errorHandler(err, {} as any, res, () => undefined);
  return { status: res.statusCode as number, body: res.body as Record<string, unknown> };
}

function pgError(code: string, message: string): DatabaseError {
  const err = new DatabaseError(message, message.length, 'error');
  err.code = code;
  err.severity = 'ERROR';
  err.detail = 'Key (phone)=(+919876543210) already exists.';
  err.table = 'tenants';
  err.constraint = 'tenants_phone_key';
  return err;
}

describe('errorHandler', () => {
  let consoleError: ReturnType<typeof vi.spyOn>;
  beforeEach(() => {
    consoleError = vi.spyOn(console, 'error').mockImplementation(() => undefined);
  });
  afterEach(() => {
    consoleError.mockRestore();
  });

  describe('intentional API messages keep their status and text', () => {
    it('plain Error business message → 400 with the message', () => {
      const r = run(new Error('Meter reading already submitted for this month.'));
      expect(r).toEqual({ status: 400, body: { error: 'Meter reading already submitted for this month.' } });
    });

    it('ZodError → 400 validation details', () => {
      const parsed = z.object({ amount: z.number() }).safeParse({ amount: 'x' });
      if (parsed.success) throw new Error('expected zod failure');
      const r = run(parsed.error);
      expect(r.status).toBe(400);
      expect(r.body.error).toBe('Validation failed');
      expect(Array.isArray(r.body.details)).toBe(true);
    });

    it('MeterAccessError → 404 Not found', () => {
      expect(run(new MeterAccessError())).toEqual({ status: 404, body: { error: 'Not found' } });
    });

    it('InvoiceLockedError keeps 400 for identity lock and 409 otherwise', () => {
      expect(run(new InvoiceLockedError('Identity locked', 'invoice_identity_locked'))).toEqual({
        status: 400,
        body: { error: 'Identity locked', code: 'invoice_identity_locked' },
      });
      expect(run(new InvoiceLockedError('Already paid', 'invoice_paid'))).toEqual({
        status: 409,
        body: { error: 'Already paid', code: 'invoice_paid' },
      });
    });

    it('InvoiceConflictError → 409 with invoice id', () => {
      const r = run(new InvoiceConflictError('Invoice exists', 'inv-1', true));
      expect(r.status).toBe(409);
      expect(r.body).toMatchObject({ error: 'Invoice exists', code: 'invoice_exists', invoiceId: 'inv-1', isDraft: true });
    });

    it('MoveInDateLockedError → 409', () => {
      const r = run(new MoveInDateLockedError('Move-in locked'));
      expect(r.status).toBe(409);
      expect(r.body.error).toBe('Move-in locked');
    });

    it('SubscriptionRequiredError → 403 upgrade response', () => {
      const r = run(new SubscriptionRequiredError());
      expect(r.status).toBe(403);
      expect(r.body).toMatchObject({ code: 'SUBSCRIPTION_REQUIRED', upgradeRequired: true });
    });

    it('FeatureNotAllowedError → 403', () => {
      const r = run(new FeatureNotAllowedError('rooms' as any, 'rental' as any));
      expect(r.status).toBe(403);
      expect(r.body.code).toBe('FEATURE_NOT_ALLOWED');
    });

    it('MulterError-style errors keep their message', () => {
      const err = Object.assign(new Error('File too large'), { name: 'MulterError', code: 'LIMIT_FILE_SIZE' });
      expect(run(err)).toEqual({ status: 400, body: { error: 'File too large' } });
    });
  });

  describe('database errors never leak driver text', () => {
    it.each([
      ['23505', 'This record already exists.'],
      ['22P02', 'Invalid value in request.'],
      ['23503', 'A related record was not found or is still in use.'],
      ['22007', 'Invalid date in request.'],
    ])('SQLSTATE %s → 400 with fixed message', (code, message) => {
      const r = run(pgError(code, 'duplicate key value violates unique constraint "tenants_phone_key"'));
      expect(r).toEqual({ status: 400, body: { error: message } });
      expect(JSON.stringify(r.body)).not.toMatch(/tenants|phone|constraint|9876/);
    });

    it('other SQLSTATE (undefined table) → 500 generic', () => {
      const r = run(pgError('42P01', 'relation "invoices_archive" does not exist'));
      expect(r).toEqual({ status: 500, body: { error: 'Internal server error' } });
    });

    it('duck-typed pg error without the DatabaseError class → handled the same', () => {
      const err = Object.assign(new Error('column "foo" does not exist'), { code: '42703', severity: 'ERROR' });
      expect(run(err)).toEqual({ status: 500, body: { error: 'Internal server error' } });
    });
  });

  describe('infrastructure and runtime faults → 500 generic', () => {
    it.each([
      ['ECONNREFUSED', Object.assign(new Error('connect ECONNREFUSED 10.0.0.5:5432'), { code: 'ECONNREFUSED', syscall: 'connect', errno: -111 })],
      ['pool connection terminated', new Error('Connection terminated unexpectedly')],
      ['pool timeout', new Error('timeout exceeded when trying to connect')],
      ['TypeError', new TypeError("Cannot read properties of undefined (reading 'id')")],
      ['ReferenceError', new ReferenceError('foo is not defined')],
      ['axios', Object.assign(new Error('Request failed with status code 401'), { isAxiosError: true })],
    ])('%s', (_label, err) => {
      expect(run(err)).toEqual({ status: 500, body: { error: 'Internal server error' } });
    });

    it('non-Error thrown values → 500 generic', () => {
      expect(run('boom')).toEqual({ status: 500, body: { error: 'Internal server error' } });
    });
  });

  describe('body-parser errors', () => {
    it('malformed JSON → 400 without parser text', () => {
      const err = Object.assign(new SyntaxError('Unexpected token } in JSON at position 12'), {
        type: 'entity.parse.failed',
        status: 400,
      });
      expect(run(err)).toEqual({ status: 400, body: { error: 'Malformed request body.' } });
    });

    it('payload too large → 413', () => {
      const err = Object.assign(new Error('request entity too large'), { type: 'entity.too.large', status: 413 });
      expect(run(err)).toEqual({ status: 413, body: { error: 'Request body is too large.' } });
    });
  });
});
