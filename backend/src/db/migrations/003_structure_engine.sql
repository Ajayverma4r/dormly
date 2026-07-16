-- 003_structure_engine.sql
-- The single source of truth every operational module builds on.
-- No column here or anywhere downstream is named building/floor/room/bed.

CREATE TABLE hierarchy_levels (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id             UUID NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
    display_name            TEXT NOT NULL,
    internal_key            TEXT NOT NULL,             -- immutable slug, set once at creation
    icon                    TEXT,
    color                   TEXT,
    order_index             INT NOT NULL,
    parent_level_id         UUID REFERENCES hierarchy_levels(id) ON DELETE CASCADE,
    is_enabled              BOOLEAN NOT NULL DEFAULT true,
    allow_multiple_children BOOLEAN NOT NULL DEFAULT true,
    supports_occupancy      BOOLEAN NOT NULL DEFAULT false,
    supports_assets         BOOLEAN NOT NULL DEFAULT false,
    supports_complaints     BOOLEAN NOT NULL DEFAULT false,
    visibility              TEXT NOT NULL DEFAULT 'internal',   -- internal | public
    metadata                JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (property_id, internal_key)
);
CREATE INDEX idx_hierarchy_levels_property ON hierarchy_levels(property_id);
CREATE INDEX idx_hierarchy_levels_parent ON hierarchy_levels(parent_level_id);

CREATE TABLE hierarchy_nodes (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id     UUID NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
    level_id        UUID NOT NULL REFERENCES hierarchy_levels(id) ON DELETE CASCADE,
    parent_node_id  UUID REFERENCES hierarchy_nodes(id) ON DELETE CASCADE,
    name            TEXT NOT NULL,
    code            TEXT,                       -- optional short code, e.g. "A-204"
    order_index     INT NOT NULL DEFAULT 0,
    is_active       BOOLEAN NOT NULL DEFAULT true,
    metadata        JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_hierarchy_nodes_property ON hierarchy_nodes(property_id);
CREATE INDEX idx_hierarchy_nodes_level ON hierarchy_nodes(level_id);
CREATE INDEX idx_hierarchy_nodes_parent ON hierarchy_nodes(parent_node_id);
