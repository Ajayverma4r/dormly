-- 002_more_property_type_templates.sql
-- Adds suggested structures for the property types that had none yet.
-- "Custom" intentionally stays empty — it's meant to be a blank canvas.

-- PG -> Building -> Floor -> Room -> Bed
WITH b AS (
    INSERT INTO property_type_level_templates
        (property_type_key, display_name, internal_key, order_index, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
    VALUES ('pg', 'Building', 'building', 0, 'building', true, false, true, true)
    RETURNING id
), f AS (
    INSERT INTO property_type_level_templates
        (property_type_key, display_name, internal_key, order_index, parent_template_id, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
    SELECT 'pg', 'Floor', 'floor', 1, id, 'layers', true, false, false, true FROM b RETURNING id
), r AS (
    INSERT INTO property_type_level_templates
        (property_type_key, display_name, internal_key, order_index, parent_template_id, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
    SELECT 'pg', 'Room', 'room', 2, id, 'door-closed', true, false, true, true FROM f RETURNING id
)
INSERT INTO property_type_level_templates
    (property_type_key, display_name, internal_key, order_index, parent_template_id, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
SELECT 'pg', 'Bed', 'bed', 3, id, 'bed', true, true, true, true FROM r;

-- Rental Property -> Building -> Floor -> {Shop, Flat}
WITH b AS (
    INSERT INTO property_type_level_templates
        (property_type_key, display_name, internal_key, order_index, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
    VALUES ('rental', 'Building', 'building', 0, 'building', true, false, false, true)
    RETURNING id
), f AS (
    INSERT INTO property_type_level_templates
        (property_type_key, display_name, internal_key, order_index, parent_template_id, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
    SELECT 'rental', 'Floor', 'floor', 1, id, 'layers', true, false, false, false FROM b RETURNING id
)
INSERT INTO property_type_level_templates
    (property_type_key, display_name, internal_key, order_index, parent_template_id, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
SELECT 'rental', v.name, v.key, v.idx, f.id, v.icon, true, true, true, true
FROM f, (VALUES ('Shop', 'shop', 2, 'briefcase'), ('Flat', 'flat', 3, 'home')) AS v(name, key, idx, icon);

-- Co-Living -> Building -> Floor -> Suite -> Room
WITH b AS (
    INSERT INTO property_type_level_templates
        (property_type_key, display_name, internal_key, order_index, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
    VALUES ('coliving', 'Building', 'building', 0, 'building', true, false, false, true)
    RETURNING id
), f AS (
    INSERT INTO property_type_level_templates
        (property_type_key, display_name, internal_key, order_index, parent_template_id, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
    SELECT 'coliving', 'Floor', 'floor', 1, id, 'layers', true, false, false, false FROM b RETURNING id
), s AS (
    INSERT INTO property_type_level_templates
        (property_type_key, display_name, internal_key, order_index, parent_template_id, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
    SELECT 'coliving', 'Suite', 'suite', 2, id, 'grid', true, false, true, true FROM f RETURNING id
)
INSERT INTO property_type_level_templates
    (property_type_key, display_name, internal_key, order_index, parent_template_id, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
SELECT 'coliving', 'Room', 'room', 3, id, 'door-closed', true, true, true, true FROM s;

-- Staff Housing -> Building -> Floor -> Room
WITH b AS (
    INSERT INTO property_type_level_templates
        (property_type_key, display_name, internal_key, order_index, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
    VALUES ('staff_housing', 'Building', 'building', 0, 'building', true, false, false, true)
    RETURNING id
), f AS (
    INSERT INTO property_type_level_templates
        (property_type_key, display_name, internal_key, order_index, parent_template_id, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
    SELECT 'staff_housing', 'Floor', 'floor', 1, id, 'layers', true, false, false, false FROM b RETURNING id
)
INSERT INTO property_type_level_templates
    (property_type_key, display_name, internal_key, order_index, parent_template_id, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
SELECT 'staff_housing', 'Room', 'room', 2, id, 'door-closed', true, true, true, true FROM f;

-- Independent House -> House -> Room
WITH h AS (
    INSERT INTO property_type_level_templates
        (property_type_key, display_name, internal_key, order_index, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
    VALUES ('house', 'House', 'house', 0, 'home', true, false, false, true)
    RETURNING id
)
INSERT INTO property_type_level_templates
    (property_type_key, display_name, internal_key, order_index, parent_template_id, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
SELECT 'house', 'Room', 'room', 1, id, 'door-closed', true, true, true, true FROM h;

-- Resort -> Building -> Floor -> Room
WITH b AS (
    INSERT INTO property_type_level_templates
        (property_type_key, display_name, internal_key, order_index, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
    VALUES ('resort', 'Building', 'building', 0, 'building', true, false, false, true)
    RETURNING id
), f AS (
    INSERT INTO property_type_level_templates
        (property_type_key, display_name, internal_key, order_index, parent_template_id, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
    SELECT 'resort', 'Floor', 'floor', 1, id, 'layers', true, false, false, false FROM b RETURNING id
)
INSERT INTO property_type_level_templates
    (property_type_key, display_name, internal_key, order_index, parent_template_id, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
SELECT 'resort', 'Room', 'room', 2, id, 'door-closed', true, true, true, true FROM f;

-- Hospital -> Building -> Floor -> Ward -> Bed
WITH b AS (
    INSERT INTO property_type_level_templates
        (property_type_key, display_name, internal_key, order_index, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
    VALUES ('hospital', 'Building', 'building', 0, 'building', true, false, false, true)
    RETURNING id
), f AS (
    INSERT INTO property_type_level_templates
        (property_type_key, display_name, internal_key, order_index, parent_template_id, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
    SELECT 'hospital', 'Floor', 'floor', 1, id, 'layers', true, false, false, false FROM b RETURNING id
), w AS (
    INSERT INTO property_type_level_templates
        (property_type_key, display_name, internal_key, order_index, parent_template_id, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
    SELECT 'hospital', 'Ward', 'ward', 2, id, 'grid', true, false, true, true FROM f RETURNING id
)
INSERT INTO property_type_level_templates
    (property_type_key, display_name, internal_key, order_index, parent_template_id, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
SELECT 'hospital', 'Bed', 'bed', 3, id, 'bed', true, true, true, true FROM w;

-- School -> Building -> Floor -> Classroom
WITH b AS (
    INSERT INTO property_type_level_templates
        (property_type_key, display_name, internal_key, order_index, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
    VALUES ('school', 'Building', 'building', 0, 'building', true, false, false, true)
    RETURNING id
), f AS (
    INSERT INTO property_type_level_templates
        (property_type_key, display_name, internal_key, order_index, parent_template_id, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
    SELECT 'school', 'Floor', 'floor', 1, id, 'layers', true, false, false, false FROM b RETURNING id
)
INSERT INTO property_type_level_templates
    (property_type_key, display_name, internal_key, order_index, parent_template_id, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
SELECT 'school', 'Classroom', 'classroom', 2, id, 'grid', true, false, true, true FROM f;

-- Factory -> Building -> Section
WITH b AS (
    INSERT INTO property_type_level_templates
        (property_type_key, display_name, internal_key, order_index, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
    VALUES ('factory', 'Building', 'building', 0, 'building', true, false, false, true)
    RETURNING id
)
INSERT INTO property_type_level_templates
    (property_type_key, display_name, internal_key, order_index, parent_template_id, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
SELECT 'factory', 'Section', 'section', 1, id, 'grid', true, false, true, true FROM b;

-- Parking -> Building -> Floor -> Slot
WITH b AS (
    INSERT INTO property_type_level_templates
        (property_type_key, display_name, internal_key, order_index, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
    VALUES ('parking', 'Building', 'building', 0, 'building', true, false, false, false)
    RETURNING id
), f AS (
    INSERT INTO property_type_level_templates
        (property_type_key, display_name, internal_key, order_index, parent_template_id, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
    SELECT 'parking', 'Floor', 'floor', 1, id, 'layers', true, false, false, false FROM b RETURNING id
)
INSERT INTO property_type_level_templates
    (property_type_key, display_name, internal_key, order_index, parent_template_id, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
SELECT 'parking', 'Slot', 'slot', 2, id, 'car', true, false, true, false FROM f;