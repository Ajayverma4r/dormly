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

// Use after authGuard on routes that require an already-selected context
// (i.e. everything except /v1/auth/contexts and /v1/auth/contexts/select).
export function requireContext(req: AuthedRequest, res: Response, next: NextFunction) {
  if (!req.ctxType || !req.ctxId) {
    return res.status(401).json({ error: 'Select a context before calling this endpoint.' });
  }
  next();
}

// Restricts a route to specific roles within the current context.
export function requireRole(...allowedRoles: string[]) {
  return (req: AuthedRequest, res: Response, next: NextFunction) => {
    if (!req.ctxRole || !allowedRoles.includes(req.ctxRole)) {
      return res.status(403).json({ error: `Requires one of roles: ${allowedRoles.join(', ')}` });
    }
    next();
  };
}

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

const NO_PROPERTY_ACCESS = { error: 'You do not have access to this property.' };

// Owner/admin contexts reach every property of their own organization.
// Manager/staff/tenant contexts reach only the property they are bound to.
export function propertyAccessGuard(
  lookup: PropertyOrganizationLookup = defaultPropertyOrganization,
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
    if (req.ctxPropertyId && req.ctxPropertyId === requestedPropertyId) {
      return next();
    }
    return res.status(403).json(NO_PROPERTY_ACCESS);
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