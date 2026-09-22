// modules/mess-menu/mess-menu.controller.ts
import { Response, NextFunction } from 'express';
import { z } from 'zod';
import { MessMenuService } from './mess-menu.service';
import { AuthedRequest } from '@shared/middleware/auth-guard';
import { TenantPortalService } from '@modules/tenant-portal/tenant-portal.service';
import { assertFeatureAllowed } from '@modules/tenant-portal/property-type-access';

const service = new MessMenuService();
const tenantPortal = new TenantPortalService();

const daySchema = z.object({
  dayOfWeek: z.number().int().min(1).max(7),
  breakfast: z.string(),
  lunch: z.string(),
  dinner: z.string(),
});

export class MessMenuController {
  list = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      res.json({ data: await service.listByProperty(req.params.propertyId) });
    } catch (err) {
      next(err);
    }
  };

  upsertDay = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const body = daySchema.parse(req.body);
      const row = await service.upsertDay(
        req.params.propertyId,
        body.dayOfWeek,
        body,
        req.userId!,
      );
      res.json({ data: row });
    } catch (err) {
      next(err);
    }
  };

  upsertWeek = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const body = z.object({ days: z.array(daySchema).min(1) }).parse(req.body);
      const rows = await service.upsertWeek(
        req.params.propertyId,
        body.days,
        req.userId!,
      );
      res.json({ data: rows });
    } catch (err) {
      next(err);
    }
  };

  /** Tenant: menu for their active tenancy property only. */
  myMenu = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const tenancy = await tenantPortal.getMyTenancy(req.ctxId!);
      if (!tenancy) return res.status(404).json({ error: 'No active tenancy' });
      assertFeatureAllowed(tenancy, 'mess_menu');
      res.json({
        data: await service.listByProperty(String(tenancy.property_id)),
      });
    } catch (err) {
      next(err);
    }
  };
}
