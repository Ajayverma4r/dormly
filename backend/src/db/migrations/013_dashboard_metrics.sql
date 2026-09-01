-- 013_dashboard_metrics.sql
--
-- Schema additions to power the property dashboard:
--   • Monthly financial stats (expected / received / pending rent)
--   • Total expenses (this month)
--   • Rent defaulters & reminder tracking
--   • KYC workflow on tenancies
--   • Upcoming vacancies (notice / planned move-out)
--
-- NOTE: Open complaints and active-tenant counts are already supported by
--       005_tenancy_and_roles.sql + 007_complaints.sql — only indexes added here.
-- Safe to re-run: enums/tables/indexes use idempotent guards.

-- ---------------------------------------------------------------------------
-- 1. Tenancy: monthly rent + KYC + vacancy planning
-- ---------------------------------------------------------------------------

DO $$ BEGIN
  CREATE TYPE kyc_status AS ENUM ('pending', 'submitted', 'verified', 'rejected');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE tenancies
  ADD COLUMN IF NOT EXISTS monthly_rent        NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS kyc_status          kyc_status NOT NULL DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS kyc_verified_at     TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS kyc_verified_by     UUID REFERENCES users(id),
  ADD COLUMN IF NOT EXISTS notice_given_at     TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS planned_move_out_at TIMESTAMPTZ;

COMMENT ON COLUMN tenancies.monthly_rent IS
  'Contractual monthly rent for this tenancy. Used for Expected Rent on the dashboard when invoices have not been generated yet.';
COMMENT ON COLUMN tenancies.kyc_status IS
  'KYC workflow state. Dashboard "Needs Attention" counts tenancies where kyc_status IN (''pending'',''submitted'').';
COMMENT ON COLUMN tenancies.notice_given_at IS
  'When the tenant gave move-out notice.';
COMMENT ON COLUMN tenancies.planned_move_out_at IS
  'Scheduled vacate date while tenancy is still active. Dashboard upcoming-vacancy widget queries this column (next 30 days).';
COMMENT ON COLUMN tenancies.move_out_at IS
  'Actual move-out timestamp — set when the tenancy ends. Do not use for upcoming-vacancy forecasts.';

-- Best-effort backfill: tenants with core docs on file are at least "submitted".
UPDATE tenancies
SET kyc_status = 'submitted'
WHERE kyc_status = 'pending'
  AND aadhaar_number IS NOT NULL
  AND TRIM(aadhaar_number) <> ''
  AND profile_photo_url IS NOT NULL
  AND TRIM(profile_photo_url) <> '';

-- Optional per-document store (Aadhaar, PAN, agreement, etc.)
DO $$ BEGIN
  CREATE TYPE tenant_document_type AS ENUM (
    'aadhaar', 'pan', 'photo', 'agreement', 'address_proof', 'other'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS tenant_documents (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenancy_id      UUID NOT NULL REFERENCES tenancies(id) ON DELETE CASCADE,
  doc_type        tenant_document_type NOT NULL,
  file_url        TEXT NOT NULL,
  status          kyc_status NOT NULL DEFAULT 'submitted',
  uploaded_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  verified_at     TIMESTAMPTZ,
  verified_by     UUID REFERENCES users(id),
  notes           TEXT,
  UNIQUE (tenancy_id, doc_type)
);

CREATE INDEX IF NOT EXISTS idx_tenant_documents_tenancy ON tenant_documents(tenancy_id);

-- ---------------------------------------------------------------------------
-- 2. Expenses (NEW — no prior table existed)
-- ---------------------------------------------------------------------------

DO $$ BEGIN
  CREATE TYPE expense_category AS ENUM (
    'maintenance', 'utilities', 'salaries', 'supplies', 'taxes', 'other'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS expenses (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id     UUID NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
  node_id         UUID REFERENCES hierarchy_nodes(id) ON DELETE SET NULL,
  category        expense_category NOT NULL DEFAULT 'other',
  description     TEXT NOT NULL,
  amount          NUMERIC(12,2) NOT NULL CHECK (amount >= 0),
  expense_date    DATE NOT NULL DEFAULT CURRENT_DATE,
  vendor_name     TEXT,
  receipt_url     TEXT,
  recorded_by     UUID REFERENCES users(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_expenses_property_date ON expenses(property_id, expense_date DESC);
CREATE INDEX IF NOT EXISTS idx_expenses_property_category ON expenses(property_id, category);

-- ---------------------------------------------------------------------------
-- 3. Billing: reminder audit + dashboard query indexes
-- ---------------------------------------------------------------------------

ALTER TABLE invoices
  ADD COLUMN IF NOT EXISTS last_reminder_sent_at TIMESTAMPTZ;

COMMENT ON COLUMN invoices.last_reminder_sent_at IS
  'Timestamp of the most recent rent reminder sent for this invoice (dashboard defaulter bell).';

CREATE INDEX IF NOT EXISTS idx_invoices_property_status_due
  ON invoices(property_id, status, due_date);

CREATE INDEX IF NOT EXISTS idx_invoices_property_period
  ON invoices(property_id, period_start, period_end);

CREATE INDEX IF NOT EXISTS idx_payments_paid_at
  ON payments(paid_at DESC);

-- ---------------------------------------------------------------------------
-- 4. Complaints + tenancies: dashboard count / list indexes
-- ---------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_complaints_property_status
  ON complaints(property_id, status);

CREATE INDEX IF NOT EXISTS idx_tenancies_property_status
  ON tenancies(property_id, status);

CREATE INDEX IF NOT EXISTS idx_tenancies_upcoming_vacancy
  ON tenancies(property_id, planned_move_out_at)
  WHERE status = 'active' AND planned_move_out_at IS NOT NULL;
