// modules/mess-menu/mess-menu.routes.ts
import { Router } from 'express';
import { MessMenuController } from './mess-menu.controller';
import { requirePropertyTeam } from '@shared/middleware/auth-guard';

const controller = new MessMenuController();
export const messMenuRouter = Router({ mergeParams: true });

// Tenants read the menu through /tenant-portal and never edit it.
messMenuRouter.use(requirePropertyTeam);
messMenuRouter.get('/', controller.list);
messMenuRouter.put('/day', controller.upsertDay);
messMenuRouter.put('/', controller.upsertWeek);
