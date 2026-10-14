-- 027_complaint_comments_assignment.sql
-- Complaint assignment and comments/activity. Additive only: no existing rows
-- or columns are changed. The backend detects these objects at runtime and
-- keeps working (without comments/assignment) until this has been applied.

BEGIN;

ALTER TABLE complaints
  ADD COLUMN IF NOT EXISTS assigned_to UUID REFERENCES users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS assigned_by UUID REFERENCES users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS assigned_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_complaints_assigned_to
  ON complaints(assigned_to) WHERE assigned_to IS NOT NULL;

-- Comments plus assignment events. property_id is copied from the complaint
-- by the backend and never taken from the client.
CREATE TABLE IF NOT EXISTS complaint_comments (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  complaint_id   UUID NOT NULL REFERENCES complaints(id) ON DELETE CASCADE,
  property_id    UUID NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
  author_user_id UUID NOT NULL REFERENCES users(id),
  author_role    TEXT NOT NULL CHECK (author_role IN ('owner', 'admin', 'manager', 'staff', 'tenant')),
  kind           TEXT NOT NULL DEFAULT 'comment' CHECK (kind IN ('comment', 'assigned', 'unassigned')),
  visibility     TEXT NOT NULL DEFAULT 'internal' CHECK (visibility IN ('internal', 'tenant_visible')),
  body           TEXT CHECK (body IS NULL OR char_length(body) BETWEEN 1 AND 2000),
  meta           JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (kind <> 'comment' OR body IS NOT NULL),
  CHECK (kind = 'comment' OR visibility = 'internal')
);

CREATE INDEX IF NOT EXISTS idx_complaint_comments_complaint
  ON complaint_comments(complaint_id, created_at);
CREATE INDEX IF NOT EXISTS idx_complaint_comments_property
  ON complaint_comments(property_id);

-- Only the backend (table owner or a BYPASSRLS role) may read or write
-- comments. Deliberately no policies and no FORCE: Supabase's anon and
-- authenticated Data API roles get nothing, the owner keeps full access.
ALTER TABLE public.complaint_comments ENABLE ROW LEVEL SECURITY;

-- Undo Supabase's default grants on new public tables. Guarded so the file
-- also runs on plain PostgreSQL where these roles do not exist.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE ALL ON TABLE public.complaint_comments FROM anon;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE ALL ON TABLE public.complaint_comments FROM authenticated;
  END IF;
END $$;

COMMIT;
