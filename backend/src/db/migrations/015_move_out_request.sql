-- 015_move_out_request.sql
-- Tamper-proof move-out request audit trail on tenancies.
-- notice_given_at  = immutable requestedAt (set once by tenant submit)
-- planned_move_out_at = proposedExitDate (may be modified by mutual agreement)

DO $$ BEGIN
  CREATE TYPE move_out_request_status AS ENUM (
    'pending',
    'approved',
    'modified_by_mutual_agreement',
    'rejected'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE tenancies
  ADD COLUMN IF NOT EXISTS move_out_request_status move_out_request_status,
  ADD COLUMN IF NOT EXISTS move_out_is_emergency BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS move_out_reason TEXT,
  ADD COLUMN IF NOT EXISTS move_out_waive_notice_penalty BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN tenancies.notice_given_at IS
  'Immutable timestamp when tenant first submitted move-out request (requestedAt).';
COMMENT ON COLUMN tenancies.planned_move_out_at IS
  'Proposed / agreed exit date (proposedExitDate). May change via mutual agreement.';
COMMENT ON COLUMN tenancies.move_out_request_status IS
  'pending | approved | modified_by_mutual_agreement | rejected';
