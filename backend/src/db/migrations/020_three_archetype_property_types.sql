-- 020_three_archetype_property_types.sql
-- Pivot catalog + existing properties to hostel_pg / apartment / rental_house.

-- 1) Remap live properties to the 3 canonical keys (before deleting old catalog rows).
UPDATE properties SET property_type_key = 'hostel_pg'
WHERE lower(property_type_key) IN (
  'hostel', 'pg', 'hostel_pg', 'coliving', 'staff_housing', 'hotel'
);

UPDATE properties SET property_type_key = 'apartment'
WHERE lower(property_type_key) IN ('apartment', 'flat');

UPDATE properties SET property_type_key = 'rental_house'
WHERE lower(property_type_key) NOT IN ('hostel_pg', 'apartment', 'rental_house');

-- 2) Clear old templates (parent FKs first via delete all)
DELETE FROM property_type_level_templates;

-- 3) Ensure the 3 archetype rows exist; drop everything else
INSERT INTO property_types (key, display_name, description, icon) VALUES
    ('hostel_pg',    'Hostel / PG',     'Shared living — hostels, PGs, and co-living', 'bed'),
    ('apartment',    'Flat / Apartment','Gated community — towers, floors, and flats', 'building'),
    ('rental_house', 'Rental House',    'Individual lease — house or standalone unit', 'home')
ON CONFLICT (key) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    description  = EXCLUDED.description,
    icon         = EXCLUDED.icon;

DELETE FROM property_types
WHERE key NOT IN ('hostel_pg', 'apartment', 'rental_house');

-- 4) Seed hierarchy templates

-- hostel_pg: Building > Floor > Room > Bed
WITH b AS (
    INSERT INTO property_type_level_templates
        (property_type_key, display_name, internal_key, order_index, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
    VALUES ('hostel_pg', 'Building', 'building', 0, 'building', true, false, true, true)
    RETURNING id
), f AS (
    INSERT INTO property_type_level_templates
        (property_type_key, display_name, internal_key, order_index, parent_template_id, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
    SELECT 'hostel_pg', 'Floor', 'floor', 1, id, 'layers', true, false, false, true FROM b
    RETURNING id
), r AS (
    INSERT INTO property_type_level_templates
        (property_type_key, display_name, internal_key, order_index, parent_template_id, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
    SELECT 'hostel_pg', 'Room', 'room', 2, id, 'door-closed', true, false, true, true FROM f
    RETURNING id
)
INSERT INTO property_type_level_templates
    (property_type_key, display_name, internal_key, order_index, parent_template_id, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
SELECT 'hostel_pg', 'Bed', 'bed', 3, id, 'bed', true, true, true, true FROM r;

-- apartment: Tower > Floor > Flat
WITH t AS (
    INSERT INTO property_type_level_templates
        (property_type_key, display_name, internal_key, order_index, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
    VALUES ('apartment', 'Tower', 'tower', 0, 'building', true, false, false, true)
    RETURNING id
), f AS (
    INSERT INTO property_type_level_templates
        (property_type_key, display_name, internal_key, order_index, parent_template_id, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
    SELECT 'apartment', 'Floor', 'floor', 1, id, 'layers', true, false, false, false FROM t
    RETURNING id
)
INSERT INTO property_type_level_templates
    (property_type_key, display_name, internal_key, order_index, parent_template_id, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
SELECT 'apartment', 'Flat', 'flat', 2, id, 'home', true, true, true, true FROM f;

-- rental_house: Property > Unit
WITH p AS (
    INSERT INTO property_type_level_templates
        (property_type_key, display_name, internal_key, order_index, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
    VALUES ('rental_house', 'Property', 'property', 0, 'home', true, false, true, true)
    RETURNING id
)
INSERT INTO property_type_level_templates
    (property_type_key, display_name, internal_key, order_index, parent_template_id, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
SELECT 'rental_house', 'Unit', 'unit', 1, id, 'door-closed', true, true, true, true FROM p;
