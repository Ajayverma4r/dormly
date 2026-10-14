// modules/staff/staff.controller.ts
import { Response, NextFunction } from 'express';
import { z } from 'zod';
import { StaffInviteError, StaffService } from './staff.service';
import { AuthedRequest } from '@shared/middleware/auth-guard';

const service = new StaffService();

export function sendInviteError(err: unknown, res: Response, next: NextFunction) {
  if (err instanceof StaffInviteError) {
    return res.status(err.status).json({ error: err.message });
  }
  next(err);
}

const assignSchema = z.object({
  phone: z.string().min(6),
  role: z.enum(['manager', 'staff']),
});

export class StaffController {
  list = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      res.json({ data: await service.listForProperty(req.params.propertyId) });
    } catch (err) { next(err); }
  };

  assign = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const body = assignSchema.parse(req.body);
      const assignment = await service.assign(req.params.propertyId, body.phone, body.role, req.userId!);
      res.status(201).json({ data: assignment });
    } catch (err) { sendInviteError(err, res, next); }
  };

  remove = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      await service.remove(req.params.propertyId, req.params.staffId);
      res.status(204).send();
    } catch (err) { sendInviteError(err, res, next); }
  };
}