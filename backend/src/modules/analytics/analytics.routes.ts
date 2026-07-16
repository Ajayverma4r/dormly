// modules/analytics/analytics.routes.ts
import { Router } from 'express';
import { AnalyticsController } from './analytics.controller';

const controller = new AnalyticsController();
export const analyticsRouter = Router({ mergeParams: true });

analyticsRouter.get('/', controller.get);
analyticsRouter.get('/activity', controller.getActivity);