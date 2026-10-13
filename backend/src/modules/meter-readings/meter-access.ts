// modules/meter-readings/meter-access.ts
//
// Who may read or record meter readings for which unit. Unit and tenancy ids
// from the client are always checked against the database.

import { query } from '@config/db';
import type { AuthedRequest } from '@shared/middleware/auth-guard';

/** Unknown, foreign or unauthorized unit/tenancy. Mapped to a plain 404. */
export class MeterAccessError extends Error {
  constructor() {
    super('Not found');
  }
}

export type TenantMeterScope = {
  tenancyId: string;
  propertyId: string;
  unitId: string;
  property_type_key: string | null;
};

export function isTenantContext(req: AuthedRequest): boolean {
  return req.ctxType === 'tenancy' || req.ctxRole === 'tenant';
}

/**
 * The caller's own active tenancy, re-read from the database so an ended
 * tenancy or a token for someone else's tenancy grants nothing.
 */
export async function resolveTenantMeterScope(
  req: AuthedRequest,
): Promise<TenantMeterScope | null> {
  if (req.ctxType !== 'tenancy' || req.ctxRole !== 'tenant' || !req.ctxId || !req.userId) {
    return null;
  }
  const [row] = await query<{
    id: string;
    property_id: string;
    node_id: string;
    property_type_key: string | null;
  }>(
    `SELECT t.id, t.property_id, t.node_id, p.property_type_key
     FROM tenancies t
     JOIN properties p ON p.id = t.property_id
     WHERE t.id = $1::uuid AND t.user_id = $2::uuid AND t.status = 'active'`,
    [req.ctxId, req.userId],
  );
  if (!row) return null;
  return {
    tenancyId: row.id,
    propertyId: row.property_id,
    unitId: row.node_id,
    property_type_key: row.property_type_key,
  };
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * The unit must belong to the property, and a given tenancy must belong to
 * the same property and unit. Throws MeterAccessError otherwise.
 */
export async function assertMeterTarget(
  propertyId: string,
  unitId: string,
  tenancyId: string | null | undefined,
): Promise<void> {
  if (!UUID_RE.test(unitId) || (tenancyId != null && !UUID_RE.test(tenancyId))) {
    throw new MeterAccessError();
  }
  const [row] = await query<{ unit_ok: boolean; tenancy_ok: boolean }>(
    `SELECT
       EXISTS (SELECT 1 FROM hierarchy_nodes
               WHERE id = $1::uuid AND property_id = $2::uuid) AS unit_ok,
       ($3::uuid IS NULL OR EXISTS (
          SELECT 1 FROM tenancies
          WHERE id = $3::uuid AND property_id = $2::uuid AND node_id = $1::uuid
       )) AS tenancy_ok`,
    [unitId, propertyId, tenancyId ?? null],
  );
  if (!row?.unit_ok || !row.tenancy_ok) throw new MeterAccessError();
}
