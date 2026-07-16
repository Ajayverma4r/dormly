-- 007_complaints.sql
CREATE TYPE complaint_status AS ENUM ('open', 'in_progress', 'resolved', 'closed');
CREATE TYPE complaint_priority AS ENUM ('low', 'medium', 'high');

CREATE TABLE complaints (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id     UUID NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
    node_id         UUID NOT NULL REFERENCES hierarchy_nodes(id) ON DELETE CASCADE,
    raised_by       UUID NOT NULL REFERENCES users(id),
    category        TEXT NOT NULL,
    description     TEXT NOT NULL,
    priority        complaint_priority NOT NULL DEFAULT 'medium',
    status          complaint_status NOT NULL DEFAULT 'open',
    resolution_note TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolved_at     TIMESTAMPTZ
);
CREATE INDEX idx_complaints_property ON complaints(property_id);
CREATE INDEX idx_complaints_node ON complaints(node_id);
CREATE INDEX idx_complaints_raised_by ON complaints(raised_by);