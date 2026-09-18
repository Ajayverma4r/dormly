-- 018_gate_passes.sql
-- Apartment / society visitor & delivery gate passes (tenant ↔ owner).

CREATE TABLE IF NOT EXISTS gate_passes (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id     UUID NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
    unit_id         UUID NOT NULL REFERENCES hierarchy_nodes(id) ON DELETE CASCADE,
    tenancy_id      UUID REFERENCES tenancies(id) ON DELETE SET NULL,
    requested_by    UUID NOT NULL REFERENCES users(id),
    visitor_name    TEXT NOT NULL,
    purpose         TEXT NOT NULL DEFAULT 'visitor',
    notes           TEXT,
    status          TEXT NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending', 'approved', 'denied', 'expired')),
    decided_by      UUID REFERENCES users(id),
    decided_at      TIMESTAMPTZ,
    valid_until     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_gate_passes_property ON gate_passes(property_id);
CREATE INDEX IF NOT EXISTS idx_gate_passes_tenancy ON gate_passes(tenancy_id);
