-- 021_remove_duplicate_templates.sql
-- Deduplicate property_type_level_templates and prevent future duplicates.
-- Cause: seed 001 / migration 020 were re-run and INSERTed a second full chain.

-- 1) Repoint children that reference a duplicate parent → the kept row
--    (same property_type_key + internal_key, lowest order_index / id).
WITH ranked AS (
  SELECT
    id,
    property_type_key,
    internal_key,
    ROW_NUMBER() OVER (
      PARTITION BY property_type_key, internal_key
      ORDER BY order_index ASC, id ASC
    ) AS rn
  FROM property_type_level_templates
),
keepers AS (
  SELECT id, property_type_key, internal_key FROM ranked WHERE rn = 1
),
doomed AS (
  SELECT id, property_type_key, internal_key FROM ranked WHERE rn > 1
)
UPDATE property_type_level_templates AS child
SET parent_template_id = k.id
FROM doomed d
JOIN keepers k
  ON k.property_type_key = d.property_type_key
 AND k.internal_key = d.internal_key
WHERE child.parent_template_id = d.id;

-- 2) Clear parent links on doomed rows so DELETE cannot violate FKs
WITH ranked AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY property_type_key, internal_key
      ORDER BY order_index ASC, id ASC
    ) AS rn
  FROM property_type_level_templates
)
UPDATE property_type_level_templates
SET parent_template_id = NULL
WHERE id IN (SELECT id FROM ranked WHERE rn > 1);

-- 3) Delete duplicate rows (rn > 1)
WITH ranked AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY property_type_key, internal_key
      ORDER BY order_index ASC, id ASC
    ) AS rn
  FROM property_type_level_templates
)
DELETE FROM property_type_level_templates
WHERE id IN (SELECT id FROM ranked WHERE rn > 1);

-- 4) Rebuild parent chain by contiguous order_index within each type
UPDATE property_type_level_templates AS child
SET parent_template_id = parent.id
FROM property_type_level_templates AS parent
WHERE child.property_type_key = parent.property_type_key
  AND parent.order_index = child.order_index - 1;

UPDATE property_type_level_templates
SET parent_template_id = NULL
WHERE order_index = 0;

-- 5) Prevent this from happening again
DO $$ BEGIN
  ALTER TABLE property_type_level_templates
    ADD CONSTRAINT uq_pt_level_templates_type_internal
    UNIQUE (property_type_key, internal_key);
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
