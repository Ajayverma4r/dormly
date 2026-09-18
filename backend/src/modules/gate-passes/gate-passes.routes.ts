// modules/gate-passes/gate-passes.routes.ts
import { Router } from 'express';
import { GatePassesController } from './gate-passes.controller';

const controller = new GatePassesController();
export const gatePassesRouter = Router({ mergeParams: true });

gatePassesRouter.get('/', controller.list);
gatePassesRouter.patch('/:gatePassId', controller.decide);
