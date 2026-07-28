// modules/reports/reports.routes.ts
import { Router } from 'express';
import { ReportsController } from './reports.controller';
import { requireRole } from '@shared/middleware/auth-guard';

const controller = new ReportsController();
export const reportsRouter = Router({ mergeParams: true });

reportsRouter.use(requireRole('owner', 'admin', 'manager')); // Staff has no reports access, per role matrix
reportsRouter.get('/rent-collection', controller.rentCollection);
reportsRouter.get('/occupancy', controller.occupancy);