-- 016_notification_data.sql
-- Optional JSON payload for deep-links (e.g. move-out request → tenant profile).

ALTER TABLE notifications
  ADD COLUMN IF NOT EXISTS data JSONB NOT NULL DEFAULT '{}'::jsonb;
