-- 010_early_bird_pricing.sql
-- Early Bird pricing: ₹99/mo and ₹999/yr with strike-through originals.
-- Also extends pro_trial from 14 → 30 days.

ALTER TABLE plans
  ADD COLUMN IF NOT EXISTS original_price_inr_monthly NUMERIC(10,2),
  ADD COLUMN IF NOT EXISTS original_price_inr_yearly  NUMERIC(10,2);

UPDATE plans SET
  price_inr_monthly          = 99,
  price_inr_yearly           = 0,
  original_price_inr_monthly = 199,
  original_price_inr_yearly  = NULL,
  description                = 'Early Bird — full Pro access billed monthly. Limited-time launch price.',
  updated_at                 = now()
WHERE slug = 'pro_monthly';

UPDATE plans SET
  price_inr_monthly          = 99,
  price_inr_yearly           = 999,
  original_price_inr_monthly = 199,
  original_price_inr_yearly  = 1999,
  description                = 'Early Bird — full Pro access billed yearly. Limited-time launch price.',
  updated_at                 = now()
WHERE slug = 'pro_yearly';

UPDATE plans SET
  trial_days  = 30,
  description = '30-day full Pro access — no credit card required. Auto-assigned on signup or claimable from the paywall.',
  updated_at  = now()
WHERE slug = 'pro_trial';
