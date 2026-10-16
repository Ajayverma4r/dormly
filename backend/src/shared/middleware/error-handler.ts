// shared/middleware/error-handler.ts
import { Request, Response, NextFunction } from 'express';
import { ZodError } from 'zod';
import { StructureValidationError } from '@core/structure-engine/services/structure.service';
import { SubscriptionRequiredError } from '@shared/property-monetization';
import { FeatureNotAllowedError } from '@modules/tenant-portal/property-type-access';
import {
  InvoiceAmountRangeError,
  InvoiceConflictError,
  InvoiceLockedError,
  MoveInDateLockedError,
} from '@modules/billing/billing.service';
import { MeterAccessError } from '@modules/meter-readings/meter-access';
import { MeterReadingValidationError } from '@modules/meter-readings/meter-readings.service';
import { SearchRequestError } from '@modules/search/search.policy';

const INTERNAL_ERROR = 'Internal server error';

/**
 * Postgres errors caused by the request's data keep the historical 400, but
 * with a fixed message: driver text can name tables, columns, constraints and
 * values. Every other SQLSTATE is a server fault (500).
 */
const CLIENT_DATA_SQLSTATES: Record<string, string> = {
  '22P02': 'Invalid value in request.',
  '22007': 'Invalid date in request.',
  '22008': 'Invalid date in request.',
  '22003': 'A value in the request is out of range.',
  '22001': 'A value in the request is too long.',
  '23502': 'A required value is missing.',
  '23503': 'A related record was not found or is still in use.',
  '23505': 'This record already exists.',
  '23514': 'A value in the request is not allowed.',
};

/** pg / pg-pool failures that arrive as plain Error objects. */
const DRIVER_MESSAGE =
  /^(connection terminated|timeout exceeded when trying to connect|client has encountered a connection error|cannot use a pool after calling end|client was closed|connection timeout)/i;

type ErrorLike = Error & {
  code?: unknown;
  severity?: unknown;
  syscall?: unknown;
  errno?: unknown;
  type?: unknown;
  status?: unknown;
  expose?: unknown;
  isAxiosError?: unknown;
};

function isDatabaseError(err: ErrorLike): boolean {
  return (
    err.constructor?.name === 'DatabaseError' ||
    (typeof err.code === 'string' &&
      /^[0-9A-Z]{5}$/.test(err.code) &&
      typeof err.severity === 'string')
  );
}

function isSystemError(err: ErrorLike): boolean {
  return (
    typeof err.syscall === 'string' ||
    typeof err.errno === 'number' ||
    (typeof err.code === 'string' && /^E[A-Z0-9_]+$/.test(err.code)) ||
    err.isAxiosError === true ||
    DRIVER_MESSAGE.test(err.message)
  );
}

/** Express body-parser failures (malformed or oversized JSON). */
function isBodyParserError(err: ErrorLike): boolean {
  return typeof err.type === 'string' && err.type.startsWith('entity.');
}

/** JavaScript runtime faults are bugs, never user-facing input problems. */
function isRuntimeError(err: Error): boolean {
  return (
    err instanceof TypeError ||
    err instanceof ReferenceError ||
    err instanceof RangeError ||
    err instanceof EvalError ||
    err instanceof URIError ||
    err instanceof SyntaxError
  );
}

/**
 * Status and client-safe body for an error that has no explicit mapping, or
 * null when the error is an intentional API message (shown as before).
 */
export function unexpectedErrorResponse(
  err: Error,
): { status: number; body: { error: string } } | null {
  const e = err as ErrorLike;
  if (isBodyParserError(e)) {
    const status = typeof e.status === 'number' && e.status >= 400 && e.status < 500 ? e.status : 400;
    return {
      status,
      body: { error: status === 413 ? 'Request body is too large.' : 'Malformed request body.' },
    };
  }
  if (isDatabaseError(e)) {
    const clientMessage = CLIENT_DATA_SQLSTATES[String(e.code)];
    return clientMessage
      ? { status: 400, body: { error: clientMessage } }
      : { status: 500, body: { error: INTERNAL_ERROR } };
  }
  if (isSystemError(e) || isRuntimeError(err)) {
    return { status: 500, body: { error: INTERNAL_ERROR } };
  }
  return null;
}

export function errorHandler(err: unknown, req: Request, res: Response, _next: NextFunction) {
  if (err instanceof ZodError) {
    return res.status(400).json({ error: 'Validation failed', details: err.errors });
  }
  if (err instanceof FeatureNotAllowedError) {
    return res.status(403).json({
      error: err.message,
      code: err.code,
      feature: err.feature,
      propertyKind: err.kind,
    });
  }
  if (err instanceof InvoiceConflictError) {
    return res.status(409).json({
      error: err.message,
      code: err.code,
      invoiceId: err.invoiceId,
      isDraft: err.isDraft,
    });
  }
  if (err instanceof InvoiceLockedError) {
    const status = err.code === 'invoice_identity_locked' ? 400 : 409;
    return res.status(status).json({ error: err.message, code: err.code });
  }
  if (err instanceof MoveInDateLockedError) {
    return res.status(409).json({ error: err.message, code: err.code });
  }
  if (err instanceof InvoiceAmountRangeError) {
    return res.status(400).json({ error: err.message, code: err.code });
  }
  if (err instanceof MeterAccessError) {
    return res.status(404).json({ error: 'Not found' });
  }
  if (err instanceof MeterReadingValidationError) {
    return res.status(400).json({ error: err.message, code: err.code });
  }
  if (err instanceof SearchRequestError) {
    return res.status(err.status).json({ error: err.message, code: err.code });
  }
  if (err instanceof StructureValidationError) {
    return res.status(409).json({ error: err.message });
  }
  if (err instanceof SubscriptionRequiredError) {
    return res.status(err.statusCode).json({
      error: err.message,
      code: err.code,
      upgradeRequired: true,
    });
  }
  if (err instanceof Error) {
    // eslint-disable-next-line no-console
    console.error(err);
    const unexpected = unexpectedErrorResponse(err);
    if (unexpected) return res.status(unexpected.status).json(unexpected.body);
    // Services throw plain Error for business-rule messages meant for the user.
    return res.status(400).json({ error: err.message });
  }
  res.status(500).json({ error: INTERNAL_ERROR });
}
