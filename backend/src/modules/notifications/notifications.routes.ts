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

function shapeNotification(row: any) {
  const readAt = row.read_at ?? row.readAt ?? null;
  return {
    ...row,
    data: row.data ?? {},
    read_at: readAt,
    is_read: readAt != null,
    isRead: readAt != null,
  };
}

/** GET /v1/notifications — all types, newest first. Backfills move-out items. */
notificationsRouter.get('/', async (req: AuthedRequest, res, next) => {
  try {
    const userId = req.userId!;

    await ensureNotificationsSchema().catch((err) =>
      console.warn('[notifications] schema ensure failed:', err),
    );
    try {
      await backfillMoveOutNotificationsForUser(userId);
    } catch (err) {
      console.warn('[notifications] pre-list backfill failed:', err);
    }

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

    res.json({ data: data.map(shapeNotification) });
  } catch (err) {
    next(err);
  }
});

/** GET /v1/notifications/unread-count */
notificationsRouter.get('/unread-count', async (req: AuthedRequest, res, next) => {
  try {
    const [row] = await query<{ count: string }>(
      `SELECT COUNT(*)::text AS count
       FROM notifications
       WHERE user_id = $1 AND read_at IS NULL`,
      [req.userId],
    );
    res.json({ data: { count: Number(row?.count ?? 0) } });
  } catch (err) {
    next(err);
  }
});

/** PATCH /v1/notifications/:id/read — mark one as read */
notificationsRouter.patch('/:id/read', async (req: AuthedRequest, res, next) => {
  try {
    const id = req.params.id;
    const rows = await query(
      `UPDATE notifications
       SET read_at = COALESCE(read_at, now())
       WHERE id = $1 AND user_id = $2
       RETURNING id, user_id, property_id, type, title, body, read_at, created_at`,
      [id, req.userId],
    );
    // Try to include data if column exists
    let row = rows[0];
    if (!row) {
      return res.status(404).json({ error: 'Notification not found' });
    }
    try {
      const withData = await query(
        `SELECT id, user_id, property_id, type, title, body, data, read_at, created_at
         FROM notifications WHERE id = $1 AND user_id = $2`,
        [id, req.userId],
      );
      if (withData[0]) row = withData[0];
    } catch {
      /* data column optional */
    }
    res.json({ data: shapeNotification(row) });
  } catch (err) {
    next(err);
  }
});

/** POST /v1/notifications/read-all — mark all unread as read for this user */
notificationsRouter.post('/read-all', async (req: AuthedRequest, res, next) => {
  try {
    const rows = await query<{ id: string }>(
      `UPDATE notifications
       SET read_at = now()
       WHERE user_id = $1 AND read_at IS NULL
       RETURNING id`,
      [req.userId],
    );
    res.json({ data: { updated: rows.length } });
  } catch (err) {
    next(err);
  }
});
