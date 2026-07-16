-- seed_property_types.sql
-- These rows are ONLY read by the property-creation wizard to pre-populate
-- suggested hierarchy_levels. After creation, a property's hierarchy_levels
-- are completely independent and can be renamed/reordered/deleted freely.

INSERT INTO property_types (key, display_name, description, icon) VALUES
    ('hostel',    'Hostel',    'Shared dorm-style accommodation', 'bed'),
    ('pg',        'PG',        'Paying guest accommodation', 'home'),
    ('apartment', 'Apartment', 'Multi-unit residential building', 'building'),
    ('rental',    'Rental Property', 'Independent rental unit', 'key'),
    ('coliving',  'Co-Living', 'Shared modern living spaces', 'users'),
    ('staff_housing', 'Staff Housing', 'Employer-provided housing', 'briefcase'),
    ('villa',     'Villa', 'Standalone luxury residence', 'home'),
    ('house',     'Independent House', 'Standalone residential unit', 'home'),
    ('office',    'Office', 'Commercial office space', 'briefcase'),
    ('warehouse', 'Warehouse', 'Storage and logistics facility', 'package'),
    ('hotel',     'Hotel', 'Guest lodging with room service', 'bed'),
    ('resort',    'Resort', 'Leisure and hospitality property', 'sun'),
    ('hospital',  'Hospital', 'Healthcare facility', 'plus-circle'),
    ('school',    'School', 'Educational institution', 'book'),
    ('factory',   'Factory', 'Manufacturing facility', 'settings'),
    ('parking',   'Parking', 'Vehicle parking facility', 'car'),
    ('custom',    'Custom', 'Define your own structure from scratch', 'sliders');

-- Example: Hostel -> Building -> Floor -> Room -> Bed
WITH b AS (
    INSERT INTO property_type_level_templates
        (property_type_key, display_name, internal_key, order_index, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
    VALUES ('hostel', 'Building', 'building', 0, 'building', true, false, true, true)
    RETURNING id
), f AS (
    INSERT INTO property_type_level_templates
        (property_type_key, display_name, internal_key, order_index, parent_template_id, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
    SELECT 'hostel', 'Floor', 'floor', 1, id, 'layers', true, false, false, true FROM b
    RETURNING id
), r AS (
    INSERT INTO property_type_level_templates
        (property_type_key, display_name, internal_key, order_index, parent_template_id, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
    SELECT 'hostel', 'Room', 'room', 2, id, 'door-closed', true, false, true, true FROM f
    RETURNING id
)
INSERT INTO property_type_level_templates
    (property_type_key, display_name, internal_key, order_index, parent_template_id, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
SELECT 'hostel', 'Bed', 'bed', 3, id, 'bed', true, true, true, true FROM r;

-- Apartment -> Tower -> Floor -> Flat
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

-- Office -> Building -> Department -> Cabin
WITH b AS (
    INSERT INTO property_type_level_templates
        (property_type_key, display_name, internal_key, order_index, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
    VALUES ('office', 'Building', 'building', 0, 'building', true, false, false, true)
    RETURNING id
), d AS (
    INSERT INTO property_type_level_templates
        (property_type_key, display_name, internal_key, order_index, parent_template_id, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
    SELECT 'office', 'Department', 'department', 1, id, 'grid', true, false, true, false FROM b
    RETURNING id
)
INSERT INTO property_type_level_templates
    (property_type_key, display_name, internal_key, order_index, parent_template_id, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
SELECT 'office', 'Cabin', 'cabin', 2, id, 'door-closed', true, true, true, true FROM d;

-- Warehouse -> Warehouse -> Zone -> Rack
WITH w AS (
    INSERT INTO property_type_level_templates
        (property_type_key, display_name, internal_key, order_index, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
    VALUES ('warehouse', 'Warehouse', 'warehouse', 0, 'warehouse', true, false, false, true)
    RETURNING id
), z AS (
    INSERT INTO property_type_level_templates
        (property_type_key, display_name, internal_key, order_index, parent_template_id, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
    SELECT 'warehouse', 'Zone', 'zone', 1, id, 'grid', true, false, true, false FROM w
    RETURNING id
)
INSERT INTO property_type_level_templates
    (property_type_key, display_name, internal_key, order_index, parent_template_id, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
SELECT 'warehouse', 'Rack', 'rack', 2, id, 'archive', true, false, true, false FROM z;

-- Hotel -> Building -> Floor -> Room
WITH b AS (
    INSERT INTO property_type_level_templates
        (property_type_key, display_name, internal_key, order_index, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
    VALUES ('hotel', 'Building', 'building', 0, 'building', true, false, false, true)
    RETURNING id
), f AS (
    INSERT INTO property_type_level_templates
        (property_type_key, display_name, internal_key, order_index, parent_template_id, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
    SELECT 'hotel', 'Floor', 'floor', 1, id, 'layers', true, false, false, false FROM b
    RETURNING id
)
INSERT INTO property_type_level_templates
    (property_type_key, display_name, internal_key, order_index, parent_template_id, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
SELECT 'hotel', 'Room', 'room', 2, id, 'door-closed', true, true, true, true FROM f;

-- Villa -> Villa (single flat level, still fully editable/expandable later)
INSERT INTO property_type_level_templates
    (property_type_key, display_name, internal_key, order_index, icon, allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
VALUES ('villa', 'Villa', 'villa', 0, 'home', true, true, true, true);

-- Custom: no templates at all — user builds from a blank canvas in the Structure Editor.
