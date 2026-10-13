// modules/analytics/analytics.routes.ts
import { Router } from 'express';
import { AnalyticsController } from './analytics.controller';
import { requireRole } from '@shared/middleware/auth-guard';

const controller = new AnalyticsController();
export const analyticsRouter = Router({ mergeParams: true });

analyticsRouter.use(requireRole('owner', 'admin', 'manager')); // Financial data: same roles as billing and reports
analyticsRouter.get('/', controller.get);
analyticsRouter.get('/activity', controller.getActivity);
