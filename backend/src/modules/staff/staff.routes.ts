// modules/staff/staff.routes.ts
import { Router } from 'express';
import { StaffController } from './staff.controller';
import { requireRole } from '@shared/middleware/auth-guard';

const controller = new StaffController();
export const staffRouter = Router({ mergeParams: true });

// Only Owner/Admin can invite or remove staff — a Manager should not be
// able to assign other managers/staff, even on their own assigned property.
staffRouter.get('/', controller.list);
staffRouter.post('/', requireRole('owner', 'admin'), controller.assign);
staffRouter.delete('/:staffId', requireRole('owner', 'admin'), controller.remove);