-- 026_invoice_kind_and_approval.sql
-- Separates rent-cycle invoices from ad hoc charges and records who approved
-- (sent) each invoice. Requires 025. Run scripts/sql/026_invoice_kind_precheck.sql
-- first. The whole migration is one transaction: any failed check rolls it back.
-- The backend detects these columns at runtime and works with or without them.

BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'invoices'
      AND column_name = 'is_auto_generated'
  ) THEN
    RAISE EXCEPTION '026: invoices.is_auto_generated missing — apply 025 first';
  END IF;
END $$;

-- 'cycle' = rent invoice for one move-in-anniversary billing period
--           (at most one per tenancy per period_start).
-- 'adhoc' = one-off charge (fine, repair, deposit top-up); never blocks a cycle.
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS invoice_kind TEXT;

-- Historical rows: the only ad hoc path so far ("Add Charge") creates a manual
-- invoice whose period is a single day. Everything else stays 'cycle'.
UPDATE invoices
SET invoice_kind = CASE
  WHEN NOT is_auto_generated AND period_start = period_end THEN 'adhoc'
  ELSE 'cycle'
END
WHERE invoice_kind IS NULL;

ALTER TABLE invoices ALTER COLUMN invoice_kind SET DEFAULT 'cycle';
ALTER TABLE invoices ALTER COLUMN invoice_kind SET NOT NULL;

DO $$
BEGIN
  ALTER TABLE invoices
    ADD CONSTRAINT invoices_invoice_kind_check
    CHECK (invoice_kind IN ('cycle', 'adhoc'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Set when an owner/admin/manager approves (sends) an invoice. NULL on
-- historical rows: the approver was never recorded and is not guessed.
ALTER TABLE invoices
  ADD COLUMN IF NOT EXISTS approved_by UUID REFERENCES users(id) ON DELETE SET NULL;

-- Existing duplicates are never deleted or merged automatically.
DO $$
DECLARE
  dup_groups INT;
BEGIN
  SELECT COUNT(*) INTO dup_groups FROM (
    SELECT 1 FROM invoices
    WHERE invoice_kind = 'cycle'
    GROUP BY tenancy_id, period_start
    HAVING COUNT(*) > 1
  ) d;
  IF dup_groups > 0 THEN
    RAISE EXCEPTION '026: % duplicate cycle invoice group(s) on (tenancy_id, period_start); resolve manually (see precheck query 6)', dup_groups;
  END IF;
END $$;

-- One rent-cycle invoice per tenancy per billing-period start.
CREATE UNIQUE INDEX IF NOT EXISTS invoices_cycle_tenancy_period_start_uniq
  ON invoices (tenancy_id, period_start)
  WHERE invoice_kind = 'cycle';

-- Replaced by the partial index above (ad hoc charges may share a start date).
DROP INDEX IF EXISTS invoices_tenancy_period_start_uniq;

COMMIT;
