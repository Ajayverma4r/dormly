-- 009_subscriptions.sql
-- Feature-entitlement & quota-based subscription system for Dormly.
--
-- DESIGN PRINCIPLES:
--   1. Application code NEVER inspects plan slugs. All gating is done by
--      querying named feature keys (e.g. can_export_pdf, max_properties).
--      The view `org_active_entitlements` is the single source of truth.
--   2. quota_value = -1 means unlimited for that feature.
--   3. Graceful downgrade on trial/plan expiry:
--        a. Backend job updates plan_id → free plan, status → 'expired'.
--        b. API middleware checks if the org currently exceeds free quotas.
--        c. If over limit: block CREATE operations, allow READ on existing
--           resources. Nothing is deleted automatically.
--   4. subscription_payments is intentionally separate from the rent/ops
--      payments table in 006_billing.sql to prevent schema coupling.

-- ---------------------------------------------------------------------------
-- plans
-- ---------------------------------------------------------------------------
CREATE TABLE plans (
    id                  UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    slug                TEXT          NOT NULL UNIQUE,
    display_name        TEXT          NOT NULL,
    description         TEXT,
    price_inr_monthly   NUMERIC(10,2) NOT NULL DEFAULT 0,
    price_inr_yearly    NUMERIC(10,2) NOT NULL DEFAULT 0,
    trial_days          INT           NOT NULL DEFAULT 0,
    is_public           BOOLEAN       NOT NULL DEFAULT true,
    is_active           BOOLEAN       NOT NULL DEFAULT true,
    sort_order          INT           NOT NULL DEFAULT 0,
    created_at          TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- features  (the feature catalog — every possible entitlement or quota)
-- ---------------------------------------------------------------------------
CREATE TYPE feature_value_type AS ENUM ('boolean', 'quota');

CREATE TABLE features (
    id              UUID               PRIMARY KEY DEFAULT gen_random_uuid(),
    key             TEXT               NOT NULL UNIQUE,  -- e.g. 'can_export_pdf'
    display_name    TEXT               NOT NULL,
    description     TEXT,
    value_type      feature_value_type NOT NULL,
    unit            TEXT,              -- 'properties' | 'rooms' | 'tier' | NULL
    category        TEXT               NOT NULL DEFAULT 'general',
    created_at      TIMESTAMPTZ        NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- plan_features  (what each plan grants — the entitlement mapping)
-- ---------------------------------------------------------------------------
CREATE TABLE plan_features (
    id              UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_id         UUID    NOT NULL REFERENCES plans(id)    ON DELETE CASCADE,
    feature_id      UUID    NOT NULL REFERENCES features(id) ON DELETE CASCADE,
    -- Exactly one of the two value columns is populated, matching feature.value_type.
    bool_value      BOOLEAN,  -- used when value_type = 'boolean'
    quota_value     INT,      -- used when value_type = 'quota'; -1 = unlimited
    UNIQUE (plan_id, feature_id),
    CONSTRAINT chk_plan_features_value CHECK (
        (bool_value IS NOT NULL AND quota_value IS NULL)
        OR
        (bool_value IS NULL AND quota_value IS NOT NULL)
    )
);
CREATE INDEX idx_plan_features_plan    ON plan_features(plan_id);
CREATE INDEX idx_plan_features_feature ON plan_features(feature_id);

-- ---------------------------------------------------------------------------
-- subscriptions  (exactly one row per organization at any point in time)
-- ---------------------------------------------------------------------------
CREATE TYPE subscription_status AS ENUM (
    'trialing',   -- within the free-trial window; full Pro entitlements
    'active',     -- paid and current
    'past_due',   -- payment failed; grace period active (still readable)
    'cancelled',  -- cancel_at_period_end=true, paid period not yet over
    'expired'     -- trial/grace lapsed; plan_id has been set to 'free'
);

CREATE TABLE subscriptions (
    id                          UUID                PRIMARY KEY DEFAULT gen_random_uuid(),
    -- One active subscription row per org. If the org has never subscribed,
    -- a row is auto-created at signup with plan=pro_trial, status=trialing.
    organization_id             UUID                NOT NULL UNIQUE REFERENCES organizations(id) ON DELETE CASCADE,
    plan_id                     UUID                NOT NULL REFERENCES plans(id),
    status                      subscription_status NOT NULL DEFAULT 'trialing',
    trial_ends_at               TIMESTAMPTZ,
    current_period_start        TIMESTAMPTZ         NOT NULL DEFAULT now(),
    current_period_end          TIMESTAMPTZ         NOT NULL DEFAULT now() + INTERVAL '14 days',
    cancel_at_period_end        BOOLEAN             NOT NULL DEFAULT false,
    cancelled_at                TIMESTAMPTZ,
    -- Grace period: set to now()+3 days when a payment fails.
    -- After it lapses, the backend job downgrades to free.
    grace_period_ends_at        TIMESTAMPTZ,
    razorpay_subscription_id    TEXT,
    razorpay_customer_id        TEXT,
    metadata                    JSONB               NOT NULL DEFAULT '{}',
    created_at                  TIMESTAMPTZ         NOT NULL DEFAULT now(),
    updated_at                  TIMESTAMPTZ         NOT NULL DEFAULT now()
);
CREATE INDEX idx_subscriptions_org    ON subscriptions(organization_id);
CREATE INDEX idx_subscriptions_plan   ON subscriptions(plan_id);
CREATE INDEX idx_subscriptions_status ON subscriptions(status);

-- ---------------------------------------------------------------------------
-- subscription_history  (immutable audit trail; append-only)
-- ---------------------------------------------------------------------------
CREATE TYPE subscription_change_reason AS ENUM (
    'signup',
    'trial_started',
    'trial_expired',
    'upgrade',
    'downgrade',
    'payment_succeeded',
    'payment_failed',
    'payment_refunded',
    'cancelled',
    'reactivated',
    'manual_override'
);

CREATE TABLE subscription_history (
    id                  UUID                        PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id     UUID                        NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    subscription_id     UUID                        NOT NULL REFERENCES subscriptions(id) ON DELETE CASCADE,
    from_plan_id        UUID                        REFERENCES plans(id),    -- NULL on first event
    to_plan_id          UUID                        NOT NULL REFERENCES plans(id),
    from_status         subscription_status,                                  -- NULL on first event
    to_status           subscription_status         NOT NULL,
    reason              subscription_change_reason  NOT NULL,
    changed_by_user_id  UUID                        REFERENCES users(id),    -- NULL = system/job
    note                TEXT,
    created_at          TIMESTAMPTZ                 NOT NULL DEFAULT now()
);
CREATE INDEX idx_sub_history_org ON subscription_history(organization_id);
CREATE INDEX idx_sub_history_sub ON subscription_history(subscription_id);

-- ---------------------------------------------------------------------------
-- subscription_payments  (Razorpay gateway records)
--
-- Lifecycle: created → attempted → paid | failed → (refunded)
-- Every Razorpay webhook upserts a row here; the backend service then
-- reflects the outcome onto the `subscriptions` table.
-- ---------------------------------------------------------------------------
CREATE TYPE sub_payment_status AS ENUM (
    'created',    -- Razorpay order created, awaiting user action
    'attempted',  -- user opened checkout; not yet confirmed
    'paid',       -- webhook payment.captured confirmed
    'failed',     -- webhook payment.failed received
    'refunded'    -- full or partial refund issued via Razorpay dashboard
);

CREATE TABLE subscription_payments (
    id                      UUID               PRIMARY KEY DEFAULT gen_random_uuid(),
    subscription_id         UUID               NOT NULL REFERENCES subscriptions(id) ON DELETE CASCADE,
    organization_id         UUID               NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    razorpay_order_id       TEXT               UNIQUE,
    razorpay_payment_id     TEXT               UNIQUE,
    razorpay_signature      TEXT,
    amount_inr              NUMERIC(10,2)      NOT NULL,
    currency                TEXT               NOT NULL DEFAULT 'INR',
    status                  sub_payment_status NOT NULL DEFAULT 'created',
    -- 'upi' | 'card' | 'netbanking' | 'wallet' | 'emi' — set from webhook
    payment_method          TEXT,
    billing_period_start    TIMESTAMPTZ,
    billing_period_end      TIMESTAMPTZ,
    invoice_url             TEXT,
    failure_code            TEXT,
    failure_reason          TEXT,
    metadata                JSONB              NOT NULL DEFAULT '{}',
    paid_at                 TIMESTAMPTZ,
    created_at              TIMESTAMPTZ        NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ        NOT NULL DEFAULT now()
);
CREATE INDEX idx_sub_payments_sub ON subscription_payments(subscription_id);
CREATE INDEX idx_sub_payments_org ON subscription_payments(organization_id);
CREATE INDEX idx_sub_payments_rzp ON subscription_payments(razorpay_payment_id);

-- ---------------------------------------------------------------------------
-- VIEW: org_active_entitlements
--
-- The canonical read surface for all feature checks. Services must NEVER
-- join subscriptions → plans directly; always query this view.
--
-- Usage examples (application layer):
--
--   -- Boolean gate:
--   SELECT bool_value FROM org_active_entitlements
--   WHERE organization_id = $orgId AND feature_key = 'can_export_pdf';
--
--   -- Quota check (returns -1 for unlimited):
--   SELECT quota_value FROM org_active_entitlements
--   WHERE organization_id = $orgId AND feature_key = 'max_properties';
--
-- Grace-period / read-only enforcement:
--   The application checks subscription_status. If 'past_due' or 'expired',
--   it compares the org's actual resource counts against the quota_values in
--   this view and blocks CREATE operations where counts >= quota, while still
--   allowing READ on existing resources.
-- ---------------------------------------------------------------------------
CREATE VIEW org_active_entitlements AS
SELECT
    s.organization_id,
    s.plan_id,
    p.slug                      AS plan_slug,
    s.status                    AS subscription_status,
    s.trial_ends_at,
    s.current_period_end,
    s.grace_period_ends_at,
    f.key                       AS feature_key,
    f.value_type,
    f.category                  AS feature_category,
    pf.bool_value,
    pf.quota_value
FROM  subscriptions  s
JOIN  plans          p  ON p.id  = s.plan_id
JOIN  plan_features  pf ON pf.plan_id   = s.plan_id
JOIN  features       f  ON f.id  = pf.feature_id;
