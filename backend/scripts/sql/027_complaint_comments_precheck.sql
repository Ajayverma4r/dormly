-- 027_complaint_comments_precheck.sql
--
-- READ-ONLY check for migration 027 (complaint assignment + comments).
--
-- HOW TO USE
--   1. Open Supabase -> SQL Editor -> New query.
--   2. Copy this WHOLE file, paste it, press Run.
--   3. You get ONE table with columns: Step | Check | Result | What this means.
--   Nothing needs to be replaced or edited.
--
-- This is a single SELECT statement. It only reads catalog information
-- (table names, column types, permissions). It never creates, changes or
-- deletes anything, and it does not read complaint contents or personal data.
--
-- RESULT VALUES
--   READY               This check is fine.
--   NOT READY           Fix this before applying migration 027.
--   NEEDS MANUAL CHECK  The database cannot answer this alone. Read the explanation.
--   NOT APPLICABLE YET  Normal before 027: complaint_comments does not exist yet.
--                       Run this file again after applying 027. It must then say READY.
--   INFO / WARNING      Information only. A WARNING does not block 027.
--
-- Run it before applying 027, and again after applying 027.

WITH
state AS (
  SELECT
    to_regclass('public.complaints') IS NOT NULL         AS has_complaints,
    to_regclass('public.users') IS NOT NULL              AS has_users,
    to_regclass('public.properties') IS NOT NULL         AS has_properties,
    to_regclass('public.complaint_comments') IS NOT NULL AS has_comments,
    EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'complaints'
        AND column_name = 'assigned_to'
    ) AS has_assigned_to
),
comments_table AS (
  SELECT c.oid,
         pg_get_userbyid(c.relowner) AS owner_name,
         c.relrowsecurity            AS rls_enabled,
         c.relforcerowsecurity       AS rls_forced
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'complaint_comments' AND c.relkind = 'r'
),
complaints_table AS (
  SELECT c.oid,
         pg_get_userbyid(c.relowner) AS owner_name,
         c.relrowsecurity            AS rls_enabled
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'complaints' AND c.relkind = 'r'
),
api_roles AS (
  SELECT oid, rolname FROM pg_roles WHERE rolname IN ('anon', 'authenticated')
),
me AS (
  SELECT r.rolname, r.rolsuper, r.rolbypassrls
  FROM pg_roles r
  WHERE r.rolname = current_user
),
checks (sort_order, step, check_name, result, details) AS (

  -- 0. Has 027 already been applied?
  SELECT 10, '0. Migration state', 'Is migration 027 already applied?',
    CASE
      WHEN s.has_assigned_to AND s.has_comments THEN 'INFO'
      WHEN NOT s.has_assigned_to AND NOT s.has_comments THEN 'INFO'
      ELSE 'NOT READY'
    END,
    CASE
      WHEN s.has_assigned_to AND s.has_comments
        THEN 'Already applied: complaints.assigned_to and complaint_comments both exist. Steps 4 to 7 must all say READY.'
      WHEN NOT s.has_assigned_to AND NOT s.has_comments
        THEN 'Not applied yet. This is expected before 027. Steps 4 to 7 will say NOT APPLICABLE YET.'
      ELSE 'Half applied: only one of complaints.assigned_to / complaint_comments exists. Do not continue. Send this result for review.'
    END
  FROM state s

  -- 1. Tables that 027 changes or points to.
  UNION ALL
  SELECT 20, '1. Required tables', 'Do complaints, users and properties exist?',
    CASE WHEN s.has_complaints AND s.has_users AND s.has_properties THEN 'READY' ELSE 'NOT READY' END,
    CASE WHEN s.has_complaints AND s.has_users AND s.has_properties
      THEN 'All three tables exist.'
      ELSE 'Missing table(s): ' || concat_ws(', ',
             CASE WHEN NOT s.has_complaints THEN 'complaints' END,
             CASE WHEN NOT s.has_users THEN 'users' END,
             CASE WHEN NOT s.has_properties THEN 'properties' END)
    END
  FROM state s

  UNION ALL
  SELECT 21, '1. Required columns', 'Are the id columns of complaints, users and properties of type uuid?',
    CASE WHEN x.uuid_count = 3 THEN 'READY' ELSE 'NOT READY' END,
    COALESCE(x.found, 'No id columns found.') || CASE WHEN x.uuid_count = 3 THEN '' ELSE ' (all three must be uuid)' END
  FROM (
    SELECT count(*) FILTER (WHERE data_type = 'uuid') AS uuid_count,
           string_agg(table_name || '.id = ' || data_type, ', ' ORDER BY table_name) AS found
    FROM information_schema.columns
    WHERE table_schema = 'public' AND column_name = 'id'
      AND table_name IN ('complaints', 'users', 'properties')
  ) x

  UNION ALL
  SELECT 22, '1. Required columns', 'Do any assignment columns already exist with a different type?',
    CASE WHEN x.wrong_type = 0 THEN 'READY' ELSE 'NOT READY' END,
    CASE
      WHEN x.present = 0 THEN 'None of assigned_to / assigned_by / assigned_at exist yet. 027 will add them.'
      WHEN x.wrong_type = 0 THEN 'Existing assignment columns have the expected types: ' || x.found
      ELSE 'Unexpected column types: ' || x.found || '. Expected uuid, uuid, timestamp with time zone.'
    END
  FROM (
    SELECT count(*) AS present,
           count(*) FILTER (
             WHERE (column_name IN ('assigned_to', 'assigned_by') AND data_type <> 'uuid')
                OR (column_name = 'assigned_at' AND data_type <> 'timestamp with time zone')
           ) AS wrong_type,
           string_agg(column_name || ' = ' || data_type, ', ' ORDER BY column_name) AS found
    FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'complaints'
      AND column_name IN ('assigned_to', 'assigned_by', 'assigned_at')
  ) x

  -- 2. Needed for new comment ids.
  UNION ALL
  SELECT 30, '2. gen_random_uuid()', 'Is the gen_random_uuid() function available?',
    CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'gen_random_uuid') THEN 'READY' ELSE 'NOT READY' END,
    CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'gen_random_uuid')
      THEN 'Available.'
      ELSE 'Not available. 027 needs it for new comment ids.'
    END

  -- 3. Size only (no complaint contents are read).
  UNION ALL
  SELECT 40, '3. Existing data', 'About how many complaints exist?',
    'INFO',
    'About ' || COALESCE((
      SELECT st.n_live_tup::text FROM pg_stat_user_tables st
      WHERE st.schemaname = 'public' AND st.relname = 'complaints'
    ), 'unknown') || ' complaint rows (estimate). 027 does not change or delete any existing rows.'

  -- 4. Row-level security on complaint_comments.
  UNION ALL
  SELECT 50, '4. RLS on complaint_comments', 'Is row-level security enabled (and not forced)?',
    CASE
      WHEN cc.oid IS NULL THEN 'NOT APPLICABLE YET'
      WHEN cc.rls_enabled AND NOT cc.rls_forced THEN 'READY'
      ELSE 'NOT READY'
    END,
    CASE
      WHEN cc.oid IS NULL
        THEN 'complaint_comments does not exist yet (normal before 027). After 027 this must say READY.'
      WHEN cc.rls_enabled AND NOT cc.rls_forced
        THEN 'RLS is enabled and not forced, as intended.'
      ELSE 'RLS enabled = ' || cc.rls_enabled || ', forced = ' || cc.rls_forced || '. Expected enabled = true, forced = false.'
    END
  FROM (SELECT 1) one
  LEFT JOIN comments_table cc ON true

  -- 5. Ownership.
  UNION ALL
  SELECT 60, '5. Table owner', 'Who owns the existing complaints table?',
    'INFO',
    COALESCE('complaints is owned by role: ' || ct.owner_name, 'complaints table not found.')
  FROM (SELECT 1) one
  LEFT JOIN complaints_table ct ON true

  UNION ALL
  SELECT 61, '5. Table owner', 'Who owns complaint_comments?',
    CASE WHEN cc.oid IS NULL THEN 'NOT APPLICABLE YET' ELSE 'NEEDS MANUAL CHECK' END,
    CASE
      WHEN cc.oid IS NULL
        THEN 'complaint_comments does not exist yet (normal before 027). Whoever runs 027 becomes its owner. If you run 027 from this SQL Editor, the owner will be: ' || current_user || '.'
      ELSE 'complaint_comments is owned by role: ' || cc.owner_name || '. The Render backend must log in as this role, or as a role with BYPASSRLS (see step 8).'
    END
  FROM (SELECT 1) one
  LEFT JOIN comments_table cc ON true

  -- 6. Policies (there should be none).
  UNION ALL
  SELECT 70, '6. Policies on complaint_comments', 'Are there zero RLS policies?',
    CASE
      WHEN cc.oid IS NULL THEN 'NOT APPLICABLE YET'
      WHEN p.n = 0 THEN 'READY'
      ELSE 'NOT READY'
    END,
    CASE
      WHEN cc.oid IS NULL THEN 'complaint_comments does not exist yet (normal before 027).'
      WHEN p.n = 0 THEN 'No policies, so Supabase API users cannot read or write comments.'
      ELSE p.n || ' policy/policies found: ' || p.names || '. 027 expects none. Send this result for review.'
    END
  FROM (SELECT 1) one
  LEFT JOIN comments_table cc ON true
  CROSS JOIN (
    SELECT count(*) AS n, string_agg(policyname, ', ') AS names
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'complaint_comments'
  ) p

  -- 7. Supabase public API roles.
  UNION ALL
  SELECT 80, '7. anon / authenticated', 'Can the public Supabase API roles touch complaint_comments?',
    CASE
      WHEN cc.oid IS NULL THEN 'NOT APPLICABLE YET'
      WHEN a.role_count = 0 THEN 'READY'
      WHEN a.with_access = 0 THEN 'READY'
      ELSE 'NOT READY'
    END,
    CASE
      WHEN cc.oid IS NULL
        THEN 'complaint_comments does not exist yet (normal before 027). After 027 this must say READY.'
      WHEN a.role_count = 0 THEN 'anon / authenticated roles do not exist in this database.'
      WHEN a.with_access = 0 THEN 'anon and authenticated have no access to complaint_comments.'
      ELSE 'These roles still have access: ' || a.names || '. Send this result for review.'
    END
  FROM (SELECT 1) one
  LEFT JOIN comments_table cc ON true
  CROSS JOIN LATERAL (
    SELECT count(*) AS role_count,
           count(*) FILTER (
             WHERE cc.oid IS NOT NULL
               AND has_table_privilege(r.oid, cc.oid, 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE')
           ) AS with_access,
           string_agg(r.rolname, ', ') FILTER (
             WHERE cc.oid IS NOT NULL
               AND has_table_privilege(r.oid, cc.oid, 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE')
           ) AS names
    FROM api_roles r
  ) a

  UNION ALL
  SELECT 81, '7. anon / authenticated', 'For comparison: can they reach the existing complaints table?',
    CASE
      WHEN ct.oid IS NULL OR a.with_access = 0 OR ct.rls_enabled THEN 'INFO'
      ELSE 'WARNING'
    END,
    CASE
      WHEN ct.oid IS NULL THEN 'complaints table not found.'
      WHEN a.with_access = 0 THEN 'anon and authenticated have no access to complaints.'
      WHEN ct.rls_enabled
        THEN 'Roles with table access: ' || a.names || ', but RLS is enabled on complaints, so rows are only visible through its policies.'
      ELSE 'Roles with table access: ' || a.names || ' and RLS is OFF on complaints. This existing table may be readable through the Supabase API. Not caused by 027, but please report it.'
    END
  FROM (SELECT 1) one
  LEFT JOIN complaints_table ct ON true
  CROSS JOIN LATERAL (
    SELECT count(*) FILTER (
             WHERE ct.oid IS NOT NULL
               AND has_table_privilege(r.oid, ct.oid, 'SELECT, INSERT, UPDATE, DELETE')
           ) AS with_access,
           string_agg(r.rolname, ', ') FILTER (
             WHERE ct.oid IS NOT NULL
               AND has_table_privilege(r.oid, ct.oid, 'SELECT, INSERT, UPDATE, DELETE')
           ) AS names
    FROM api_roles r
  ) a

  -- 8. Backend role. The SQL Editor cannot see which login Render uses.
  UNION ALL
  SELECT 90, '8. Role running this check', 'Which database role is running this query?',
    'INFO',
    'You are running as: ' || m.rolname
      || ' (superuser = ' || m.rolsuper || ', bypass RLS = ' || m.rolbypassrls || ').'
      || ' If you also apply 027 from here, this role will own complaint_comments.'
  FROM me m

  UNION ALL
  SELECT 91, '8. Render backend role', 'Will the Render backend still be able to use complaint_comments?',
    'NEEDS MANUAL CHECK',
    'WARNING: the database cannot tell which role Render logs in with, so this cannot be verified automatically.'
      || ' The backend keeps access only if its role OWNS complaint_comments or has BYPASS RLS.'
      || ' Expected owner after 027: ' || COALESCE((SELECT owner_name FROM comments_table), current_user) || '.'
      || ' Roles here with bypass RLS or superuser: '
      || COALESCE((
           SELECT string_agg(rolname, ', ' ORDER BY rolname)
           FROM pg_roles
           WHERE (rolbypassrls OR rolsuper) AND rolname NOT LIKE 'pg\_%'
         ), 'none') || '.'
      || ' To check: in Render, look only at the USERNAME in DATABASE_URL (the part after postgresql:// and before the colon).'
      || ' For a Supabase pooler it looks like postgres.abcdefgh, which means role postgres.'
      || ' Never copy or share the password or the full URL.'
),
summary AS (
  SELECT 100 AS sort_order, '9. FINAL' AS step, 'Overall result' AS check_name,
    CASE
      WHEN EXISTS (SELECT 1 FROM checks WHERE result = 'NOT READY') THEN 'NOT READY'
      ELSE 'NEEDS MANUAL CHECK'
    END AS result,
    CASE
      WHEN EXISTS (SELECT 1 FROM checks WHERE result = 'NOT READY')
        THEN 'At least one check is NOT READY. Do not apply 027. Send this whole table for review.'
      WHEN (SELECT has_comments FROM state)
        THEN '027 is applied and all automatic checks passed. Only step 8 (Render backend role) still needs a manual check.'
      ELSE 'All automatic checks passed. Before applying 027, confirm step 8 (Render backend role) manually.'
    END AS details
)
SELECT step       AS "Step",
       check_name AS "Check",
       result     AS "Result",
       details    AS "What this means"
FROM (
  SELECT * FROM checks
  UNION ALL
  SELECT * FROM summary
) all_checks
ORDER BY sort_order;
