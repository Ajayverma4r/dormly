-- deploy_readiness_readonly.sql
-- READ-ONLY deployment readiness checks (A–H). Run manually in the Supabase SQL
-- editor; nothing is written. Every query runs whether or not migrations
-- 025/026 are applied: optional invoice columns are read through to_jsonb(row).
-- Run 026_invoice_kind_precheck.sql as well before applying 026.

BEGIN TRANSACTION READ ONLY;

-- A. Billing columns that exist (tells you whether 019 / 025 / 026 are applied).
SELECT table_name, column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND ((table_name = 'invoices' AND column_name IN
        ('sent_at', 'is_auto_generated', 'overdue_notified_at', 'invoice_kind', 'approved_by'))
    OR (table_name = 'invoice_line_items' AND column_name = 'charge_kind')
    OR (table_name = 'tenancies' AND column_name = 'include_past_rent_arrears'))
ORDER BY table_name, column_name;

-- B. Invoice indexes, and whether each is valid/ready.
SELECT c.relname AS index_name, i.indisunique, i.indisvalid, i.indisready,
       pg_get_indexdef(i.indexrelid) AS definition
FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
WHERE i.indrelid = 'public.invoices'::regclass
ORDER BY c.relname;

-- C. Invoice constraints (invoice_kind check, approved_by FK after 026).
SELECT conname, contype, pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid = 'public.invoices'::regclass
ORDER BY conname;

-- D. Property time zones and how the backend will interpret each.
--    'UTC' is honoured as UTC (not Asia/Kolkata). Missing/invalid → Asia/Kolkata.
--    Review every non-Asia/Kolkata row before deploying; never auto-updated.
SELECT p.timezone AS stored_value,
       COUNT(*)   AS properties,
       CASE
         WHEN p.timezone IS NULL OR btrim(p.timezone) = '' THEN 'missing → Asia/Kolkata'
         WHEN EXISTS (SELECT 1 FROM pg_timezone_names n
                       WHERE lower(n.name) = lower(btrim(p.timezone))) THEN 'valid, used as configured'
         ELSE 'invalid → Asia/Kolkata'
       END AS backend_interpretation
FROM properties p
GROUP BY p.timezone
ORDER BY properties DESC;

-- E1. Duplicate (tenancy_id, period_start) groups across all invoices.
SELECT tenancy_id, period_start, COUNT(*) AS n
FROM invoices
GROUP BY tenancy_id, period_start
HAVING COUNT(*) > 1;

-- E2. Duplicates among rows that stay 'cycle' after 026 (must be 0 rows or 026 aborts).
SELECT i.tenancy_id, i.period_start, COUNT(*) AS n
FROM invoices i
WHERE NOT (NOT COALESCE((to_jsonb(i) ->> 'is_auto_generated')::boolean, false)
           AND i.period_start = i.period_end)
GROUP BY i.tenancy_id, i.period_start
HAVING COUNT(*) > 1;

-- F. Rows 026 will label 'adhoc'; and, after 026, rows the explicit
--    LEGACY_INVOICE_INDEX_CLEANUP step would relabel (NULL before 026).
SELECT
  COUNT(*) FILTER (
    WHERE NOT COALESCE((to_jsonb(i) ->> 'is_auto_generated')::boolean, false)
      AND i.period_start = i.period_end)                         AS will_be_adhoc_by_026,
  CASE WHEN bool_or(to_jsonb(i) ? 'approved_by') THEN
    COUNT(*) FILTER (
      WHERE to_jsonb(i) ->> 'invoice_kind' = 'cycle'
        AND NOT COALESCE((to_jsonb(i) ->> 'is_auto_generated')::boolean, false)
        AND i.period_start = i.period_end
        AND to_jsonb(i) ->> 'approved_by' IS NULL)
  END                                                            AS cleanup_would_relabel
FROM invoices i;

-- G. Enum values and live-ops tables that older builds created at startup.
SELECT t.typname, e.enumlabel
FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
WHERE t.typname IN ('complaint_status', 'invoice_charge_kind')
ORDER BY t.typname, e.enumsortorder;

SELECT to_regclass('public.mess_menus')     IS NOT NULL AS mess_menus,
       to_regclass('public.meter_readings') IS NOT NULL AS meter_readings,
       to_regclass('public.gate_passes')    IS NOT NULL AS gate_passes;

-- H. Same verdict as the backend's startup check (shared/startup/schema-readiness.ts).
--    Every *_ok must be true or the backend refuses to start while
--    DB_SCHEMA_AUTO_MIGRATE is off.
SELECT
  EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public'
          AND table_name = 'notifications' AND column_name = 'data')                 AS notifications_data_ok,
  (SELECT COUNT(*) = 2 FROM information_schema.columns WHERE table_schema = 'public'
          AND table_name = 'complaints' AND column_name IN ('photo_urls', 'ticket_number')) AS complaints_cols_ok,
  EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
          WHERE t.typname = 'complaint_status' AND e.enumlabel = 'assigned')        AS complaint_assigned_ok,
  (to_regclass('public.mess_menus') IS NOT NULL
   AND to_regclass('public.meter_readings') IS NOT NULL
   AND to_regclass('public.gate_passes') IS NOT NULL)                               AS live_ops_tables_ok,
  EXISTS (SELECT 1 FROM pg_type WHERE typname = 'invoice_charge_kind')              AS charge_kind_type_ok,
  (SELECT COUNT(*) = 2 FROM information_schema.columns WHERE table_schema = 'public'
          AND ((table_name = 'invoice_line_items' AND column_name = 'charge_kind')
            OR (table_name = 'tenancies' AND column_name = 'include_past_rent_arrears'))) AS migration_019_ok,
  (SELECT COUNT(*) = 3 FROM information_schema.columns WHERE table_schema = 'public'
          AND table_name = 'invoices'
          AND column_name IN ('sent_at', 'is_auto_generated', 'overdue_notified_at'))  AS migration_025_ok,
  EXISTS (SELECT 1 FROM pg_index ix JOIN pg_class c ON c.oid = ix.indexrelid
          WHERE ix.indisunique AND ix.indisvalid AND ix.indisready
            AND c.relname IN ('invoices_cycle_tenancy_period_start_uniq',
                              'invoices_tenancy_period_start_uniq'))                AS invoice_unique_index_ok;

ROLLBACK;
