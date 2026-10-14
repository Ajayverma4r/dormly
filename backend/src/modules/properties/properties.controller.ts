// modules/properties/properties.controller.ts
import { Response, NextFunction } from 'express';
import { PropertiesService } from './properties.service';
import { activeStaffRole, AuthedRequest } from '@shared/middleware/auth-guard';

const service = new PropertiesService();

/** Organization of an owner/admin workspace token, or null for any other role. */
function ownerOrganization(req: AuthedRequest): string | null {
  return req.ctxType === 'organization' &&
    (req.ctxRole === 'owner' || req.ctxRole === 'admin') &&
    req.ctxId
    ? req.ctxId
    : null;
}

export class PropertiesController {
  list = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      // The organization always comes from the selected workspace, never from
      // the client, so nobody can list another organization's properties.
      const organizationId = ownerOrganization(req);
      if (organizationId) {
        res.json({ data: await service.listForOrganization(organizationId) });
        return;
      }

      // Managers and staff see only the one property they accepted.
      if (
        (req.ctxRole === 'manager' || req.ctxRole === 'staff') &&
        req.userId &&
        req.ctxPropertyId &&
        (await activeStaffRole(req.userId, req.ctxPropertyId)) === req.ctxRole
      ) {
        const property = await service.getById(req.ctxPropertyId);
        res.json({ data: property ? [property] : [] });
        return;
      }

      return res.status(403).json({ error: 'Your workspace cannot list properties.' });
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
      const organizationId = ownerOrganization(req);
      if (!organizationId) {
        return res.status(403).json({ error: 'Only owners and admins can add properties.' });
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
