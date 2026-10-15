// modules/gate-passes/gate-passes.routes.ts
import { Router } from 'express';
import { GatePassesController } from './gate-passes.controller';
import { requirePropertyTeam } from '@shared/middleware/auth-guard';
import { scopeParamToProperty } from '@shared/middleware/property-scope';

const controller = new GatePassesController();
export const gatePassesRouter = Router({ mergeParams: true });

gatePassesRouter.param('gatePassId', scopeParamToProperty('gate_passes'));

// Tenants request and track their own passes through /tenant-portal only.
gatePassesRouter.get('/', requirePropertyTeam, controller.list);
gatePassesRouter.patch('/:gatePassId', requirePropertyTeam, controller.decide);
