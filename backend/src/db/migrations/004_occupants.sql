-- 004_occupants.sql
-- First operational module. Notice it only ever references node_id + property_id —
-- never a level name. Every future module (visitors, complaints, assets...) follows
-- this exact same shape.

CREATE TYPE occupant_status AS ENUM ('active', 'moved_out', 'pending');

CREATE TABLE occupants (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id     UUID NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
    node_id         UUID NOT NULL REFERENCES hierarchy_nodes(id) ON DELETE CASCADE,
    name            TEXT NOT NULL,
    phone           TEXT,
    status          occupant_status NOT NULL DEFAULT 'active',
    moved_in_at     TIMESTAMPTZ,
    moved_out_at    TIMESTAMPTZ,
    metadata        JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_occupants_property ON occupants(property_id);
CREATE INDEX idx_occupants_node ON occupants(node_id);
