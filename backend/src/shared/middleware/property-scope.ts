// shared/middleware/property-scope.ts
import type { NextFunction, Response } from 'express';
import { query } from '@config/db';
import type { AuthedRequest } from './auth-guard';

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export type PropertyScopedTable =
  | 'invoices'
  | 'tenancies'
  | 'charge_types'
  | 'complaints'
  | 'gate_passes';

export type RecordPropertyLookup = (
  table: PropertyScopedTable,
  id: string,
  propertyId: string,
) => Promise<boolean>;

const defaultLookup: RecordPropertyLookup = async (table, id, propertyId) => {
  const rows = await query<{ ok: number }>(
    `SELECT 1 AS ok FROM ${table} WHERE id = $1::uuid AND property_id = $2::uuid LIMIT 1`,
    [id, propertyId],
  );
  return rows.length > 0;
};

/**
 * router.param handler: the :param record must belong to :propertyId.
 * requirePropertyAccess only authorises the URL's property, so without this a
 * caller could reach another property's record by id. Mismatches return 404 so
 * record existence is not disclosed.
 */
export function scopeParamToProperty(
  table: PropertyScopedTable,
  lookup: RecordPropertyLookup = defaultLookup,
) {
  return async (
    req: AuthedRequest,
    res: Response,
    next: NextFunction,
    value: string,
  ) => {
    const propertyId = req.params.propertyId;
    if (!UUID_RE.test(String(value)) || !UUID_RE.test(String(propertyId ?? ''))) {
      return res.status(404).json({ error: 'Not found' });
    }
    try {
      if (!(await lookup(table, value, propertyId))) {
        return res.status(404).json({ error: 'Not found' });
      }
      next();
    } catch (err) {
      next(err);
    }
  };
}
