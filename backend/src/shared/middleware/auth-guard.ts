// shared/middleware/auth-guard.ts
import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { env } from '@config/env';

export interface AuthedRequest extends Request {
  userId?: string;
  ctxType?: 'organization' | 'tenancy';
  ctxId?: string;
  ctxRole?: string;
  ctxPropertyId?: string | null;
}

export function authGuard(req: AuthedRequest, res: Response, next: NextFunction) {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Missing bearer token' });
  }
  try {
    const payload = jwt.verify(header.slice(7), env.jwtAccessSecret) as any;
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

// For manager/staff contexts, restricts access to only their assigned property.
// Owner/admin contexts (whole-organization) always pass.
export function requirePropertyAccess(req: AuthedRequest, res: Response, next: NextFunction) {
  const requestedPropertyId = req.params.propertyId;
  if (req.ctxRole === 'owner' || req.ctxRole === 'admin') {
    return next(); // org-wide access
  }
  if (req.ctxPropertyId && req.ctxPropertyId === requestedPropertyId) {
    return next(); // manager/staff scoped correctly
  }
  return res.status(403).json({ error: 'You do not have access to this property.' });
}