// modules/analytics/org-analytics.routes.ts
import { Router } from 'express';
import { AnalyticsController } from './analytics.controller';
import { authGuard, requireContext, requireOrganizationAccess } from '@shared/middleware/auth-guard';

const controller = new AnalyticsController();
export const orgAnalyticsRouter = Router({ mergeParams: true });

orgAnalyticsRouter.use(authGuard, requireContext, requireOrganizationAccess);
orgAnalyticsRouter.get('/', controller.getForOrganization);
