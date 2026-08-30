// modules/dashboard/dashboard.routes.ts

import { Router } from 'express';
import { DashboardController } from './dashboard.controller';

const controller = new DashboardController();
export const dashboardRouter = Router({ mergeParams: true });

dashboardRouter.get('/', controller.get);
