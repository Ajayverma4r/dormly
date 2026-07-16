-- 002_properties.sql
-- property_type_key is a UX label ONLY. No downstream table or code branches on it.

CREATE TABLE properties (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id     UUID NOT NULL REFERENCES organizations(id),
    name                TEXT NOT NULL,
    property_type_key   TEXT NOT NULL,          -- e.g. 'hostel', 'apartment' — label only
    address             TEXT,
    city                TEXT,
    state               TEXT,
    country             TEXT,
    timezone            TEXT NOT NULL DEFAULT 'UTC',
    currency            TEXT NOT NULL DEFAULT 'USD',
    language             TEXT NOT NULL DEFAULT 'en',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_properties_org ON properties(organization_id);

-- Reference catalogue shown in the wizard. Purely descriptive.
CREATE TABLE property_types (
    key             TEXT PRIMARY KEY,
    display_name    TEXT NOT NULL,
    description     TEXT,
    icon            TEXT
);

-- Suggested hierarchy levels per property type. Copied into hierarchy_levels
-- at property-creation time, then owned entirely by the property from then on.
CREATE TABLE property_type_level_templates (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    property_type_key      TEXT NOT NULL REFERENCES property_types(key),
    display_name            TEXT NOT NULL,
    internal_key             TEXT NOT NULL,
    order_index              INT NOT NULL,
    parent_template_id      UUID REFERENCES property_type_level_templates(id),
    icon                    TEXT,
    color                   TEXT,
    allow_multiple_children BOOLEAN NOT NULL DEFAULT true,
    supports_occupancy      BOOLEAN NOT NULL DEFAULT false,
    supports_assets         BOOLEAN NOT NULL DEFAULT false,
    supports_complaints     BOOLEAN NOT NULL DEFAULT false
);
CREATE INDEX idx_pt_level_templates_type ON property_type_level_templates(property_type_key);
