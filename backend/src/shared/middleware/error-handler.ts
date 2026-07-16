// shared/middleware/error-handler.ts
import { Request, Response, NextFunction } from 'express';
import { ZodError } from 'zod';
import { StructureValidationError } from '@core/structure-engine/services/structure.service';

export function errorHandler(err: unknown, req: Request, res: Response, _next: NextFunction) {
  if (err instanceof ZodError) {
    return res.status(400).json({ error: 'Validation failed', details: err.errors });
  }
  if (err instanceof StructureValidationError) {
    return res.status(409).json({ error: err.message });
  }
  if (err instanceof Error) {
    // eslint-disable-next-line no-console
    console.error(err);
    return res.status(400).json({ error: err.message });
  }
  res.status(500).json({ error: 'Internal server error' });
}
