-- 027_complaint_comments_precheck.sql
-- READ-ONLY. Run in the Supabase SQL editor before applying migration 027, and
-- again afterwards to confirm sections 0 and 5-8.
-- Every statement is a SELECT inside a READ ONLY transaction; nothing is written.

BEGIN TRANSACTION READ ONLY;

-- 0. Migration state (all false before 027 is applied).
SELECT
  EXISTS (SELECT 1 FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'complaints'
            AND column_name = 'assigned_to')            AS has_027_assigned_to,
  to_regclass('public.complaint_comments') IS NOT NULL  AS has_027_complaint_comments;

-- 1. Current complaints columns (027 only adds assigned_to/assigned_by/assigned_at).
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'complaints'
ORDER BY ordinal_position;

-- 2. Complaint volume per status (027 changes no existing rows).
SELECT status::text AS status, COUNT(*) AS complaints
FROM complaints
GROUP BY status
ORDER BY status;

-- 3. gen_random_uuid() must be available for the new table's default.
SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'gen_random_uuid') AS has_gen_random_uuid;

-- 4. Referenced tables exist.
SELECT to_regclass('public.users') IS NOT NULL      AS has_users,
       to_regclass('public.properties') IS NOT NULL AS has_properties;

-- 5. Row-level security and owner of complaint_comments (and complaints for
--    comparison). Before 027: only the complaints row. After 027 expect
--    complaint_comments with rls_enabled = true and rls_forced = false.
SELECT c.relname,
       pg_get_userbyid(c.relowner) AS owner,
       c.relrowsecurity            AS rls_enabled,
       c.relforcerowsecurity       AS rls_forced
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relname IN ('complaints', 'complaint_comments')
ORDER BY c.relname;

-- 6. Policies on complaint_comments. Expect 0 rows (no client-facing policies).
SELECT policyname, roles, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'complaint_comments';

-- 7. Supabase API-role privileges on complaint_comments. After 027 expect every
--    column false. No rows when the table or the roles do not exist.
SELECT r.rolname,
       has_table_privilege(r.oid, c.oid, 'SELECT') AS can_select,
       has_table_privilege(r.oid, c.oid, 'INSERT') AS can_insert,
       has_table_privilege(r.oid, c.oid, 'UPDATE') AS can_update,
       has_table_privilege(r.oid, c.oid, 'DELETE') AS can_delete
FROM pg_roles r
CROSS JOIN pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE r.rolname IN ('anon', 'authenticated')
  AND n.nspname = 'public' AND c.relname = 'complaint_comments'
ORDER BY r.rolname;

-- 8. Backend role. Replace <backend_role> with ONLY the username part of the
--    backend's DATABASE_URL (Supabase pooler "postgres.<project-ref>" means
--    role "postgres"); never paste the URL or password here. The backend keeps
--    access only if it owns the table (owns_* = true) or rolbypassrls = true.
--    Returns no rows until the placeholder is replaced.
SELECT r.rolname,
       r.rolsuper,
       r.rolbypassrls,
       EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
               WHERE n.nspname = 'public' AND c.relname = 'complaints'
                 AND c.relowner = r.oid)         AS owns_complaints,
       EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
               WHERE n.nspname = 'public' AND c.relname = 'complaint_comments'
                 AND c.relowner = r.oid)         AS owns_complaint_comments,
       current_user                              AS checked_by
FROM pg_roles r
WHERE r.rolname = '<backend_role>';

ROLLBACK;
