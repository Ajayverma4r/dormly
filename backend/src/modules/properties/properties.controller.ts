// modules/properties/properties.controller.ts
import { Response, NextFunction } from 'express';
import { PropertiesService } from './properties.service';
import { AuthedRequest } from '@shared/middleware/auth-guard';

const service = new PropertiesService();

export class PropertiesController {
  list = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      // organizationId resolution from membership is elided here for brevity —
      // in the full build this comes from a tenant-resolution middleware.
      const organizationId = req.query.organizationId as string;
      const properties = await service.listForOrganization(organizationId);
      res.json({ data: properties });
    } catch (err) { next(err); }
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
      const property = await service.create(req.body);
      res.status(201).json({ data: property });
    } catch (err) { next(err); }
  };
}
