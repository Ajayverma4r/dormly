# Dormly — One Platform. Every Property.

A configurable Property Operations Platform. See `docs/ARCHITECTURE.md` for the full plan.

## What's included in this first scaffold

- `docs/ARCHITECTURE.md` — full implementation plan (DB design, backend architecture,
  Flutter architecture, API structure, module dependency graph, build order).
- `backend/` — Node.js + TypeScript + Express + PostgreSQL, Clean Architecture:
  - `db/migrations/001-004` — identity, properties, **Structure Engine** (the core), occupants
  - `db/seeds/001_property_types.sql` — suggested templates for Hostel/Apartment/Office/Warehouse/Hotel/Villa
  - `core/structure-engine/` — framework-agnostic domain logic (safe rename, safe delete, reorder)
  - `modules/auth` — OTP request/verify, JWT issue/refresh
  - `modules/properties` — property creation, copies template → property's own hierarchy_levels
  - `modules/structure` — REST API for levels & nodes (CRUD, reorder, enable/disable)
  - `modules/occupants` migration only so far — proves the generic `node_id` pattern
- `mobile/` — Flutter, feature-first, Riverpod + go_router:
  - `features/structure/presentation/dynamic_dashboard/` — dashboard rendered **entirely**
    from configured hierarchy levels (no hardcoded "Room"/"Bed" anywhere)
  - `features/auth`, `features/properties` — splash → phone login → OTP → wizard flow stubs
  - `core/theme` — enterprise/minimal styling

## Running the backend locally

```bash
cd backend
cp .env.example .env
npm install
# start Postgres (docker-compose up db, or your own local instance)
docker compose up -d db
# apply migrations in order, then seed data:
psql "$DATABASE_URL" -f src/db/migrations/001_identity.sql
psql "$DATABASE_URL" -f src/db/migrations/002_properties.sql
psql "$DATABASE_URL" -f src/db/migrations/003_structure_engine.sql
psql "$DATABASE_URL" -f src/db/migrations/004_occupants.sql
psql "$DATABASE_URL" -f src/db/seeds/001_property_types.sql

npm run dev   # http://localhost:4000/health
```

Or with Docker Compose end-to-end: `docker compose up --build`.

## Running the mobile app locally

```bash
cd mobile
flutter pub get
flutter run --dart-define=API_BASE_URL=http://localhost:4000
```

## What's NOT built yet (next steps, in build order from the architecture doc)

1. Structure Editor UI (drag-reorder, rename, enable/disable, add-custom-level) — currently
   only the backend API for this exists; the Flutter screen is not built yet.
2. Full property wizard step 2/3 (suggested-structure preview + confirm) wired to the API.
3. Remaining operational modules (visitors, complaints, maintenance, assets, inventory,
   bookings, payments) — `occupants` is the only one scaffolded as the reference pattern.
4. Settings screens (General, Members, Permissions, Notifications, Billing, Integrations, Danger Zone).
5. Reports/analytics, notifications delivery, real OTP SMS provider integration.
6. Tests (unit tests for StructureService are the highest-value first target).

We'll build these one at a time — tell me which piece to do next and I'll implement it fully
(migrations if needed, backend module, Flutter screens) rather than stubbing it.
