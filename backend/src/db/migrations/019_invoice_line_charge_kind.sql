-- 019_invoice_line_charge_kind.sql
-- Invoice line-item charge kinds + tenancy preference for backdated move-in arrears.

DO $$ BEGIN
  CREATE TYPE invoice_charge_kind AS ENUM (
    'rent',
    'electricity',
    'maintenance',
    'previous_dues',
    'other'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE invoice_line_items
  ADD COLUMN IF NOT EXISTS charge_kind invoice_charge_kind;

COMMENT ON COLUMN invoice_line_items.charge_kind IS
  'Semantic charge category for arrears / utilities breakdown (optional; inferred when null).';

ALTER TABLE tenancies
  ADD COLUMN IF NOT EXISTS include_past_rent_arrears BOOLEAN NOT NULL DEFAULT true;

COMMENT ON COLUMN tenancies.include_past_rent_arrears IS
  'When true, first / monthly invoice generation should roll unbilled past rent into Previous Dues.';
