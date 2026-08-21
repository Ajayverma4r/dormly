// shared/middleware/require-writable-property.ts
//
// Blocks POST/PATCH/PUT/DELETE on properties that are frozen after
// subscription downgrade. GET/HEAD/OPTIONS always pass (zero data deletion /
// read-only access to locked properties).

import { Response, NextFunction } from 'express';
import { query } from '@config/db';
import { AuthedRequest } from './auth-guard';
import { assertCanManageProperty } from '@modules/properties/property-manageability';

const READ_METHODS = new Set(['GET', 'HEAD', 'OPTIONS']);

export async function requireWritableProperty(
  req: AuthedRequest,
  _res: Response,
  next: NextFunction,
) {
  if (READ_METHODS.has(req.method.toUpperCase())) {
    return next();
  }

  const propertyId = req.params.propertyId;
  if (!propertyId) {
    return next();
  }

  try {
    let organizationId =
      req.ctxType === 'organization' && req.ctxId ? req.ctxId : null;

    if (!organizationId) {
      const rows = await query<{ organization_id: string }>(
        `SELECT organization_id FROM properties WHERE id = $1`,
        [propertyId],
      );
      organizationId = rows[0]?.organization_id ?? null;
    }

    if (!organizationId) {
      return next();
    }

    await assertCanManageProperty(organizationId, propertyId);
    next();
  } catch (err) {
    next(err);
  }
}
