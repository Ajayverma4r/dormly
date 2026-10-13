-- 026_invoice_kind_precheck.sql
-- READ-ONLY. Run in the Supabase SQL editor before reviewing migration 026.
-- Every statement is a SELECT inside a READ ONLY transaction; nothing is written.
--
-- Works whether or not migrations 025/026 are applied: optional columns
-- (sent_at, is_auto_generated, invoice_kind, approved_by) are read through
-- to_jsonb(row), so a missing column yields NULL instead of an error that
-- would abort the rest of the transaction. Before 025 every invoice counts as
-- sent and manual (that is what 025's backfill does).
-- Stored property timezones are validated against pg_timezone_names; missing
-- or invalid values use Asia/Kolkata, matching the backend's policy.

BEGIN TRANSACTION READ ONLY;

-- 0. Migration state. 026 aborts unless 025 (is_auto_generated) is applied.
SELECT
  bool_or(column_name = 'sent_at')             AS has_025_sent_at,
  bool_or(column_name = 'is_auto_generated')   AS has_025_is_auto_generated,
  bool_or(column_name = 'overdue_notified_at') AS has_025_overdue_notified_at,
  bool_or(column_name = 'invoice_kind')        AS has_026_invoice_kind,
  bool_or(column_name = 'approved_by')         AS has_026_approved_by
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'invoices';

-- 1. invoices columns (expect sent_at, is_auto_generated, overdue_notified_at from 025;
--    invoice_kind and approved_by should NOT exist yet).
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'invoices'
ORDER BY ordinal_position;

-- 2. Indexes and constraints on invoices
--    (expect invoices_tenancy_period_start_uniq from 025).
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public' AND tablename = 'invoices'
ORDER BY indexname;

SELECT conname, pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid = 'public.invoices'::regclass
ORDER BY conname;

-- 3. Invoice population by workflow state.
WITH inv AS (
  SELECT i.period_start, i.period_end,
         COALESCE((to_jsonb(i) ->> 'is_auto_generated')::boolean, false) AS is_auto,
         (NOT (to_jsonb(i) ? 'sent_at') OR to_jsonb(i) ->> 'sent_at' IS NOT NULL) AS is_sent
  FROM invoices i
)
SELECT
  COUNT(*)                                                      AS total,
  COUNT(*) FILTER (WHERE NOT is_sent)                           AS drafts,
  COUNT(*) FILTER (WHERE is_sent)                               AS sent,
  COUNT(*) FILTER (WHERE is_auto)                               AS auto_generated,
  COUNT(*) FILTER (WHERE NOT is_auto)                           AS manual,
  COUNT(*) FILTER (WHERE period_start = period_end)             AS single_day_period,
  COUNT(*) FILTER (WHERE NOT is_auto
                     AND period_start = period_end)             AS will_backfill_adhoc,
  COUNT(*) FILTER (WHERE period_start > period_end)             AS inverted_period
FROM inv;

-- 4. Rows the backfill will classify as 'adhoc' (manual + single-day period).
--    Review: each should be an "Add Charge" style invoice, not a rent cycle.
SELECT i.id, i.tenancy_id, i.property_id, i.period_start, i.period_end,
       i.due_date, i.total_amount, i.status,
       (NOT (to_jsonb(i) ? 'sent_at') OR to_jsonb(i) ->> 'sent_at' IS NOT NULL) AS is_sent,
       (SELECT string_agg(li.description, ' | ' ORDER BY li.description)
          FROM invoice_line_items li WHERE li.invoice_id = i.id) AS line_items
FROM invoices i
WHERE NOT COALESCE((to_jsonb(i) ->> 'is_auto_generated')::boolean, false)
  AND i.period_start = i.period_end
ORDER BY i.created_at DESC
LIMIT 200;

-- 5. Duplicate (tenancy_id, period_start) groups. Must be 0 rows for the
--    cycle-only unique index; with the 025 index present this should already be 0.
SELECT tenancy_id, period_start, COUNT(*) AS n,
       array_agg(id ORDER BY created_at) AS invoice_ids
FROM invoices
GROUP BY tenancy_id, period_start
HAVING COUNT(*) > 1;

-- 6. Same check restricted to rows that will remain 'cycle' after backfill.
SELECT i.tenancy_id, i.period_start, COUNT(*) AS n
FROM invoices i
WHERE NOT (NOT COALESCE((to_jsonb(i) ->> 'is_auto_generated')::boolean, false)
           AND i.period_start = i.period_end)
GROUP BY i.tenancy_id, i.period_start
HAVING COUNT(*) > 1;

-- 7. Invoices whose property differs from their tenancy's property (integrity).
SELECT i.id, i.property_id AS invoice_property, t.property_id AS tenancy_property
FROM invoices i JOIN tenancies t ON t.id = i.tenancy_id
WHERE i.property_id <> t.property_id;

-- 8. total_amount vs line-item sum (catches partially written drafts).
SELECT i.id, i.total_amount, COALESCE(SUM(li.amount), 0) AS line_sum,
       COUNT(li.id) AS line_count,
       (to_jsonb(i) ? 'sent_at' AND to_jsonb(i) ->> 'sent_at' IS NULL) AS is_draft
FROM invoices i
LEFT JOIN invoice_line_items li ON li.invoice_id = i.id
GROUP BY i.id
HAVING i.total_amount <> COALESCE(SUM(li.amount), 0) OR COUNT(li.id) = 0;

-- 9. Over-paid invoices (payments exceed total).
SELECT i.id, i.total_amount, SUM(p.amount) AS paid
FROM invoices i JOIN payments p ON p.invoice_id = i.id
GROUP BY i.id
HAVING SUM(p.amount) > i.total_amount;

-- 10. Drafts already marked overdue (Phase 3 concern; informational).
--     Always 0 before 025 (no drafts exist yet).
SELECT COUNT(*) AS drafts_marked_overdue
FROM invoices i
WHERE to_jsonb(i) ? 'sent_at' AND to_jsonb(i) ->> 'sent_at' IS NULL
  AND i.status = 'overdue';

-- 11. Single-day manual invoices that fall on a tenancy's cycle anniversary day.
--     These are the rows that currently block the generator (they collide on
--     period_start). After 026 they become 'adhoc' and stop blocking.
SELECT i.id, i.tenancy_id, i.period_start, z.tz AS billing_time_zone,
       (t.move_in_at AT TIME ZONE z.tz)::date AS check_in
FROM invoices i
JOIN tenancies t ON t.id = i.tenancy_id
JOIN properties p ON p.id = i.property_id
CROSS JOIN LATERAL (
  SELECT COALESCE(
    (SELECT n.name FROM pg_timezone_names n
      WHERE lower(n.name) = lower(btrim(p.timezone)) LIMIT 1),
    'Asia/Kolkata') AS tz
) z
WHERE NOT COALESCE((to_jsonb(i) ->> 'is_auto_generated')::boolean, false)
  AND i.period_start = i.period_end
  AND t.move_in_at IS NOT NULL
  AND EXTRACT(DAY FROM i.period_start)
      = EXTRACT(DAY FROM (t.move_in_at AT TIME ZONE z.tz));

-- 12. Prerequisites for the approved_by foreign key and notifications payload.
SELECT
  to_regclass('public.users')         IS NOT NULL AS users_table_exists,
  (SELECT data_type FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'id') AS users_id_type,
  (SELECT data_type FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'notifications' AND column_name = 'data') AS notifications_data_type;

ROLLBACK;
