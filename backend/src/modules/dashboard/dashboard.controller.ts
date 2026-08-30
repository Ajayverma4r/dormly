// modules/dashboard/dashboard.controller.ts

import { Response, NextFunction } from 'express';
import { AuthedRequest } from '@shared/middleware/auth-guard';
import { DashboardService } from './dashboard.service';

const service = new DashboardService();

export class DashboardController {
  /** GET /v1/properties/:propertyId/dashboard */
  get = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const data = await service.getPropertyDashboard(req.params.propertyId);
      res.json({ data });
    } catch (err) {
      next(err);
    }
  };
}
