-- 025_invoice_review_workflow.sql
-- Draft → review → send workflow for automatically generated rent invoices.
-- Mirrored at runtime by ensureBillingSchema() so older databases self-heal.

-- NULL sent_at = draft (owner has not confirmed; tenant cannot see it).
-- Existing rows are back-filled as already sent via the temporary default.
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS sent_at TIMESTAMPTZ DEFAULT now();
ALTER TABLE invoices ALTER COLUMN sent_at DROP DEFAULT;

ALTER TABLE invoices
  ADD COLUMN IF NOT EXISTS is_auto_generated BOOLEAN NOT NULL DEFAULT false;

-- Set once when the overdue notification is sent; cleared when the due date changes.
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS overdue_notified_at TIMESTAMPTZ;
-- Invoices already past due before this feature shipped are not re-announced.
UPDATE invoices SET overdue_notified_at = now()
WHERE due_date < CURRENT_DATE AND overdue_notified_at IS NULL;

-- At most one invoice per tenancy per billing cycle.
CREATE UNIQUE INDEX IF NOT EXISTS invoices_tenancy_period_start_uniq
  ON invoices (tenancy_id, period_start);
