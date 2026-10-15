-- =============================================================================
-- Dormly TESTING environment: FRESH START
-- Deletes all application data, keeps subscription plans and system setup.
-- =============================================================================
--
-- !!  PERMANENT. THERE IS NO UNDO. Only for the Dormly TESTING project.  !!
--     Check the project name at the top of the Supabase dashboard first.
--
-- HOW TO RUN: Supabase > SQL Editor > paste this WHOLE file > Run.
-- Supabase warns that the query is destructive; confirm.
--
-- PRESERVED (rows untouched):
--   plans, features, plan_features                 subscription plans/prices
--   property_types, property_type_level_templates  built-in property setups
--   Every table, column, index, function, trigger, RLS policy, grant and
--   migration. Only rows are removed.
--
-- DELETED (all rows; 25 tables):
--   users, otp_codes, organizations, memberships, property_staff_assignments,
--   properties, hierarchy_levels, hierarchy_nodes, occupants, tenancies,
--   tenant_documents, charge_types, invoices, invoice_line_items, payments,
--   expenses, meter_readings, mess_menus, gate_passes, complaints,
--   complaint_comments, notifications, subscriptions, subscription_history,
--   subscription_payments
--   + Supabase Auth accounts (auth.users and their sessions/identities).
--     Dormly does not log in through Supabase Auth (it uses its own users
--     and otp_codes tables), so this is normally already empty.
--
-- NOT DELETED BY THIS FILE: uploaded files in Supabase Storage. Supabase only
--   removes stored files through the Storage API/dashboard, not SQL. The
--   result table shows how many remain; empty the bucket in
--   Storage > dormly-uploads > "Empty bucket".
--
-- SAFETY: everything runs as one transaction. Before deleting anything it
--   STOPS (and changes nothing) if
--   * this does not look like the Dormly database,
--   * there is a table in "public" this file does not know about,
--   * any other table, in any schema, links to a table being emptied
--     (so no preserved table can be emptied along with it),
--   * a TRUNCATE trigger exists on a table being emptied.
--   TRUNCATE does not fire row DELETE triggers or ON DELETE actions, and no
--   CASCADE is used, so nothing outside the list above is affected.
-- =============================================================================

DO $reset$
DECLARE
  keep_tables text[] := ARRAY[
    'plans', 'features', 'plan_features',
    'property_types', 'property_type_level_templates'
  ];
  app_tables text[] := ARRAY[
    'users', 'otp_codes', 'organizations', 'memberships',
    'property_staff_assignments', 'properties', 'hierarchy_levels',
    'hierarchy_nodes', 'occupants', 'tenancies', 'tenant_documents',
    'charge_types', 'invoices', 'invoice_line_items', 'payments', 'expenses',
    'meter_readings', 'mess_menus', 'gate_passes', 'complaints',
    'complaint_comments', 'notifications', 'subscriptions',
    'subscription_history', 'subscription_payments'
  ];
  targets   regclass[];
  missing   text;
  problem   text;
  auth_rows bigint;
BEGIN
  -- Fail fast instead of waiting forever if the backend holds a lock.
  PERFORM set_config('lock_timeout', '15s', true);

  -- 1. Is this the Dormly database?
  SELECT string_agg(t, ', ') INTO missing
  FROM unnest(keep_tables || ARRAY['users', 'organizations', 'properties']) AS t
  WHERE to_regclass(format('public.%I', t)) IS NULL;
  IF missing IS NOT NULL THEN
    RAISE EXCEPTION 'STOPPED, nothing deleted: this does not look like the Dormly database (missing: %).', missing;
  END IF;

  SELECT array_agg(to_regclass(format('public.%I', t)))
    INTO targets
  FROM unnest(app_tables) AS t
  WHERE to_regclass(format('public.%I', t)) IS NOT NULL;

  -- 2. Unknown tables in public: do not guess whether they are data or config.
  SELECT string_agg(c.relname, ', ' ORDER BY c.relname) INTO problem
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relkind IN ('r', 'p')
    AND NOT c.relispartition
    AND c.relname <> ALL (keep_tables || app_tables)
    AND NOT EXISTS (
      SELECT 1 FROM pg_depend d
      WHERE d.classid = 'pg_class'::regclass AND d.objid = c.oid AND d.deptype = 'e'
    );
  IF problem IS NOT NULL THEN
    RAISE EXCEPTION 'STOPPED, nothing deleted: unknown table(s) in public: %. Add each to keep_tables or app_tables in this file.', problem;
  END IF;

  -- 3. Any table outside the delete list that links to it (preserved tables,
  --    other schemas). Without CASCADE, TRUNCATE would fail on these anyway.
  SELECT string_agg(format('%s -> %s', con.conrelid::regclass, con.confrelid::regclass), ', ')
    INTO problem
  FROM pg_constraint con
  WHERE con.contype = 'f'
    AND con.confrelid = ANY (targets)
    AND con.conrelid <> ALL (targets);
  IF problem IS NOT NULL THEN
    RAISE EXCEPTION 'STOPPED, nothing deleted: other tables link to app data (%).', problem;
  END IF;

  -- 4. TRUNCATE triggers could run extra code; there should be none.
  SELECT string_agg(format('%s on %s', tg.tgname, tg.tgrelid::regclass), ', ')
    INTO problem
  FROM pg_trigger tg
  WHERE NOT tg.tgisinternal
    AND tg.tgrelid = ANY (targets)
    AND (tg.tgtype & 32) <> 0;
  IF problem IS NOT NULL THEN
    RAISE EXCEPTION 'STOPPED, nothing deleted: TRUNCATE trigger(s) found: %.', problem;
  END IF;

  -- 5. Empty the application tables. No CASCADE: only these tables change.
  EXECUTE 'TRUNCATE TABLE '
    || (SELECT string_agg(t::text, ', ') FROM unnest(targets) AS t)
    || ' RESTART IDENTITY';
  RAISE NOTICE 'Emptied % application tables.', cardinality(targets);

  -- 6. Supabase Auth accounts (sessions, identities etc. go with them).
  IF to_regclass('auth.users') IS NOT NULL THEN
    BEGIN
      DELETE FROM auth.users;
      GET DIAGNOSTICS auth_rows = ROW_COUNT;
      RAISE NOTICE 'Deleted % Supabase Auth account(s).', auth_rows;
    EXCEPTION WHEN insufficient_privilege OR foreign_key_violation THEN
      RAISE WARNING 'Supabase Auth accounts NOT deleted (%). Delete them in Authentication > Users.', SQLERRM;
    END;
  END IF;
END
$reset$;

-- =============================================================================
-- VERIFICATION (can also be run on its own at any time; it only reads).
-- Every row should say OK. Rows needing attention are listed first.
-- =============================================================================
SELECT section, item, row_count, expected, status
FROM (
  SELECT 'DELETED'   AS section, 'users'                      AS item, (SELECT count(*) FROM public.users)                      AS row_count
  UNION ALL SELECT 'DELETED',   'otp_codes',                  (SELECT count(*) FROM public.otp_codes)
  UNION ALL SELECT 'DELETED',   'organizations',              (SELECT count(*) FROM public.organizations)
  UNION ALL SELECT 'DELETED',   'memberships',                (SELECT count(*) FROM public.memberships)
  UNION ALL SELECT 'DELETED',   'property_staff_assignments', (SELECT count(*) FROM public.property_staff_assignments)
  UNION ALL SELECT 'DELETED',   'properties',                 (SELECT count(*) FROM public.properties)
  UNION ALL SELECT 'DELETED',   'hierarchy_levels',           (SELECT count(*) FROM public.hierarchy_levels)
  UNION ALL SELECT 'DELETED',   'hierarchy_nodes',            (SELECT count(*) FROM public.hierarchy_nodes)
  UNION ALL SELECT 'DELETED',   'occupants',                  (SELECT count(*) FROM public.occupants)
  UNION ALL SELECT 'DELETED',   'tenancies',                  (SELECT count(*) FROM public.tenancies)
  UNION ALL SELECT 'DELETED',   'tenant_documents',           (SELECT count(*) FROM public.tenant_documents)
  UNION ALL SELECT 'DELETED',   'charge_types',               (SELECT count(*) FROM public.charge_types)
  UNION ALL SELECT 'DELETED',   'invoices',                   (SELECT count(*) FROM public.invoices)
  UNION ALL SELECT 'DELETED',   'invoice_line_items',         (SELECT count(*) FROM public.invoice_line_items)
  UNION ALL SELECT 'DELETED',   'payments',                   (SELECT count(*) FROM public.payments)
  UNION ALL SELECT 'DELETED',   'expenses',                   (SELECT count(*) FROM public.expenses)
  UNION ALL SELECT 'DELETED',   'meter_readings',             (SELECT count(*) FROM public.meter_readings)
  UNION ALL SELECT 'DELETED',   'mess_menus',                 (SELECT count(*) FROM public.mess_menus)
  UNION ALL SELECT 'DELETED',   'gate_passes',                (SELECT count(*) FROM public.gate_passes)
  UNION ALL SELECT 'DELETED',   'complaints',                 (SELECT count(*) FROM public.complaints)
  UNION ALL SELECT 'DELETED',   'complaint_comments',         (SELECT count(*) FROM public.complaint_comments)
  UNION ALL SELECT 'DELETED',   'notifications',              (SELECT count(*) FROM public.notifications)
  UNION ALL SELECT 'DELETED',   'subscriptions',              (SELECT count(*) FROM public.subscriptions)
  UNION ALL SELECT 'DELETED',   'subscription_history',       (SELECT count(*) FROM public.subscription_history)
  UNION ALL SELECT 'DELETED',   'subscription_payments',      (SELECT count(*) FROM public.subscription_payments)
  UNION ALL SELECT 'DELETED',   'Supabase Auth accounts (auth.users)', (SELECT count(*) FROM auth.users)
  UNION ALL SELECT 'PRESERVED', 'plans',                      (SELECT count(*) FROM public.plans)
  UNION ALL SELECT 'PRESERVED', 'features',                   (SELECT count(*) FROM public.features)
  UNION ALL SELECT 'PRESERVED', 'plan_features',              (SELECT count(*) FROM public.plan_features)
  UNION ALL SELECT 'PRESERVED', 'property_types',             (SELECT count(*) FROM public.property_types)
  UNION ALL SELECT 'PRESERVED', 'property_type_level_templates', (SELECT count(*) FROM public.property_type_level_templates)
  UNION ALL SELECT 'STORAGE',   'uploaded files, all buckets', (SELECT count(*) FROM storage.objects)
) AS r
CROSS JOIN LATERAL (
  SELECT
    CASE section WHEN 'PRESERVED' THEN 'more than 0' ELSE '0' END AS expected,
    CASE
      WHEN section = 'PRESERVED' AND row_count > 0 THEN 'OK'
      WHEN section = 'PRESERVED' THEN 'CHECK: empty, run backend/src/db/seeds'
      WHEN row_count = 0 THEN 'OK'
      WHEN section = 'STORAGE' THEN 'ACTION: Storage > bucket > Empty bucket'
      WHEN item LIKE 'Supabase Auth%' THEN 'ACTION: Authentication > Users > delete'
      ELSE 'NOT EMPTY: re-run the reset'
    END AS status
) AS s
ORDER BY (status = 'OK'), section, item;
