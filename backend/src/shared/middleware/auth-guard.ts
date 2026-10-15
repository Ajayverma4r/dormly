// shared/middleware/auth-guard.ts
import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { env } from '@config/env';
import { query } from '@config/db';

export interface AuthedRequest extends Request {
  userId?: string;
  ctxType?: 'organization' | 'tenancy';
  ctxId?: string;
  ctxRole?: string;
  ctxPropertyId?: string | null;
}

export function authGuard(req: AuthedRequest, res: Response, next: NextFunction) {
  const header = req.headers.authorization;
  // Reports/downloads open as plain links (browser can't attach custom headers),
  // so we also accept the token as a query param for exactly that case.
  const token = header?.startsWith('Bearer ') ? header.slice(7) : (req.query.token as string | undefined);
  if (!token) {
    return res.status(401).json({ error: 'Missing bearer token' });
  }
  try {
    const payload = jwt.verify(token, env.jwtAccessSecret) as any;
    
    req.userId = payload.sub;
    req.ctxType = payload.ctxType;
    req.ctxId = payload.ctxId;
    req.ctxRole = payload.ctxRole;
    req.ctxPropertyId = payload.ctxPropertyId;
    next();
  } catch {
    res.status(401).json({ error: 'Invalid or expired token' });
  }
}

export type TokenContext = Required<
  Pick<AuthedRequest, 'userId' | 'ctxType' | 'ctxId' | 'ctxRole'>
> & { ctxPropertyId: string | null };

/** Whether the token's workspace is still one the server would list for the user. */
export type ContextMembershipLookup = (ctx: TokenContext) => Promise<boolean>;

// Mirrors ContextService.listContextsForUser: owner/admin membership, accepted
// manager/staff assignment, or active tenancy — each with the token's role.
export const contextStillValid: ContextMembershipLookup = async (ctx) => {
  if (!UUID_RE.test(ctx.userId) || !UUID_RE.test(ctx.ctxId)) return false;
  if (ctx.ctxType === 'organization' && (ctx.ctxRole === 'owner' || ctx.ctxRole === 'admin')) {
    const rows = await query(
      `SELECT 1 FROM memberships
       WHERE user_id = $1::uuid AND organization_id = $2::uuid AND role::text = $3`,
      [ctx.userId, ctx.ctxId, ctx.ctxRole],
    );
    return rows.length > 0;
  }
  if (ctx.ctxType === 'organization' && (ctx.ctxRole === 'manager' || ctx.ctxRole === 'staff')) {
    if (ctx.ctxPropertyId !== ctx.ctxId) return false;
    const rows = await query(
      `SELECT 1 FROM property_staff_assignments
       WHERE user_id = $1::uuid AND property_id = $2::uuid AND role = $3 AND status = 'active'`,
      [ctx.userId, ctx.ctxId, ctx.ctxRole],
    );
    return rows.length > 0;
  }
  if (ctx.ctxType === 'tenancy' && ctx.ctxRole === 'tenant') {
    if (!ctx.ctxPropertyId || !UUID_RE.test(ctx.ctxPropertyId)) return false;
    const rows = await query(
      `SELECT 1 FROM tenancies
       WHERE id = $1::uuid AND user_id = $2::uuid AND property_id = $3::uuid
         AND status = 'active'`,
      [ctx.ctxId, ctx.userId, ctx.ctxPropertyId],
    );
    return rows.length > 0;
  }
  return false;
};

const STALE_CONTEXT = {
  error: 'Your access to this workspace has changed. Please sign in again.',
};

// Use after authGuard on routes that require an already-selected context
// (i.e. everything except /v1/auth/contexts and /v1/auth/contexts/select).
// The token's workspace is rechecked on every request, so a removed admin,
// staff member or ended tenancy loses access before the token expires.
export function contextGuard(lookup: ContextMembershipLookup = contextStillValid) {
  return async (req: AuthedRequest, res: Response, next: NextFunction) => {
    if (!req.ctxType || !req.ctxId) {
      return res.status(401).json({ error: 'Select a context before calling this endpoint.' });
    }
    if (!req.userId || !req.ctxRole) return res.status(403).json(STALE_CONTEXT);
    try {
      const valid = await lookup({
        userId: req.userId,
        ctxType: req.ctxType,
        ctxId: req.ctxId,
        ctxRole: req.ctxRole,
        ctxPropertyId: req.ctxPropertyId ?? null,
      });
      if (!valid) return res.status(403).json(STALE_CONTEXT);
    } catch (err) {
      return next(err);
    }
    next();
  };
}

export const requireContext = contextGuard();

// Restricts a route to specific roles within the current context.
export function requireRole(...allowedRoles: string[]) {
  return (req: AuthedRequest, res: Response, next: NextFunction) => {
    if (!req.ctxRole || !allowedRoles.includes(req.ctxRole)) {
      return res.status(403).json({ error: `Requires one of roles: ${allowedRoles.join(', ')}` });
    }
    next();
  };
}

// Tenants also pass requirePropertyAccess for their own property, so
// property routes that are not tenant-aware must use one of these.
export const PROPERTY_TEAM_ROLES = ['owner', 'admin', 'manager', 'staff'] as const;
export const PROPERTY_MANAGER_ROLES = ['owner', 'admin', 'manager'] as const;

/** Owner, admin, manager or staff of the property. */
export const requirePropertyTeam = requireRole(...PROPERTY_TEAM_ROLES);
/** Owner, admin or manager of the property. */
export const requirePropertyManager = requireRole(...PROPERTY_MANAGER_ROLES);

/** Organization that owns a property, or null when it does not exist. */
export type PropertyOrganizationLookup = (propertyId: string) => Promise<string | null>;

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const defaultPropertyOrganization: PropertyOrganizationLookup = async (propertyId) => {
  const rows = await query<{ organization_id: string }>(
    `SELECT organization_id FROM properties WHERE id = $1::uuid`,
    [propertyId],
  );
  return rows[0]?.organization_id ?? null;
};

/** Role of the user's accepted (active) assignment on a property, or null. */
export type StaffAssignmentLookup = (userId: string, propertyId: string) => Promise<string | null>;

export const activeStaffRole: StaffAssignmentLookup = async (userId, propertyId) => {
  const rows = await query<{ role: string }>(
    `SELECT role FROM property_staff_assignments
     WHERE user_id = $1 AND property_id = $2::uuid AND status = 'active'`,
    [userId, propertyId],
  );
  return rows[0]?.role ?? null;
};

const NO_PROPERTY_ACCESS = { error: 'You do not have access to this property.' };

// Owner/admin contexts reach every property of their own organization.
// Manager/staff/tenant contexts reach only the property they are bound to;
// manager/staff tokens are rechecked against an accepted assignment with the
// same role, so removal or a pending role change takes effect immediately.
export function propertyAccessGuard(
  lookup: PropertyOrganizationLookup = defaultPropertyOrganization,
  staffLookup: StaffAssignmentLookup = activeStaffRole,
) {
  return async (req: AuthedRequest, res: Response, next: NextFunction) => {
    const requestedPropertyId = req.params.propertyId;
    if (req.ctxRole === 'owner' || req.ctxRole === 'admin') {
      if (
        req.ctxType !== 'organization' ||
        !req.ctxId ||
        !UUID_RE.test(String(requestedPropertyId ?? ''))
      ) {
        return res.status(403).json(NO_PROPERTY_ACCESS);
      }
      try {
        const organizationId = await lookup(requestedPropertyId);
        if (organizationId && organizationId === req.ctxId) return next();
        return res.status(403).json(NO_PROPERTY_ACCESS);
      } catch (err) {
        return next(err);
      }
    }
    if (!req.ctxPropertyId || req.ctxPropertyId !== requestedPropertyId) {
      return res.status(403).json(NO_PROPERTY_ACCESS);
    }
    if (req.ctxRole === 'manager' || req.ctxRole === 'staff') {
      if (!req.userId || !UUID_RE.test(String(requestedPropertyId))) {
        return res.status(403).json(NO_PROPERTY_ACCESS);
      }
      try {
        const role = await staffLookup(req.userId, requestedPropertyId);
        if (role !== req.ctxRole) return res.status(403).json(NO_PROPERTY_ACCESS);
      } catch (err) {
        return next(err);
      }
    }
    return next();
  };
}

export const requirePropertyAccess = propertyAccessGuard();

// Organization-wide endpoints: only that organization's owner/admin contexts.
export function requireOrganizationAccess(req: AuthedRequest, res: Response, next: NextFunction) {
  if (
    req.ctxType === 'organization' &&
    (req.ctxRole === 'owner' || req.ctxRole === 'admin') &&
    req.ctxId &&
    req.ctxId === req.params.organizationId
  ) {
    return next();
  }
  return res.status(403).json({ error: 'You do not have access to this organization.' });
}