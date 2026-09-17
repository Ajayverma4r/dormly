// modules/notifications/move-out-notifications.ts
//
// Shared helpers: ensure schema, insert move-out notifications, and backfill
// for owners when they open the notifications list.

import { query } from '@config/db';

export type MoveOutNotifInput = {
  userId: string;
  propertyId: string;
  tenancyId: string;
  tenantName: string;
  room: string;
  proposedExitAt?: string | Date | null;
  isEmergency?: boolean;
};

let schemaReady: Promise<boolean> | null = null;

/** Idempotent: adds `notifications.data` if missing. */
export async function ensureNotificationsSchema(): Promise<boolean> {
  if (!schemaReady) {
    schemaReady = (async () => {
      try {
        await query(
          `ALTER TABLE notifications
             ADD COLUMN IF NOT EXISTS data JSONB NOT NULL DEFAULT '{}'::jsonb`,
        );
        console.log('[notifications] ensured notifications.data column');
        return true;
      } catch (err) {
        console.error('[notifications] could not ensure data column:', err);
        return false;
      }
    })();
  }
  return schemaReady;
}

function formatExitLabel(raw?: string | Date | null): string {
  if (!raw) return 'TBD';
  const d = raw instanceof Date ? raw : new Date(raw);
  if (Number.isNaN(d.getTime())) return 'TBD';
  return d.toLocaleDateString('en-IN', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
  });
}

export function buildMoveOutNotificationContent(input: MoveOutNotifInput) {
  const tenantName = (input.tenantName || 'Tenant').trim() || 'Tenant';
  const room = (input.room || '—').trim() || '—';
  const exitLabel = formatExitLabel(input.proposedExitAt);
  const emergencyTag = input.isEmergency ? ' • Emergency' : '';
  return {
    title: `Move-Out Request: ${tenantName}`,
    body: `Proposed exit: ${exitLabel} • Room ${room}${emergencyTag}`,
    type: 'move_out_request' as const,
    data: {
      tenancy_id: input.tenancyId,
      tenancyId: input.tenancyId,
      property_id: input.propertyId,
      propertyId: input.propertyId,
      route: '/tenant-profile',
      isEmergency: input.isEmergency === true,
    },
  };
}

/** Returns true if a move-out notification already exists for this user+tenancy. */
async function alreadyExists(
  userId: string,
  propertyId: string,
  tenancyId: string,
  title: string,
): Promise<boolean> {
  const hasData = await ensureNotificationsSchema();
  if (hasData) {
    const byData = await query<{ id: string }>(
      `SELECT id FROM notifications
       WHERE user_id = $1
         AND property_id = $2
         AND (
           type = 'move_out_request'
           OR type = $3
         )
         AND (
           data->>'tenancy_id' = $4
           OR data->>'tenancyId' = $4
           OR type = $3
           OR title = $5
         )
       LIMIT 1`,
      [userId, propertyId, `move_out_request:${tenancyId}`, tenancyId, title],
    );
    if (byData.length) return true;
  }

  const byType = await query<{ id: string }>(
    `SELECT id FROM notifications
     WHERE user_id = $1
       AND property_id = $2
       AND (
         type = $3
         OR (type = 'move_out_request' AND title = $4)
       )
     LIMIT 1`,
    [userId, propertyId, `move_out_request:${tenancyId}`, title],
  );
  return byType.length > 0;
}

/**
 * Insert one move-out notification for a recipient. Idempotent.
 * Logs every step for debugging.
 */
export async function insertMoveOutNotification(
  input: MoveOutNotifInput,
): Promise<boolean> {
  const { title, body, type, data } = buildMoveOutNotificationContent(input);
  console.log(
    `>>> INSERTING NOTIFICATION FOR USER: ${input.userId} <<< tenancy=${input.tenancyId} property=${input.propertyId}`,
  );

  try {
    if (await alreadyExists(input.userId, input.propertyId, input.tenancyId, title)) {
      console.log(
        `>>> SKIP DUPLICATE move-out notif user=${input.userId} tenancy=${input.tenancyId} <<<`,
      );
      return true;
    }

    const hasData = await ensureNotificationsSchema();
    if (hasData) {
      await query(
        `INSERT INTO notifications (user_id, property_id, type, title, body, data)
         VALUES ($1, $2, $3, $4, $5, $6::jsonb)`,
        [
          input.userId,
          input.propertyId,
          type,
          title,
          body,
          JSON.stringify(data),
        ],
      );
    } else {
      await query(
        `INSERT INTO notifications (user_id, property_id, type, title, body)
         VALUES ($1, $2, $3, $4, $5)`,
        [
          input.userId,
          input.propertyId,
          `move_out_request:${input.tenancyId}`,
          title,
          body,
        ],
      );
    }

    console.log(
      `>>> NOTIFICATION INSERTED OK user=${input.userId} title="${title}" <<<`,
    );
    return true;
  } catch (err) {
    console.error('>>> NOTIFICATION INSERT FAILED <<<');
    console.error(err);
    if (err instanceof Error) {
      console.error(err.stack);
    }
    // Absolute fallback — base columns only
    try {
      await query(
        `INSERT INTO notifications (user_id, property_id, type, title, body)
         VALUES ($1, $2, $3, $4, $5)`,
        [
          input.userId,
          input.propertyId,
          `move_out_request:${input.tenancyId}`,
          title,
          body,
        ],
      );
      console.log(
        `>>> FALLBACK INSERT OK user=${input.userId} tenancy=${input.tenancyId} <<<`,
      );
      return true;
    } catch (err2) {
      console.error('>>> FALLBACK INSERT ALSO FAILED <<<');
      console.error(err2);
      if (err2 instanceof Error) {
        console.error(err2.stack);
      }
      return false;
    }
  }
}

/** Resolve owner/admin user ids for a property. */
export async function resolvePropertyOwnerIds(
  propertyId: string,
  preferredOwnerId?: string | null,
): Promise<string[]> {
  const ids = new Set<string>();
  if (preferredOwnerId) ids.add(String(preferredOwnerId));

  try {
    const rows = await query<{ user_id: string }>(
      `SELECT DISTINCT u.user_id FROM (
         SELECT o.owner_user_id AS user_id
         FROM properties p
         JOIN organizations o ON o.id = p.organization_id
         WHERE p.id = $1
         UNION
         SELECT m.user_id
         FROM properties p
         JOIN memberships m ON m.organization_id = p.organization_id
         WHERE p.id = $1 AND m.role IN ('owner', 'admin')
       ) u
       WHERE u.user_id IS NOT NULL`,
      [propertyId],
    );
    for (const r of rows) ids.add(String(r.user_id));
  } catch (err) {
    console.warn('[notifications] resolvePropertyOwnerIds failed:', err);
  }

  return [...ids];
}

/** Notify all owners/admins about a tenancy move-out request. */
export async function notifyOwnersOfMoveOut(tenancy: any): Promise<number> {
  const propertyId = tenancy.property_id ?? tenancy.propertyId;
  const ownerUserId = tenancy.owner_user_id ?? tenancy.ownerUserId;
  if (!propertyId) {
    console.warn('[notifications] move-out notify skipped: missing propertyId');
    return 0;
  }

  const recipients = await resolvePropertyOwnerIds(propertyId, ownerUserId);
  console.log(
    `[notifications] move-out recipients for property=${propertyId}:`,
    recipients,
  );
  if (!recipients.length) return 0;

  const inputBase = {
    propertyId: String(propertyId),
    tenancyId: String(tenancy.id),
    tenantName: String(tenancy.full_name ?? tenancy.fullName ?? 'Tenant'),
    room: String(tenancy.node_name ?? tenancy.nodeName ?? '—'),
    proposedExitAt: tenancy.planned_move_out_at ?? tenancy.plannedMoveOutAt,
    isEmergency:
      tenancy.move_out_is_emergency === true ||
      tenancy.move_out_is_emergency === 'true',
  };

  let ok = 0;
  for (const userId of recipients) {
    const inserted = await insertMoveOutNotification({ ...inputBase, userId });
    if (inserted) ok += 1;
  }
  console.log(
    `[notifications] move-out notify done insertedOrExisting=${ok}/${recipients.length}`,
  );
  return ok;
}

/**
 * When an owner opens Notifications, create any missing move-out notifications
 * for pending requests on their properties.
 */
export async function backfillMoveOutNotificationsForUser(
  userId: string,
): Promise<number> {
  await ensureNotificationsSchema();

  let rows: Array<{
    tenancy_id: string;
    full_name: string;
    room: string;
    property_id: string;
    planned_move_out_at: string | null;
    is_emergency: boolean;
  }> = [];

  try {
    rows = await query(
      `SELECT
         t.id AS tenancy_id,
         t.full_name,
         n.name AS room,
         t.property_id,
         t.planned_move_out_at::text,
         COALESCE(t.move_out_is_emergency, false) AS is_emergency
       FROM tenancies t
       JOIN hierarchy_nodes n ON n.id = t.node_id
       JOIN properties p ON p.id = t.property_id
       JOIN organizations o ON o.id = p.organization_id
       LEFT JOIN memberships m
         ON m.organization_id = o.id AND m.user_id = $1
       WHERE t.status = 'active'
         AND t.planned_move_out_at IS NOT NULL
         AND t.planned_move_out_at >= now() - interval '1 day'
         AND (
           o.owner_user_id = $1
           OR m.role IN ('owner', 'admin')
         )
       ORDER BY t.planned_move_out_at ASC
       LIMIT 50`,
      [userId],
    );
  } catch (err) {
    console.warn(
      '[notifications] backfill query v2 failed, trying without emergency col:',
      err,
    );
    try {
      rows = await query(
        `SELECT
           t.id AS tenancy_id,
           t.full_name,
           n.name AS room,
           t.property_id,
           t.planned_move_out_at::text,
           false AS is_emergency
         FROM tenancies t
         JOIN hierarchy_nodes n ON n.id = t.node_id
         JOIN properties p ON p.id = t.property_id
         JOIN organizations o ON o.id = p.organization_id
         LEFT JOIN memberships m
           ON m.organization_id = o.id AND m.user_id = $1
         WHERE t.status = 'active'
           AND t.planned_move_out_at IS NOT NULL
           AND t.planned_move_out_at >= now() - interval '1 day'
           AND (
             o.owner_user_id = $1
             OR m.role IN ('owner', 'admin')
           )
         ORDER BY t.planned_move_out_at ASC
         LIMIT 50`,
        [userId],
      );
    } catch (err2) {
      console.error('>>> BACKFILL QUERY FAILED <<<');
      console.error(err2);
      if (err2 instanceof Error) console.error(err2.stack);
      return 0;
    }
  }

  let created = 0;
  for (const row of rows) {
    const ok = await insertMoveOutNotification({
      userId,
      propertyId: row.property_id,
      tenancyId: row.tenancy_id,
      tenantName: row.full_name,
      room: row.room,
      proposedExitAt: row.planned_move_out_at,
      isEmergency: row.is_emergency === true,
    });
    if (ok) created += 1;
  }

  if (rows.length) {
    console.log(
      `[notifications] backfill for user=${userId}: candidates=${rows.length} ensured=${created}`,
    );
  }
  return created;
}
