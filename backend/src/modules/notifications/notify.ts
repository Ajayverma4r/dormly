// modules/notifications/notify.ts
//
// Unified notification insert used by complaints, mess, meters, move-out, etc.
// Any state change that should alert the other party goes through here.

import { query } from '@config/db';
import {
  ensureNotificationsSchema,
  resolvePropertyOwnerIds,
} from './move-out-notifications';

export type NotifyInput = {
  userId: string;
  propertyId?: string | null;
  type: string;
  title: string;
  body: string;
  data?: Record<string, unknown>;
};

export async function createNotification(input: NotifyInput): Promise<boolean> {
  const hasData = await ensureNotificationsSchema().catch(() => false);
  const payload = JSON.stringify(input.data ?? {});

  try {
    if (hasData) {
      await query(
        `INSERT INTO notifications (user_id, property_id, type, title, body, data)
         VALUES ($1, $2, $3, $4, $5, $6::jsonb)`,
        [
          input.userId,
          input.propertyId ?? null,
          input.type,
          input.title,
          input.body,
          payload,
        ],
      );
    } else {
      await query(
        `INSERT INTO notifications (user_id, property_id, type, title, body)
         VALUES ($1, $2, $3, $4, $5)`,
        [
          input.userId,
          input.propertyId ?? null,
          input.type,
          input.title,
          input.body,
        ],
      );
    }
    console.log(
      `>>> INSERTING NOTIFICATION FOR USER: ${input.userId} <<< type=${input.type}`,
    );
    return true;
  } catch (err) {
    console.error('[notifications] createNotification failed:', err);
    return false;
  }
}

export async function notifyPropertyOwners(opts: {
  propertyId: string;
  preferredOwnerId?: string | null;
  type: string;
  title: string;
  body: string;
  data?: Record<string, unknown>;
}): Promise<number> {
  const recipients = await resolvePropertyOwnerIds(
    opts.propertyId,
    opts.preferredOwnerId,
  );
  let ok = 0;
  for (const userId of recipients) {
    const inserted = await createNotification({
      userId,
      propertyId: opts.propertyId,
      type: opts.type,
      title: opts.title,
      body: opts.body,
      data: opts.data,
    });
    if (inserted) ok += 1;
  }
  return ok;
}

/** Ensure live-ops tables exist even if SQL migration was not applied yet. */
let liveOpsReady: Promise<void> | null = null;

export async function ensureLiveOpsSchema(): Promise<void> {
  if (!liveOpsReady) {
    liveOpsReady = (async () => {
      try {
        await query(`
          DO $$ BEGIN
            ALTER TYPE complaint_status ADD VALUE 'assigned';
          EXCEPTION WHEN duplicate_object THEN NULL;
          END $$;
        `);
      } catch {
        /* enum already has assigned, or type missing in empty DB */
      }

      await query(
        `ALTER TABLE complaints
           ADD COLUMN IF NOT EXISTS photo_urls TEXT[] NOT NULL DEFAULT '{}'`,
      ).catch(() => undefined);
      await query(
        `ALTER TABLE complaints ADD COLUMN IF NOT EXISTS ticket_number TEXT`,
      ).catch(() => undefined);

      await query(`
        CREATE TABLE IF NOT EXISTS mess_menus (
          id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          property_id     UUID NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
          day_of_week     SMALLINT NOT NULL CHECK (day_of_week BETWEEN 1 AND 7),
          breakfast       TEXT NOT NULL DEFAULT '',
          lunch           TEXT NOT NULL DEFAULT '',
          dinner          TEXT NOT NULL DEFAULT '',
          updated_by      UUID REFERENCES users(id),
          created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
          updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
          UNIQUE (property_id, day_of_week)
        )
      `).catch((err) => console.warn('[live-ops] mess_menus ensure:', err));

      await query(`
        CREATE TABLE IF NOT EXISTS meter_readings (
          id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          property_id           UUID NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
          unit_id               UUID NOT NULL REFERENCES hierarchy_nodes(id) ON DELETE CASCADE,
          tenancy_id            UUID REFERENCES tenancies(id) ON DELETE SET NULL,
          meter_reading_value   NUMERIC(14,3) NOT NULL,
          previous_reading      NUMERIC(14,3),
          units_consumed        NUMERIC(14,3),
          rate_per_unit         NUMERIC(12,4),
          amount                NUMERIC(12,2),
          meter_image_url       TEXT,
          billing_cycle         TEXT NOT NULL,
          submitted_by          UUID NOT NULL REFERENCES users(id),
          invoice_id            UUID REFERENCES invoices(id) ON DELETE SET NULL,
          invoice_line_item_id  UUID REFERENCES invoice_line_items(id) ON DELETE SET NULL,
          created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
        )
      `).catch((err) => console.warn('[live-ops] meter_readings ensure:', err));

      await query(`
        CREATE TABLE IF NOT EXISTS gate_passes (
          id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          property_id     UUID NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
          unit_id         UUID NOT NULL REFERENCES hierarchy_nodes(id) ON DELETE CASCADE,
          tenancy_id      UUID REFERENCES tenancies(id) ON DELETE SET NULL,
          requested_by    UUID NOT NULL REFERENCES users(id),
          visitor_name    TEXT NOT NULL,
          purpose         TEXT NOT NULL DEFAULT 'visitor',
          notes           TEXT,
          status          TEXT NOT NULL DEFAULT 'pending',
          decided_by      UUID REFERENCES users(id),
          decided_at      TIMESTAMPTZ,
          valid_until     TIMESTAMPTZ,
          created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
          updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
        )
      `).catch((err) => console.warn('[live-ops] gate_passes ensure:', err));
    })();
  }
  return liveOpsReady;
}
