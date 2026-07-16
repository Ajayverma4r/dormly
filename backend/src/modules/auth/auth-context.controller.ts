// modules/auth/auth-context.controller.ts
import { Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { z } from 'zod';
import { env } from '@config/env';
import { ContextService } from './context.service';
import { AuthedRequest } from '@shared/middleware/auth-guard';

const service = new ContextService();

const selectSchema = z.object({
  contextType: z.enum(['organization', 'tenancy']),
  contextId: z.string().uuid(),
});

export class AuthContextController {
  listContexts = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const contexts = await service.listContextsForUser(req.userId!);
      res.json({ data: contexts });
    } catch (err) { next(err); }
  };

  selectContext = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const { contextType, contextId } = selectSchema.parse(req.body);
      const contexts = await service.listContextsForUser(req.userId!);
      const match = contexts.find((c) => c.type === contextType && c.id === contextId);

      if (!match) {
        return res.status(403).json({ error: 'You do not have access to that context.' });
      }

      const accessToken = jwt.sign(
        {
          sub: req.userId,
          ctxType: match.type,
          ctxId: match.id,
          ctxRole: match.role,
          ctxPropertyId: match.propertyId ?? null,
        },
        env.jwtAccessSecret,
        { expiresIn: env.jwtAccessTtl } as jwt.SignOptions,
      );

      res.json({ data: { accessToken, context: match } });
    } catch (err) { next(err); }
  };
}