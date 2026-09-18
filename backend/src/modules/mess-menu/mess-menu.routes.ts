// modules/mess-menu/mess-menu.routes.ts
import { Router } from 'express';
import { MessMenuController } from './mess-menu.controller';

const controller = new MessMenuController();
export const messMenuRouter = Router({ mergeParams: true });

messMenuRouter.get('/', controller.list);
messMenuRouter.put('/day', controller.upsertDay);
messMenuRouter.put('/', controller.upsertWeek);
