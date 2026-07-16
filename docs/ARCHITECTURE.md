# Dormly — Implementation Plan v1

**Principle behind every decision below:** the system never encodes "Building / Floor / Room / Bed".
It only knows about **Hierarchy Levels** and **Hierarchy Nodes**. Property types are just
*seed data* (a list of suggested levels) that a wizard writes into the same generic tables
every other property type uses. Nothing downstream branches on property type.

---

## 1. Core Domain Model (the Structure Engine)

Everything in the product hangs off two tables:

- **hierarchy_levels** — the *schema* a property defines for itself (e.g. "Level 0 = Block", "Level 1 = Dorm Room").
- **hierarchy_nodes** — actual instances of those levels (e.g. "Block A", "Room 204").

```
Property
 └─ HierarchyLevel (ordered, self-describing, configurable)
     └─ HierarchyNode (actual instances, tree via parent_node_id)
         └─ Occupancy / Asset / Complaint / Booking (all reference node_id, not "room_id" or "bed_id")
```

A level is not "a room type" — it's a row of config:

| field | purpose |
|---|---|
| id | UUID |
| property_id | tenant scoping |
| display_name | what users see ("Room", "Dorm Room", "Rack"...) |
| internal_key | stable slug used in code/permissions, immutable after creation |
| icon, color | UI rendering |
| order_index | position in hierarchy |
| parent_level_id | nullable, self-referencing — defines tree depth |
| is_enabled | soft toggle without deleting data |
| allow_multiple_children | e.g. a Floor can have many Rooms |
| supports_occupancy | can Occupants live at nodes of this level? |
| supports_assets | can Assets be assigned here? |
| supports_complaints | can Complaints be raised here? |
| visibility | public/internal — for future portal use |
| metadata (jsonb) | escape hatch for anything not yet modeled |

This is the one table every future module joins against. A "Warehouse > Zone > Rack" property
and a "Hostel > Building > Floor > Room > Bed" property are represented identically — just
different rows.

---

## 2. Database Design (PostgreSQL)

```sql
-- Tenancy & Identity
users(id, phone, name, created_at, ...)
organizations(id, name, owner_user_id, created_at)
memberships(id, user_id, organization_id, role, created_at)

-- Properties
properties(id, organization_id, name, property_type_key, address, city, state,
           country, timezone, currency, language, created_at)

property_types(key, display_name, description)          -- reference/lookup table only
property_type_level_templates(id, property_type_key, display_name, internal_key,
           order_index, parent_template_id, supports_occupancy, supports_assets,
           supports_complaints, icon, color)             -- seed suggestions, copied at wizard time

-- Structure Engine (the heart)
hierarchy_levels(id, property_id, display_name, internal_key, icon, color,
           order_index, parent_level_id, is_enabled, allow_multiple_children,
           supports_occupancy, supports_assets, supports_complaints,
           visibility, metadata jsonb, created_at, updated_at)

hierarchy_nodes(id, property_id, level_id, parent_node_id, name, code,
           order_index, is_active, metadata jsonb, created_at, updated_at)

-- Generic Operational Modules (all reference node_id — never a specific level)
occupants(id, property_id, node_id, name, phone, moved_in_at, moved_out_at, status)
visitors(id, property_id, node_id, name, phone, checked_in_at, checked_out_at)
complaints(id, property_id, node_id, raised_by, category, description, status, created_at)
maintenance_tickets(id, property_id, node_id, title, description, status, assigned_to)
assets(id, property_id, node_id, name, category, purchased_at, status)
inventory_items(id, property_id, node_id, sku, name, quantity)
bookings(id, property_id, node_id, guest_name, start_date, end_date, status)
payments(id, property_id, occupant_id, amount, currency, status, due_date, paid_at)

-- Platform
notifications(id, user_id, property_id, title, body, read_at, created_at)
audit_logs(id, property_id, user_id, action, entity, entity_id, diff jsonb, created_at)
```

Key normalization rules:
- No table ever contains a column named `room_id`, `bed_id`, `floor_id`, etc. Always `node_id`.
- `property_type_key` is a label for onboarding UX only — it is **never** read by business logic
  after the wizard completes.
- Row-level tenant isolation via `property_id` on every operational table + `organization_id`
  at the top for multi-property orgs.

---

## 3. Backend Architecture (Node.js, TypeScript, Clean Architecture)

```
backend/
  src/
    config/                # env, db pool, constants
    core/                  # framework-agnostic domain layer
      structure-engine/
        entities/          # HierarchyLevel, HierarchyNode (plain TS types + invariants)
        services/          # StructureService: validate reorder, prevent breaking deletes, etc.
        repository.interface.ts
    modules/
      auth/                # OTP request/verify, JWT issue/refresh
        auth.controller.ts
        auth.service.ts
        auth.routes.ts
      organizations/
      properties/
        properties.controller.ts
        properties.service.ts
        properties.routes.ts
        property-type-templates.service.ts   # returns *suggestions* only
      structure/
        structure.controller.ts   # CRUD + reorder + enable/disable for levels & nodes
        structure.service.ts
        structure.routes.ts
      occupants/
      visitors/
      complaints/
      maintenance/
      assets/
      inventory/
      bookings/
      payments/
      notifications/
      reports/
    shared/
      middleware/          # auth guard, tenant guard, error handler, validation
      utils/
    db/
      migrations/          # SQL, timestamped
      seeds/                # property_type_level_templates seed data
    app.ts                 # express app wiring
    server.ts               # entrypoint
  test/
  Dockerfile
  docker-compose.yml
  package.json
  tsconfig.json
```

Rules enforced in code review / CI:
- Every module folder under `modules/*` (except `structure`, `properties`, `auth`,
  `organizations`) must only ever query by `node_id` + `property_id`. A lint rule / PR checklist
  item: "does this module import anything from `structure-engine` other than `node_id` lookups?"
- `structure.service.ts` is the **only** place that understands parent/child level ordering,
  reordering math, and cascade rules on delete/disable.

### API Structure (REST, versioned)

```
POST   /v1/auth/otp/request
POST   /v1/auth/otp/verify
POST   /v1/auth/refresh

GET    /v1/properties
POST   /v1/properties
GET    /v1/properties/:id

GET    /v1/property-types                 # suggestions catalogue for wizard step 2

GET    /v1/properties/:id/structure/levels
POST   /v1/properties/:id/structure/levels
PATCH  /v1/properties/:id/structure/levels/:levelId        # rename/enable/disable/config
POST   /v1/properties/:id/structure/levels/reorder
DELETE /v1/properties/:id/structure/levels/:levelId

GET    /v1/properties/:id/structure/nodes?levelId=&parentNodeId=
POST   /v1/properties/:id/structure/nodes
PATCH  /v1/properties/:id/structure/nodes/:nodeId
DELETE /v1/properties/:id/structure/nodes/:nodeId

# Operational modules — identical shape regardless of property type
GET/POST /v1/properties/:id/occupants?nodeId=
GET/POST /v1/properties/:id/complaints?nodeId=
GET/POST /v1/properties/:id/assets?nodeId=
... etc, always nodeId-scoped
```

---

## 4. Flutter Architecture (Clean Architecture, feature-first)

```
mobile/
  lib/
    core/
      network/            # dio client, interceptors (JWT), error mapping
      routing/             # go_router config, auth guard redirect
      theme/               # colors, typography, spacing — enterprise/minimal
      widgets/             # DormlyButton, DormlyCard, DormlyEmptyState, DynamicIcon
      utils/
    features/
      auth/
        data/               # AuthRepository impl, DTOs
        domain/             # entities, use cases (RequestOtp, VerifyOtp)
        presentation/       # PhoneLoginScreen, OtpScreen, controllers (Riverpod/Bloc)
      properties/
        data/
        domain/             # Property entity
        presentation/       # PropertyWizardScreen (step 1 basic info, step 2 type picker)
      structure/
        data/               # HierarchyLevel/Node repositories
        domain/             # entities + StructureTree builder
        presentation/
          structure_editor/       # drag-reorder, rename, enable/disable, add-level UI
          dynamic_dashboard/      # renders dashboard FROM hierarchy_levels — no fixed labels
      occupants/
      visitors/
      complaints/
      maintenance/
      assets/
      inventory/
      bookings/
      payments/
      settings/
    app.dart
    main.dart
  pubspec.yaml
```

Key pattern — **Dynamic Dashboard**: the dashboard screen never says `"Rooms"` or `"Beds"`.
It queries `GET /structure/levels` (enabled, ordered) and renders one card per level using
`level.display_name`, `level.icon`, `level.color`, with a count pulled from `/structure/nodes`.
Tapping a card drills into that level's nodes generically (same widget, different data).

State management: Riverpod (testable, no BuildContext coupling in business logic).
Navigation: go_router with a redirect guard: no properties → `/onboarding/create-property`;
has properties → `/dashboard`. Existing users never see onboarding again (persisted flag from
`GET /properties` result, not a local "hasSeenOnboarding" bool — always derived from server truth).

---

## 5. Navigation Flow

```
Splash → (check token) → PhoneLogin → OtpVerify → 
   GET /properties
     if empty  → EmptyDashboard → CreatePropertyWizard(step1 → step2 templates → step3 review) → Dashboard
     if not empty → Dashboard
Dashboard → tap level card → NodeListScreen(level) → NodeDetailScreen(node)
                                                        ├─ Occupants tab
                                                        ├─ Complaints tab
                                                        ├─ Assets tab
                                                        └─ ...
Dashboard → Settings → Structure → StructureEditor (reorder/rename/enable/add level)
```

---

## 6. Module Dependency Graph

```
auth ──┐
       ├─▶ properties ──▶ structure-engine ──▶ {occupants, visitors, complaints,
       │                                        maintenance, assets, inventory,
       │                                        bookings, payments}
       └─▶ organizations                                │
                                                          ▼
                                                    notifications, reports, analytics
                                                    (aggregate across all modules,
                                                     grouped by node/level generically)
```

No operational module depends on another operational module directly — they only depend on
`structure-engine` for node/level lookups. Reports/analytics are the only layer allowed to
read across multiple modules, and they do so generically (group-by `level.display_name`).

---

## 7. Future Scalability

- **New property type** = new row in `property_type_level_templates` seed data. Zero code change.
- **New operational module** (e.g. "Vehicles") = new table with `node_id` + `property_id`,
  new controller/service/routes following the existing module template. No touch to
  structure-engine or other modules.
- **White-label / multi-language**: `display_name` fields are already the source of truth
  for UI text, so i18n only needs to translate *labels*, not restructure logic.
- **Deep hierarchies**: `parent_level_id` self-reference supports arbitrary depth (e.g. a
  future "Campus > Building > Floor > Wing > Room > Bed" six-level property) with no schema change.
- **Permissions**: `hierarchy_levels.visibility` + a future `role_permissions` table can scope
  which roles see which levels/modules without new tables per property type.

---

## 8. Build Order (feature-by-feature, after this plan is approved)

1. DB migrations + seed data (property_type_level_templates for Hostel/Apartment/Office/Warehouse/Hotel/Villa)
2. Backend: auth (OTP+JWT) → properties → structure-engine CRUD/reorder
3. Backend: one operational module end-to-end (occupants) to validate the generic pattern
4. Flutter: splash/auth flow → property wizard → dynamic dashboard → structure editor
5. Flutter: occupants module (proves dynamic pattern on client)
6. Remaining operational modules, repeated using the same template
7. Reports/analytics, notifications, billing, permissions

We will build in this order, one step at a time, so you can review each piece before we move on.
