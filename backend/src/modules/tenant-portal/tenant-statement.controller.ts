// modules/tenant-portal/tenant-statement.controller.ts
import { Response, NextFunction } from 'express';
import { AuthedRequest } from '@shared/middleware/auth-guard';
import { propertyClock } from '@modules/billing/billing-metrics';
import {
  StatementFilter,
  StatementRequestError,
  TenantStatementService,
} from './tenant-statement.service';
import { renderStatementPdf } from './tenant-statement.pdf';

const service = new TenantStatementService();

function filterFrom(req: AuthedRequest): StatementFilter {
  const q = req.query as Record<string, unknown>;
  const str = (v: unknown) => (typeof v === 'string' ? v : undefined);
  return { propertyId: str(q.propertyId), from: str(q.from), to: str(q.to) };
}

function handle(err: unknown, res: Response, next: NextFunction) {
  if (err instanceof StatementRequestError) {
    return res.status(err.status).json({ error: err.message });
  }
  next(err);
}

export class TenantStatementController {
  stays = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      res.json({ data: await service.listStays(req.userId!, req.ctxId) });
    } catch (err) {
      next(err);
    }
  };

  paymentHistory = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      res.json({ data: await service.getHistory(req.userId!, filterFrom(req)) });
    } catch (err) {
      handle(err, res, next);
    }
  };

  statementPdf = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const result = await service.getHistory(req.userId!, filterFrom(req));
      if (result.payments.length === 0) {
        return res.status(404).json({ error: 'No payments found for this selection.' });
      }
      const [holder, stays, clock] = await Promise.all([
        service.statementHolder(req.userId!, req.ctxId),
        service.listStays(req.userId!, req.ctxId),
        propertyClock(String(req.ctxPropertyId ?? '')),
      ]);
      const scopeLabel = result.filter.propertyId
        ? stays.find((s) => s.property_id === result.filter.propertyId)?.property_name ?? 'Property'
        : 'All properties I have stayed at';

      const doc = renderStatementPdf({
        holder,
        scopeLabel,
        from: result.filter.from,
        to: result.filter.to,
        generatedOn: clock.today,
        result,
      });
      const name = `Dormly_Payment_Statement_${clock.today}.pdf`;
      res.setHeader('Content-Type', 'application/pdf');
      res.setHeader('Content-Disposition', `inline; filename="${name}"`);
      res.setHeader('Cache-Control', 'no-store');
      doc.pipe(res);
    } catch (err) {
      handle(err, res, next);
    }
  };
}
