// modules/gate-passes/gate-passes.controller.ts
import { Response, NextFunction } from 'express';
import { z } from 'zod';
import { GatePassesService } from './gate-passes.service';
import { AuthedRequest } from '@shared/middleware/auth-guard';
import { TenantPortalService } from '@modules/tenant-portal/tenant-portal.service';

const service = new GatePassesService();
const tenantPortal = new TenantPortalService();

export class GatePassesController {
  list = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      res.json({ data: await service.listByProperty(req.params.propertyId) });
    } catch (err) {
      next(err);
    }
  };

  decide = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const body = z
        .object({ status: z.enum(['approved', 'denied']) })
        .parse(req.body);
      const row = await service.decide(
        req.params.propertyId,
        req.params.gatePassId,
        body.status,
        req.userId!,
      );
      if (!row) return res.status(404).json({ error: 'Gate pass not found' });
      res.json({ data: row });
    } catch (err) {
      next(err);
    }
  };

  myList = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const tenancy = await tenantPortal.getMyTenancy(req.ctxId!);
      if (!tenancy) return res.status(404).json({ error: 'No active tenancy' });
      res.json({
        data: await service.listMine(req.userId!, String(tenancy.id)),
      });
    } catch (err) {
      next(err);
    }
  };

  createMine = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const tenancy = await tenantPortal.getMyTenancy(req.ctxId!);
      if (!tenancy) return res.status(404).json({ error: 'No active tenancy' });
      const body = z
        .object({
          visitorName: z.string().min(1),
          purpose: z.string().default('visitor'),
          notes: z.string().optional(),
          validUntil: z.string().optional(),
        })
        .parse(req.body);
      const row = await service.create({
        propertyId: String(tenancy.property_id),
        unitId: String(tenancy.node_id),
        tenancyId: String(tenancy.id),
        requestedBy: req.userId!,
        visitorName: body.visitorName,
        purpose: body.purpose,
        notes: body.notes,
        validUntil: body.validUntil,
      });
      res.status(201).json({ data: row });
    } catch (err) {
      next(err);
    }
  };
}
