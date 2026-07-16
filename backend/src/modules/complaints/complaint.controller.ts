// modules/complaints/complaint.controller.ts
import { Response, NextFunction } from 'express';
import { z } from 'zod';
import { ComplaintService } from './complaint.service';
import { AuthedRequest } from '@shared/middleware/auth-guard';

const service = new ComplaintService();

const createSchema = z.object({
  nodeId: z.string().uuid(),
  category: z.string().min(1),
  description: z.string().min(1),
  priority: z.enum(['low', 'medium', 'high']).default('medium'),
});

const updateSchema = z.object({
  status: z.enum(['open', 'in_progress', 'resolved', 'closed']),
  resolutionNote: z.string().optional(),
});

export class ComplaintController {
  list = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      res.json({ data: await service.listByProperty(req.params.propertyId) });
    } catch (err) { next(err); }
  };

  create = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const body = createSchema.parse(req.body);
      const complaint = await service.create(
        req.params.propertyId, body.nodeId, req.userId!, body.category, body.description, body.priority,
      );
      res.status(201).json({ data: complaint });
    } catch (err) { next(err); }
  };

  updateStatus = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const body = updateSchema.parse(req.body);
      const complaint = await service.updateStatus(req.params.complaintId, body.status, body.resolutionNote);
      res.json({ data: complaint });
    } catch (err) { next(err); }
  };

  // Tenant-facing — creates against the caller's own tenancy node only.
  myComplaints = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      res.json({ data: await service.listByUser(req.userId!) });
    } catch (err) { next(err); }
  };

  createMine = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const body = z.object({
        category: z.string().min(1),
        description: z.string().min(1),
        priority: z.enum(['low', 'medium', 'high']).default('medium'),
        propertyId: z.string().uuid(),
        nodeId: z.string().uuid(),
      }).parse(req.body);
      const complaint = await service.create(
        body.propertyId, body.nodeId, req.userId!, body.category, body.description, body.priority,
      );
      res.status(201).json({ data: complaint });
    } catch (err) { next(err); }
  };
}