-- 006_billing.sql
-- Billing is deliberately generic: charge_types is owner-configurable per
-- property (Rent/Electricity/Water/Maintenance/Other are DEFAULTS auto-seeded
-- on property creation, not hardcoded columns anywhere downstream).

CREATE TABLE charge_types (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id     UUID NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
    name            TEXT NOT NULL,
    default_amount  NUMERIC(12,2) NOT NULL DEFAULT 0,
    is_recurring    BOOLEAN NOT NULL DEFAULT true,
    order_index     INT NOT NULL DEFAULT 0,
    is_active       BOOLEAN NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_charge_types_property ON charge_types(property_id);

CREATE TYPE invoice_status AS ENUM ('pending', 'partial', 'paid', 'overdue');

CREATE TABLE invoices (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenancy_id      UUID NOT NULL REFERENCES tenancies(id) ON DELETE CASCADE,
    property_id     UUID NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
    period_start    DATE NOT NULL,
    period_end      DATE NOT NULL,
    due_date        DATE NOT NULL,
    total_amount    NUMERIC(12,2) NOT NULL DEFAULT 0,
    status          invoice_status NOT NULL DEFAULT 'pending',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_invoices_tenancy ON invoices(tenancy_id);
CREATE INDEX idx_invoices_property ON invoices(property_id);

CREATE TABLE invoice_line_items (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_id      UUID NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
    charge_type_id  UUID REFERENCES charge_types(id),
    description     TEXT NOT NULL,
    amount          NUMERIC(12,2) NOT NULL
);
CREATE INDEX idx_invoice_line_items_invoice ON invoice_line_items(invoice_id);

CREATE TABLE payments (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_id      UUID NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
    amount          NUMERIC(12,2) NOT NULL,
    method          TEXT NOT NULL DEFAULT 'cash',
    note            TEXT,
    recorded_by     UUID REFERENCES users(id),
    paid_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_payments_invoice ON payments(invoice_id);

-- Generic notification log — reminders write here now (console-logged),
-- and this same table is ready for Push/SMS/WhatsApp/Email providers later
-- without any schema change.
CREATE TABLE notifications (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id),
    property_id     UUID REFERENCES properties(id),
    type            TEXT NOT NULL DEFAULT 'general',
    title           TEXT NOT NULL,
    body            TEXT NOT NULL,
    read_at         TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_notifications_user ON notifications(user_id);