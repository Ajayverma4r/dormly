// modules/notifications/notifications.routes.ts
import { Router } from 'express';
import { query } from '@config/db';
import { authGuard, AuthedRequest } from '@shared/middleware/auth-guard';

export const notificationsRouter = Router();
notificationsRouter.use(authGuard);

notificationsRouter.get('/', async (req: AuthedRequest, res, next) => {
  try {
    const data = await query(
      `SELECT * FROM notifications WHERE user_id = $1 ORDER BY created_at DESC LIMIT 50`,
      [req.userId],
    );
    res.json({ data });
  } catch (err) { next(err); }
});