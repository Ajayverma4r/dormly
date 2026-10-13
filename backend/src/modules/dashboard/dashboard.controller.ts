// modules/dashboard/dashboard.controller.ts

import { Response, NextFunction } from 'express';
import { AuthedRequest } from '@shared/middleware/auth-guard';
import { DashboardService } from './dashboard.service';
import {
  FINANCIAL_PERIODS,
  getDashboardFinancials,
  parseFinancialPeriod,
} from './dashboard-financials';

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

  /** GET /v1/properties/:propertyId/dashboard/financials?period=this_month */
  financials = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const period = parseFinancialPeriod(req.query.period);
      if (!period) {
        return res
          .status(400)
          .json({ error: `period must be one of: ${FINANCIAL_PERIODS.join(', ')}` });
      }
      res.json({ data: await getDashboardFinancials(req.params.propertyId, period) });
    } catch (err) {
      next(err);
    }
  };
}
