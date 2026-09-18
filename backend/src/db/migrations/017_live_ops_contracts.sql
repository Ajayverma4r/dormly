-- 017_live_ops_contracts.sql
-- Shared tenant ↔ owner live-ops tables: complaint photos/status, mess menus, meter readings.

-- Allow owner workflow statuses used by the tenant tracker UI.
DO $$ BEGIN
  ALTER TYPE complaint_status ADD VALUE 'assigned';
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE complaints
  ADD COLUMN IF NOT EXISTS photo_urls TEXT[] NOT NULL DEFAULT '{}';

ALTER TABLE complaints
  ADD COLUMN IF NOT EXISTS ticket_number TEXT;

UPDATE complaints
SET ticket_number = 'CMP-' || UPPER(SUBSTRING(REPLACE(id::text, '-', ''), 1, 8))
WHERE ticket_number IS NULL;

-- Weekly mess menu per property (hostel / PG).
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
);
CREATE INDEX IF NOT EXISTS idx_mess_menus_property ON mess_menus(property_id);

-- Utility meter readings for flats / rental houses / commercial EB.
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
);
CREATE INDEX IF NOT EXISTS idx_meter_readings_property ON meter_readings(property_id);
CREATE INDEX IF NOT EXISTS idx_meter_readings_unit ON meter_readings(unit_id);
CREATE INDEX IF NOT EXISTS idx_meter_readings_tenancy ON meter_readings(tenancy_id);
CREATE INDEX IF NOT EXISTS idx_meter_readings_cycle ON meter_readings(property_id, billing_cycle);
