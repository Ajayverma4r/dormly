// modules/tenant-portal/tenant-portal.controller.ts
import { Response, NextFunction } from 'express';
import { z } from 'zod';
import { TenantPortalService } from './tenant-portal.service';
import { AuthedRequest } from '@shared/middleware/auth-guard';

const service = new TenantPortalService();

const moveOutRequestSchema = z.object({
  proposedExitDate: z.string().min(1),
  isEmergency: z.boolean().optional().default(false),
  reason: z.string().max(500).optional(),
});

export class TenantPortalController {
  getMe = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const tenancy = await service.getMyTenancy(req.ctxId!);
      if (!tenancy) {
        return res.status(404).json({ error: 'Tenancy not found' });
      }
      res.json({ data: tenancy });
    } catch (err) { next(err); }
  };

  requestMoveOut = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      console.log(
        `>>> POST /v1/tenant-portal/move-out-request <<< ctxId=${req.ctxId} userId=${req.userId}`,
      );
      const body = moveOutRequestSchema.parse(req.body);
      const tenancy = await service.requestMoveOut(req.ctxId!, {
        proposedExitDate: body.proposedExitDate,
        isEmergency: body.isEmergency,
        reason: body.reason,
      });
      console.log(
        `>>> move-out-request OK <<< tenancy=${tenancy?.id} owner=${tenancy?.owner_user_id}`,
      );
      res.json({ data: tenancy });
    } catch (err) {
      if (err instanceof z.ZodError) {
        return res.status(400).json({ error: err.errors[0]?.message ?? 'Invalid request' });
      }
      const message = err instanceof Error ? err.message : 'Could not submit move-out request';
      console.warn(`>>> move-out-request error <<< ${message}`);
      if (err instanceof Error && err.stack) console.warn(err.stack);
      const status = message.includes('already') || message.includes('past') || message.includes('ended')
        ? 400
        : 500;
      if (status === 400) return res.status(400).json({ error: message });
      next(err);
    }
  };

  societyNotices = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const rows = await service.listSocietyNotices(req.ctxId!, req.userId!);
      res.json({ data: rows });
    } catch (err) {
      next(err);
    }
  };

  leaseDetails = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const data = await service.getLeaseDetails(req.ctxId!);
      res.json({ data });
    } catch (err) {
      next(err);
    }
  };
}
