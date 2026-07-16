-- 005_tenancy_and_roles.sql

-- Manager/Staff scoping: which specific properties can this member act on?
-- Owners/Admins are NOT listed here — their organization membership already
-- implies access to every property in the org. Only manager/staff need
-- per-property scoping rows.
CREATE TABLE property_staff_assignments (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id),
    property_id     UUID NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
    role            membership_role NOT NULL DEFAULT 'staff', -- 'manager' or 'staff'
    assigned_by     UUID REFERENCES users(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, property_id)
);
CREATE INDEX idx_staff_assignments_user ON property_staff_assignments(user_id);
CREATE INDEX idx_staff_assignments_property ON property_staff_assignments(property_id);

-- A tenant's link to their specific unit. This is node-scoped, not org-scoped —
-- it deliberately does NOT reuse `memberships`, because a tenant is not a
-- member of the owner's organization.
CREATE TYPE tenancy_status AS ENUM ('active', 'ended', 'pending');

CREATE TABLE tenancies (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL REFERENCES users(id),
    property_id         UUID NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
    node_id             UUID NOT NULL REFERENCES hierarchy_nodes(id) ON DELETE CASCADE,
    full_name           TEXT NOT NULL,
    email               TEXT,
    address             TEXT,
    company_name        TEXT,
    aadhaar_number      TEXT,
    profile_photo_url   TEXT,
    agreement_pdf_url   TEXT,
    move_in_at          TIMESTAMPTZ,
    move_out_at         TIMESTAMPTZ,
    security_deposit    NUMERIC(12,2),
    status              tenancy_status NOT NULL DEFAULT 'active',
    notes               TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_tenancies_user ON tenancies(user_id);
CREATE INDEX idx_tenancies_property ON tenancies(property_id);
CREATE INDEX idx_tenancies_node ON tenancies(node_id);

-- NOTE: the existing `occupants` table (migration 004) stays as a lightweight
-- "who is currently at this node" record used by non-billing modules
-- (complaints, visitors). `tenancies` is the richer, authenticated,
-- billing-capable profile. We are not deleting occupants — reports/analytics
-- may still reference it directly. This mirrors real systems where "who's
-- physically here" and "who has a legal/billing relationship" can differ.