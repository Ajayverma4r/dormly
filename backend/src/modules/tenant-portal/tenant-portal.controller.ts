// modules/tenant-portal/tenant-portal.controller.ts
import { Response, NextFunction } from 'express';
import { TenantPortalService } from './tenant-portal.service';
import { AuthedRequest } from '@shared/middleware/auth-guard';

const service = new TenantPortalService();

export class TenantPortalController {
  getMe = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const tenancy = await service.getMyTenancy(req.ctxId!);
      if (!tenancy) {
        return res.status(404).json({ error: 'Tenancy not found' });
      }
      res.json({ data: tenancy });
    } catch (err) { next(err); }
  };
}