-- 011_subscription_auto_renew.sql
-- Prep for Razorpay UPI AutoPay / eMandate and expiry-warning UX.

ALTER TABLE subscriptions
  ADD COLUMN IF NOT EXISTS auto_renew     BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS mandate_active BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN subscriptions.auto_renew IS
  'True when Razorpay AutoPay / eMandate will charge at period end.';
COMMENT ON COLUMN subscriptions.mandate_active IS
  'True when a Razorpay mandate token is linked (subscription/emandate ready).';

-- Helpful for the daily 7-day expiry warning job
CREATE INDEX IF NOT EXISTS idx_subscriptions_period_end
  ON subscriptions (current_period_end)
  WHERE status IN ('active', 'cancelled', 'past_due');

CREATE INDEX IF NOT EXISTS idx_subscriptions_trial_end
  ON subscriptions (trial_ends_at)
  WHERE status = 'trialing';
