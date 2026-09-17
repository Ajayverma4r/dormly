// modules/notifications/notifications.routes.ts
import { Router } from 'express';
import { query } from '@config/db';
import { authGuard, AuthedRequest } from '@shared/middleware/auth-guard';
import {
  backfillMoveOutNotificationsForUser,
  ensureNotificationsSchema,
} from './move-out-notifications';

export const notificationsRouter = Router();
notificationsRouter.use(authGuard);

notificationsRouter.get('/', async (req: AuthedRequest, res, next) => {
  try {
    const userId = req.userId!;
    console.log(`[notifications] GET list for user=${userId}`);

    // Ensure schema + backfill any missing move-out notifications for this owner.
    await ensureNotificationsSchema().catch((err) =>
      console.warn('[notifications] schema ensure failed:', err),
    );
    try {
      const ensured = await backfillMoveOutNotificationsForUser(userId);
      console.log(
        `[notifications] pre-list backfill ensured=${ensured} user=${userId}`,
      );
    } catch (err) {
      console.warn('[notifications] pre-list backfill failed:', err);
    }

    // Explicit columns — never filter by type.
    let data: any[];
    try {
      data = await query(
        `SELECT id, user_id, property_id, type, title, body, data, read_at, created_at
         FROM notifications
         WHERE user_id = $1
         ORDER BY created_at DESC
         LIMIT 50`,
        [userId],
      );
    } catch (err) {
      console.warn('[notifications] list with data column failed:', err);
      data = await query(
        `SELECT id, user_id, property_id, type, title, body, read_at, created_at
         FROM notifications
         WHERE user_id = $1
         ORDER BY created_at DESC
         LIMIT 50`,
        [userId],
      );
    }

    console.log(
      `[notifications] returning ${data.length} rows for user=${userId} types=${data
        .map((r) => r.type)
        .join(',')}`,
    );

    res.json({
      data: data.map((row) => ({
        ...row,
        data: row.data ?? {},
      })),
    });
  } catch (err) {
    next(err);
  }
});
