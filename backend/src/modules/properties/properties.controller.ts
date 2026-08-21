// modules/properties/properties.controller.ts
import { Response, NextFunction } from 'express';
import { PropertiesService } from './properties.service';
import { AuthedRequest } from '@shared/middleware/auth-guard';

const service = new PropertiesService();

export class PropertiesController {
  list = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      // Prefer org from the scoped JWT (SaaS global context). Query param is fallback
      // for legacy clients — missing/empty query must not break authenticated owners.
      const organizationId =
        req.ctxType === 'organization' && req.ctxId
          ? req.ctxId
          : (req.query.organizationId as string | undefined);

      if (!organizationId) {
        return res.status(400).json({
          error: 'No organization context. Select a workspace and try again.',
        });
      }

      const properties = await service.listForOrganization(organizationId);
      res.json({ data: properties });
    } catch (err) {
      next(err);
    }
  };

  listTypes = async (_req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      res.json({ data: await service.listPropertyTypes() });
    } catch (err) { next(err); }
  };

  previewTemplate = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      res.json({ data: await service.previewTemplate(req.params.typeKey) });
    } catch (err) { next(err); }
  };

  getById = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const property = await service.getById(req.params.propertyId);
      if (!property) return res.status(404).json({ error: 'Property not found' });
      res.json({ data: property });
    } catch (err) { next(err); }
  };

  create = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      // Prefer scoped org context over client-supplied organizationId.
      const organizationId =
        req.ctxType === 'organization' && req.ctxId
          ? req.ctxId
          : (req.body.organizationId as string | undefined);

      if (!organizationId) {
        return res.status(400).json({ error: 'organizationId is required.' });
      }
      if (!req.body.propertyTypeKey) {
        return res.status(400).json({ error: 'propertyTypeKey is required.' });
      }

      const property = await service.create({
        ...req.body,
        organizationId,
      });
      res.status(201).json({ data: property });
    } catch (err) { next(err); }
  };
}
