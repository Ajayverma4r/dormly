-- 008_staff_invitations.sql
ALTER TABLE property_staff_assignments
  ADD COLUMN status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'active'));