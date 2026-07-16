// modules/analytics/analytics.controller.ts
import { Response, NextFunction } from 'express';
import { AnalyticsService } from './analytics.service';
import { AuthedRequest } from '@shared/middleware/auth-guard';

const service = new AnalyticsService();

export class AnalyticsController {
  get = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      res.json({ data: await service.getPropertyAnalytics(req.params.propertyId) });
    } catch (err) { next(err); }
  };
  getForOrganization = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      res.json({ data: await service.getOrganizationAnalytics(req.params.organizationId) });
    } catch (err) { next(err); }
  };
  getActivity = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      res.json({ data: await service.getRecentActivity(req.params.propertyId) });
    } catch (err) { next(err); }
  };
}