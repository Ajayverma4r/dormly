-- 003_subscription_plans.sql
-- Default plan catalog + feature catalog + plan→feature entitlement mapping.
--
-- Plans:
--   free          — permanent free tier
--   pro_trial     — 14-day full Pro access (auto-assigned on org signup)
--   pro_monthly   — ₹499/month, same entitlements as pro_trial
--   pro_yearly    — ₹4,999/year  (≈ ₹416/month, saves ~2 months)
--   enterprise    — custom pricing, not publicly listed
--
-- Quota semantics:  quota_value = -1  →  unlimited
-- Support tiers:    0=community  1=email  2=priority  3=dedicated
--
-- All INSERT statements are idempotent (ON CONFLICT DO UPDATE) so this file
-- is safe to re-run after plan adjustments.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Plans
-- ---------------------------------------------------------------------------
INSERT INTO plans
    (slug, display_name, description, price_inr_monthly, price_inr_yearly, trial_days, is_public, is_active, sort_order)
VALUES
    ('free',
     'Free',
     'Get started with basic property management for one property.',
     0, 0, 0, true, true, 0),

    ('pro_trial',
     'Pro Trial',
     '14-day full Pro access — no credit card required. Auto-assigned on signup.',
     0, 0, 14, false, true, 1),

    ('pro_monthly',
     'Pro Monthly',
     'Full access to all Pro features, billed every month.',
     499, 0, 0, true, true, 2),

    ('pro_yearly',
     'Pro Yearly',
     'Full Pro access billed annually. Saves you the cost of 2 months.',
     499, 4999, 0, true, true, 3),

    ('enterprise',
     'Enterprise',
     'Custom pricing and SLA for large multi-property operations.',
     0, 0, 0, false, true, 4)
ON CONFLICT (slug) DO UPDATE SET
    display_name      = EXCLUDED.display_name,
    description       = EXCLUDED.description,
    price_inr_monthly = EXCLUDED.price_inr_monthly,
    price_inr_yearly  = EXCLUDED.price_inr_yearly,
    trial_days        = EXCLUDED.trial_days,
    is_public         = EXCLUDED.is_public,
    sort_order        = EXCLUDED.sort_order,
    updated_at        = now();

-- ---------------------------------------------------------------------------
-- 2. Feature catalog
-- ---------------------------------------------------------------------------
INSERT INTO features (key, display_name, description, value_type, unit, category)
VALUES
    -- Properties
    ('max_properties',
     'Max Properties',
     'Maximum number of properties that can be created under the organization.',
     'quota', 'properties', 'properties'),

    ('max_rooms',
     'Max Rooms / Units',
     'Maximum total leaf-level units (rooms, beds, desks) across all properties.',
     'quota', 'rooms', 'properties'),

    -- Staff
    ('max_staff_members',
     'Max Staff Members',
     'Maximum number of staff/manager accounts that can be invited.',
     'quota', 'staff_members', 'staff'),

    ('can_create_staff',
     'Create Staff',
     'Ability to invite and manage staff and manager accounts.',
     'boolean', NULL, 'staff'),

    -- Billing & Invoicing
    ('can_send_reminders',
     'Automated Reminders',
     'Send automated payment-due reminders to tenants.',
     'boolean', NULL, 'billing'),

    ('can_use_bulk_actions',
     'Bulk Actions',
     'Apply operations (generate invoices, mark paid) to multiple tenants at once.',
     'boolean', NULL, 'billing'),

    ('can_custom_charge_types',
     'Custom Charge Types',
     'Create charge types beyond the five defaults (Rent, Electricity, Water, Maintenance, Other).',
     'boolean', NULL, 'billing'),

    -- Reports & Exports
    ('can_access_reports',
     'Reports',
     'Access occupancy, revenue, and financial summary reports.',
     'boolean', NULL, 'reports'),

    ('can_export_pdf',
     'Export PDF',
     'Download invoices and reports as PDF files.',
     'boolean', NULL, 'reports'),

    ('can_export_csv',
     'Export CSV',
     'Export any data table (tenants, invoices, payments) as a CSV file.',
     'boolean', NULL, 'reports'),

    -- Analytics
    ('can_use_analytics',
     'Analytics Dashboard',
     'Full analytics dashboard with revenue trends, vacancy charts, and forecasting.',
     'boolean', NULL, 'analytics'),

    -- UI / Monetisation
    ('ads_enabled',
     'Show In-App Ads',
     'Whether the app displays advertisements to the org owner/staff.',
     'boolean', NULL, 'ui'),

    -- Security & Compliance
    ('can_view_audit_log',
     'Audit Log',
     'View the immutable audit trail of all actions taken in the organization.',
     'boolean', NULL, 'security'),

    -- Developer
    ('can_use_api_access',
     'API Access',
     'Programmatic API access using long-lived service tokens.',
     'boolean', NULL, 'developer'),

    -- Support
    ('support_tier',
     'Support Tier',
     'Level of support access: 0=community, 1=email, 2=priority, 3=dedicated.',
     'quota', 'tier', 'support')
ON CONFLICT (key) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    description  = EXCLUDED.description,
    unit         = EXCLUDED.unit,
    category     = EXCLUDED.category;

-- ---------------------------------------------------------------------------
-- 3. Plan → Feature entitlement mapping
--
-- Uses a single CTE-driven bulk INSERT so adding a new plan or feature
-- later is a one-liner in the VALUES list below.
--
-- Column order: plan_slug, feature_key, bool_value, quota_value
-- ---------------------------------------------------------------------------
WITH pf (plan_slug, feature_key, bool_value, quota_value) AS (
    VALUES
    -- ── FREE ─────────────────────────────────────────────────────────────
    ('free', 'max_properties',          NULL::boolean,  1),
    ('free', 'max_rooms',               NULL,           20),
    ('free', 'max_staff_members',       NULL,           2),
    ('free', 'can_create_staff',        true,           NULL::int),
    ('free', 'can_send_reminders',      false,          NULL),
    ('free', 'can_use_bulk_actions',    false,          NULL),
    ('free', 'can_custom_charge_types', false,          NULL),
    ('free', 'can_access_reports',      false,          NULL),
    ('free', 'can_export_pdf',          false,          NULL),
    ('free', 'can_export_csv',          false,          NULL),
    ('free', 'can_use_analytics',       false,          NULL),
    ('free', 'ads_enabled',             true,           NULL),
    ('free', 'can_view_audit_log',      false,          NULL),
    ('free', 'can_use_api_access',      false,          NULL),
    ('free', 'support_tier',            NULL,           0),

    -- ── PRO TRIAL (full Pro entitlements, time-limited) ──────────────────
    ('pro_trial', 'max_properties',          NULL,   -1),  -- unlimited
    ('pro_trial', 'max_rooms',               NULL,   -1),
    ('pro_trial', 'max_staff_members',       NULL,   20),
    ('pro_trial', 'can_create_staff',        true,   NULL),
    ('pro_trial', 'can_send_reminders',      true,   NULL),
    ('pro_trial', 'can_use_bulk_actions',    true,   NULL),
    ('pro_trial', 'can_custom_charge_types', true,   NULL),
    ('pro_trial', 'can_access_reports',      true,   NULL),
    ('pro_trial', 'can_export_pdf',          true,   NULL),
    ('pro_trial', 'can_export_csv',          true,   NULL),
    ('pro_trial', 'can_use_analytics',       true,   NULL),
    ('pro_trial', 'ads_enabled',             false,  NULL),
    ('pro_trial', 'can_view_audit_log',      false,  NULL),
    ('pro_trial', 'can_use_api_access',      false,  NULL),
    ('pro_trial', 'support_tier',            NULL,   1),

    -- ── PRO MONTHLY (identical entitlements to pro_trial) ────────────────
    ('pro_monthly', 'max_properties',          NULL,   -1),
    ('pro_monthly', 'max_rooms',               NULL,   -1),
    ('pro_monthly', 'max_staff_members',       NULL,   20),
    ('pro_monthly', 'can_create_staff',        true,   NULL),
    ('pro_monthly', 'can_send_reminders',      true,   NULL),
    ('pro_monthly', 'can_use_bulk_actions',    true,   NULL),
    ('pro_monthly', 'can_custom_charge_types', true,   NULL),
    ('pro_monthly', 'can_access_reports',      true,   NULL),
    ('pro_monthly', 'can_export_pdf',          true,   NULL),
    ('pro_monthly', 'can_export_csv',          true,   NULL),
    ('pro_monthly', 'can_use_analytics',       true,   NULL),
    ('pro_monthly', 'ads_enabled',             false,  NULL),
    ('pro_monthly', 'can_view_audit_log',      false,  NULL),
    ('pro_monthly', 'can_use_api_access',      false,  NULL),
    ('pro_monthly', 'support_tier',            NULL,   1),

    -- ── PRO YEARLY (identical entitlements to pro_monthly) ───────────────
    ('pro_yearly', 'max_properties',          NULL,   -1),
    ('pro_yearly', 'max_rooms',               NULL,   -1),
    ('pro_yearly', 'max_staff_members',       NULL,   20),
    ('pro_yearly', 'can_create_staff',        true,   NULL),
    ('pro_yearly', 'can_send_reminders',      true,   NULL),
    ('pro_yearly', 'can_use_bulk_actions',    true,   NULL),
    ('pro_yearly', 'can_custom_charge_types', true,   NULL),
    ('pro_yearly', 'can_access_reports',      true,   NULL),
    ('pro_yearly', 'can_export_pdf',          true,   NULL),
    ('pro_yearly', 'can_export_csv',          true,   NULL),
    ('pro_yearly', 'can_use_analytics',       true,   NULL),
    ('pro_yearly', 'ads_enabled',             false,  NULL),
    ('pro_yearly', 'can_view_audit_log',      false,  NULL),
    ('pro_yearly', 'can_use_api_access',      false,  NULL),
    ('pro_yearly', 'support_tier',            NULL,   2),   -- priority support on yearly

    -- ── ENTERPRISE ───────────────────────────────────────────────────────
    ('enterprise', 'max_properties',          NULL,   -1),
    ('enterprise', 'max_rooms',               NULL,   -1),
    ('enterprise', 'max_staff_members',       NULL,   -1),
    ('enterprise', 'can_create_staff',        true,   NULL),
    ('enterprise', 'can_send_reminders',      true,   NULL),
    ('enterprise', 'can_use_bulk_actions',    true,   NULL),
    ('enterprise', 'can_custom_charge_types', true,   NULL),
    ('enterprise', 'can_access_reports',      true,   NULL),
    ('enterprise', 'can_export_pdf',          true,   NULL),
    ('enterprise', 'can_export_csv',          true,   NULL),
    ('enterprise', 'can_use_analytics',       true,   NULL),
    ('enterprise', 'ads_enabled',             false,  NULL),
    ('enterprise', 'can_view_audit_log',      true,   NULL),
    ('enterprise', 'can_use_api_access',      true,   NULL),
    ('enterprise', 'support_tier',            NULL,   3)    -- dedicated support
)
INSERT INTO plan_features (plan_id, feature_id, bool_value, quota_value)
SELECT
    p.id,
    f.id,
    pf.bool_value,
    pf.quota_value
FROM  pf
JOIN  plans    p ON p.slug = pf.plan_slug
JOIN  features f ON f.key  = pf.feature_key
ON CONFLICT (plan_id, feature_id) DO UPDATE SET
    bool_value  = EXCLUDED.bool_value,
    quota_value = EXCLUDED.quota_value;

COMMIT;
