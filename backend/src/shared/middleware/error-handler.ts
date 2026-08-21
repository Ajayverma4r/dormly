// shared/middleware/error-handler.ts
import { Request, Response, NextFunction } from 'express';
import { ZodError } from 'zod';
import { StructureValidationError } from '@core/structure-engine/services/structure.service';
import { SubscriptionRequiredError } from '@shared/property-monetization';

export function errorHandler(err: unknown, req: Request, res: Response, _next: NextFunction) {
  if (err instanceof ZodError) {
    return res.status(400).json({ error: 'Validation failed', details: err.errors });
  }
  if (err instanceof StructureValidationError) {
    return res.status(409).json({ error: err.message });
  }
  if (err instanceof SubscriptionRequiredError) {
    return res.status(err.statusCode).json({
      error: err.message,
      code: err.code,
      upgradeRequired: true,
    });
  }
  if (err instanceof Error) {
    // eslint-disable-next-line no-console
    console.error(err);
    return res.status(400).json({ error: err.message });
  }
  res.status(500).json({ error: 'Internal server error' });
}
