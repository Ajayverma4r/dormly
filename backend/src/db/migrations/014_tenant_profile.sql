-- 014_tenant_profile.sql — Tenant 360 profile fields on tenancies

ALTER TABLE tenancies
  ADD COLUMN IF NOT EXISTS occupation              TEXT,
  ADD COLUMN IF NOT EXISTS emergency_contact_name  TEXT,
  ADD COLUMN IF NOT EXISTS emergency_contact_relation TEXT,
  ADD COLUMN IF NOT EXISTS emergency_contact_phone TEXT,
  ADD COLUMN IF NOT EXISTS id_type                 TEXT,
  ADD COLUMN IF NOT EXISTS police_verification_done BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN tenancies.occupation IS
  'Tenant occupation category, e.g. student or working.';
COMMENT ON COLUMN tenancies.emergency_contact_name IS
  'Emergency contact full name.';
COMMENT ON COLUMN tenancies.emergency_contact_relation IS
  'Relationship to tenant, e.g. Parent, Spouse.';
COMMENT ON COLUMN tenancies.emergency_contact_phone IS
  'Emergency contact phone number.';
COMMENT ON COLUMN tenancies.id_type IS
  'Primary ID document type: aadhaar, pan, passport, etc.';
COMMENT ON COLUMN tenancies.police_verification_done IS
  'Whether police verification has been completed for this tenant.';
