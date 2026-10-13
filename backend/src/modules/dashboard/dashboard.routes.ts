// modules/dashboard/dashboard.routes.ts

import { Router } from 'express';
import { DashboardController } from './dashboard.controller';
import { requireRole } from '@shared/middleware/auth-guard';

const controller = new DashboardController();
export const dashboardRouter = Router({ mergeParams: true });

dashboardRouter.use(requireRole('owner', 'admin', 'manager')); // Financial data: same roles as billing and reports
dashboardRouter.get('/', controller.get);
