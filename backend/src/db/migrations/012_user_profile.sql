-- 012_user_profile.sql
-- Owner/admin account profile fields for post-OTP onboarding.

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS email      TEXT,
  ADD COLUMN IF NOT EXISTS avatar_url TEXT;

COMMENT ON COLUMN users.name IS 'Display full name — required before property onboarding.';
COMMENT ON COLUMN users.email IS 'Optional contact email.';
COMMENT ON COLUMN users.avatar_url IS 'Optional profile photo URL (local /uploads/avatars/…).';
