-- 024_hierarchy_node_pricing.sql
-- Default rent / deposit attached to a rental space (hierarchy node).

ALTER TABLE hierarchy_nodes
  ADD COLUMN IF NOT EXISTS monthly_rent NUMERIC(12, 2);

ALTER TABLE hierarchy_nodes
  ADD COLUMN IF NOT EXISTS security_deposit NUMERIC(12, 2);

COMMENT ON COLUMN hierarchy_nodes.monthly_rent IS
  'Default monthly rent for this rental space (pre-fills tenancy).';
COMMENT ON COLUMN hierarchy_nodes.security_deposit IS
  'Default security deposit for this rental space (pre-fills tenancy).';
