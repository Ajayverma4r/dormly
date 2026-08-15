// shared/middleware/entitlement.ts
//
// Feature-gate middleware. Import these instead of writing raw plan checks.
//
// Usage:
//   import { requireFeature, requireQuota } from '@shared/middleware/entitlement';
//
//   // Boolean gate — blocks if feature flag is false
//   router.post('/reports/pdf', requireFeature('can_export_pdf'), controller.exportPdf);
//
//   // Quota gate — blocks CREATE when the org is at or over its limit
//   router.post('/properties', requireQuota('max_properties', countOrgProperties), controller.create);
//
// The count function receives the full AuthedRequest so it can access params/body as needed.

import { Response, NextFunction } from 'express';
import { AuthedRequest } from '@shared/middleware/auth-guard';
import { EntitlementService } from '@modules/subscriptions/entitlement.service';

const entitlementService = new EntitlementService();

/**
 * Blocks the request with 403 if the organization's active plan does not
 * grant the specified boolean feature.
 *
 * Must be used after authGuard + requireContext.
 */
export function requireFeature(featureKey: string) {
  return async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      if (req.ctxType !== 'organization' || !req.ctxId) {
        return res.status(403).json({ error: 'Organization context required.' });
      }

      const allowed = await entitlementService.checkBoolFeature(req.ctxId, featureKey);
      if (!allowed) {
        return res.status(403).json({
          error: 'Your current plan does not include this feature.',
          feature: featureKey,
          upgradeRequired: true,
        });
      }

      next();
    } catch (err) {
      next(err);
    }
  };
}

/**
 * Blocks resource-creation requests once the organization has reached its
 * plan quota for a given resource type.
 *
 * @param quotaKey     - Feature key to read from org_active_entitlements (e.g. 'max_properties').
 * @param getCountFn   - Async function that returns the org's CURRENT count of that resource.
 *
 * Quota semantics:
 *   -1  → unlimited, always passes
 *    0  → blocked (feature not on plan)
 *   >0  → blocked if currentCount >= quota
 *
 * Graceful downgrade: even if status is 'expired', existing resources are
 * readable. Apply this middleware only to POST/creation routes, not GET routes.
 */
export function requireQuota(
  quotaKey: string,
  getCountFn: (req: AuthedRequest) => Promise<number>,
) {
  return async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      if (req.ctxType !== 'organization' || !req.ctxId) {
        return res.status(403).json({ error: 'Organization context required.' });
      }

      const quota = await entitlementService.checkQuota(req.ctxId, quotaKey);

      if (quota === -1) return next(); // unlimited — skip count query

      const currentCount = await getCountFn(req);

      if (currentCount >= quota) {
        return res.status(403).json({
          error: 'You have reached the limit for your current plan.',
          quota: quotaKey,
          limit: quota,
          current: currentCount,
          upgradeRequired: true,
        });
      }

      next();
    } catch (err) {
      next(err);
    }
  };
}
