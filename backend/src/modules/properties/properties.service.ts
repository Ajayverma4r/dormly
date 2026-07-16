// modules/properties/properties.service.ts
//
// Creating a property copies the chosen property_type's SUGGESTED level
// templates into that property's own hierarchy_levels — but now the wizard
// can override which levels are enabled and what they're renamed to BEFORE
// creation, per the "MOST IMPORTANT FEATURE" requirement. Overrides are
// keyed by internal_key (stable across templates). Parent resolution always
// walks up to the nearest ENABLED ancestor, so disabling a middle level
// doesn't orphan its children.

import { query } from '@config/db';

interface LevelOverride {
  displayName?: string;
  enabled?: boolean;
}

interface CreatePropertyInput {
  organizationId: string;
  name: string;
  propertyTypeKey: string;
  address?: string;
  city?: string;
  state?: string;
  country?: string;
  timezone: string;
  currency: string;
  language: string;
  levelOverrides?: Record<string, LevelOverride>;
}

export class PropertiesService {
  async listForOrganization(organizationId: string) {
    return query(`SELECT * FROM properties WHERE organization_id = $1 ORDER BY created_at DESC`, [organizationId]);
  }

  async listPropertyTypes() {
    return query(`SELECT * FROM property_types ORDER BY display_name`);
  }

  async previewTemplate(propertyTypeKey: string) {
    return query(
      `SELECT * FROM property_type_level_templates WHERE property_type_key = $1 ORDER BY order_index`,
      [propertyTypeKey],
    );
  }

  async getById(propertyId: string) {
    const rows = await query(`SELECT * FROM properties WHERE id = $1`, [propertyId]);
    return rows[0] ?? null;
  }

  async create(input: CreatePropertyInput) {
    const [property] = await query<{ id: string }>(
      `INSERT INTO properties
        (organization_id, name, property_type_key, address, city, state, country, timezone, currency, language)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) RETURNING *`,
      [
        input.organizationId, input.name, input.propertyTypeKey, input.address ?? null,
        input.city ?? null, input.state ?? null, input.country ?? null,
        input.timezone, input.currency, input.language,
      ],
    );

    await this.seedHierarchyFromTemplate(
      (property as any).id,
      input.propertyTypeKey,
      input.levelOverrides ?? {},
    );
    await this.seedDefaultChargeTypes((property as any).id);
    return property;
  }

  private async seedHierarchyFromTemplate(
    propertyId: string,
    propertyTypeKey: string,
    overrides: Record<string, LevelOverride>,
  ) {
    const templates = await query<any>(
      `SELECT * FROM property_type_level_templates WHERE property_type_key = $1 ORDER BY order_index`,
      [propertyTypeKey],
    );

    // template.id -> effective enabled state, resolved once up front so parent
    // lookups can walk the chain without re-deciding enabled-ness each time.
    const enabledMap = new Map<string, boolean>();
    for (const t of templates) {
      const override = overrides[t.internal_key];
      enabledMap.set(t.id, override?.enabled ?? true);
    }

    // template.id -> newly created hierarchy_levels.id (only set for enabled ones)
    const idMap = new Map<string, string>();

    // Finds the nearest enabled ancestor's NEW id, skipping any disabled
    // levels in between, so disabling a middle tier never orphans children.
    function resolveParentLevelId(templateId: string | null): string | null {
      let currentId = templateId;
      while (currentId) {
        const current = templates.find((t: any) => t.id === currentId);
        if (!current) return null;
        if (enabledMap.get(current.id) && idMap.has(current.id)) {
          return idMap.get(current.id)!;
        }
        currentId = current.parent_template_id;
      }
      return null;
    }

    for (const t of templates) {
      if (!enabledMap.get(t.id)) continue; // skip disabled — user can add it back later via Structure Editor

      const override = overrides[t.internal_key];
      const displayName = override?.displayName?.trim() || t.display_name;
      const parentLevelId = resolveParentLevelId(t.parent_template_id);

      const [level] = await query<{ id: string }>(
        `INSERT INTO hierarchy_levels
          (property_id, display_name, internal_key, icon, order_index, parent_level_id,
           allow_multiple_children, supports_occupancy, supports_assets, supports_complaints)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) RETURNING id`,
        [
          propertyId, displayName, t.internal_key, t.icon, t.order_index, parentLevelId,
          t.allow_multiple_children, t.supports_occupancy, t.supports_assets, t.supports_complaints,
        ],
      );
      idMap.set(t.id, (level as any).id);
    }
  }
  private async seedDefaultChargeTypes(propertyId: string) {
    const defaults = [
      { name: 'Rent', amount: 0, order: 0 },
      { name: 'Electricity', amount: 0, order: 1 },
      { name: 'Water', amount: 0, order: 2 },
      { name: 'Maintenance', amount: 0, order: 3 },
      { name: 'Other', amount: 0, order: 4 },
    ];
    for (const d of defaults) {
      await query(
        `INSERT INTO charge_types (property_id, name, default_amount, order_index) VALUES ($1,$2,$3,$4)`,
        [propertyId, d.name, d.amount, d.order],
      );
    }
  }
}