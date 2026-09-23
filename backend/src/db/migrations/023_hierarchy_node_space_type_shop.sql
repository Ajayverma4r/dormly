-- 023_hierarchy_node_space_type_shop.sql
-- Allow commercial / shop spaces on rental houses.

ALTER TABLE hierarchy_nodes
  DROP CONSTRAINT IF EXISTS hierarchy_nodes_space_type_check;

ALTER TABLE hierarchy_nodes
  ADD CONSTRAINT hierarchy_nodes_space_type_check
  CHECK (
    space_type IS NULL
    OR space_type IN (
      'entire_property',
      'floor',
      'portion',
      'room',
      'shop'
    )
  );
