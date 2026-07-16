// modules/structure/structure.routes.ts

import { Router } from 'express';
import { StructureController } from './structure.controller';
import { StructureService } from '@core/structure-engine/services/structure.service';
import {
  PgHierarchyLevelRepository,
  PgHierarchyNodeRepository,
} from './structure.repository';
import { requireRole } from '@shared/middleware/auth-guard';

const service = new StructureService(
  new PgHierarchyLevelRepository(),
  new PgHierarchyNodeRepository(),
);

const controller = new StructureController(service);

export const structureRouter = Router({ mergeParams: true });

// ==================== LEVELS ====================

structureRouter.get('/levels', controller.listLevels);

structureRouter.post(
  '/levels',
  requireRole('owner', 'admin', 'manager'),
  controller.createLevel,
);

structureRouter.patch(
  '/levels/:levelId',
  requireRole('owner', 'admin', 'manager'),
  controller.updateLevel,
);

structureRouter.post(
  '/levels/reorder',
  requireRole('owner', 'admin', 'manager'),
  controller.reorderLevels,
);

structureRouter.delete(
  '/levels/:levelId',
  requireRole('owner', 'admin', 'manager'),
  controller.deleteLevel,
);

// ==================== NODES ====================

structureRouter.get('/nodes', controller.listNodes);

structureRouter.post(
  '/nodes',
  requireRole('owner', 'admin', 'manager'),
  controller.createNode,
);

structureRouter.patch(
  '/nodes/:nodeId',
  requireRole('owner', 'admin', 'manager'),
  controller.updateNode,
);

structureRouter.delete(
  '/nodes/:nodeId',
  requireRole('owner', 'admin', 'manager'),
  controller.deleteNode,
);