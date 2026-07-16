// modules/staff/invitations.controller.ts
import { Response, NextFunction } from 'express';
import { StaffService } from './staff.service';
import { AuthedRequest } from '@shared/middleware/auth-guard';

const service = new StaffService();

export class InvitationsController {
  list = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      res.json({ data: await service.listPendingForUser(req.userId!) });
    } catch (err) { next(err); }
  };

  accept = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      res.json({ data: await service.accept(req.params.assignmentId, req.userId!) });
    } catch (err) { next(err); }
  };

  decline = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      await service.decline(req.params.assignmentId, req.userId!);
      res.status(204).send();
    } catch (err) { next(err); }
  };
}