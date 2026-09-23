-- 022_hierarchy_node_space_type.sql
-- Flexible rental "spaces" typing on hierarchy_nodes.
-- parent_node_id already exists (nullable) for Room → Floor nesting.

ALTER TABLE hierarchy_nodes
  ADD COLUMN IF NOT EXISTS space_type TEXT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'hierarchy_nodes_space_type_check'
  ) THEN
    ALTER TABLE hierarchy_nodes
      ADD CONSTRAINT hierarchy_nodes_space_type_check
      CHECK (
        space_type IS NULL
        OR space_type IN ('entire_property', 'floor', 'portion', 'room')
      );
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_hierarchy_nodes_space_type
  ON hierarchy_nodes (property_id, space_type)
  WHERE space_type IS NOT NULL;

-- Backfill from metadata when present.
UPDATE hierarchy_nodes
SET space_type = metadata->>'space_type'
WHERE space_type IS NULL
  AND metadata ? 'space_type'
  AND metadata->>'space_type' IN ('entire_property', 'floor', 'portion', 'room');
