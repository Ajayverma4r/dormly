// modules/structure/structure.controller.ts
import { Request, Response, NextFunction } from 'express';
import { StructureService } from '@core/structure-engine/services/structure.service';

export class StructureController {
  constructor(private readonly service: StructureService) {}

  listLevels = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const levels = await this.service.listLevels(req.params.propertyId);
      res.json({ data: levels });
    } catch (err) { next(err); }
  };

  createLevel = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const level = await this.service.createLevel({
        propertyId: req.params.propertyId,
        ...req.body,
      });
      res.status(201).json({ data: level });
    } catch (err) { next(err); }
  };

  updateLevel = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { displayName, isEnabled, ...rest } = req.body;
      let level;
      if (displayName !== undefined) {
        level = await this.service.renameLevel(req.params.levelId, displayName);
      }
      if (isEnabled !== undefined) {
        level = await this.service.setLevelEnabled(req.params.levelId, isEnabled);
      }
      if (Object.keys(rest).length > 0) {
        level = await this.service.updateLevelConfig(req.params.levelId, rest);
      }
      res.json({ data: level });
    } catch (err) { next(err); }
  };

  reorderLevels = async (req: Request, res: Response, next: NextFunction) => {
    try {
      await this.service.reorderLevels(req.params.propertyId, req.body.orderedIds);
      res.status(204).send();
    } catch (err) { next(err); }
  };

  deleteLevel = async (req: Request, res: Response, next: NextFunction) => {
    try {
      await this.service.deleteLevel(req.params.levelId, { forceCascade: req.query.force === 'true' });
      res.status(204).send();
    } catch (err) { next(err); }
  };

  listNodes = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const nodes = await this.service.listNodes(
        req.query.levelId as string,
        (req.query.parentNodeId as string) ?? null,
      );
      res.json({ data: nodes });
    } catch (err) { next(err); }
  };

  createNode = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const node = await this.service.createNode({
        propertyId: req.params.propertyId,
        ...req.body,
      });
      res.status(201).json({ data: node });
    } catch (err) { next(err); }
  };

  updateNode = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const node = await this.service.updateNode(req.params.nodeId, req.body);
      res.json({ data: node });
    } catch (err) { next(err); }
  };

  deleteNode = async (req: Request, res: Response, next: NextFunction) => {
    try {
      await this.service.deleteNode(req.params.nodeId);
      res.status(204).send();
    } catch (err) { next(err); }
  };
}
