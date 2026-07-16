// modules/structure/structure.repository.ts
// Postgres implementation of the structure-engine ports.

import { query } from '@config/db';
import {
  HierarchyLevelRepository,
  HierarchyNodeRepository,
} from '@core/structure-engine/repository.interface';
import { HierarchyLevel, CreateHierarchyLevelInput, UpdateHierarchyLevelInput } from '@core/structure-engine/entities/hierarchy-level.entity';
import { HierarchyNode, CreateHierarchyNodeInput, UpdateHierarchyNodeInput } from '@core/structure-engine/entities/hierarchy-node.entity';

function mapLevel(row: any): HierarchyLevel {
  return {
    id: row.id,
    propertyId: row.property_id,
    displayName: row.display_name,
    internalKey: row.internal_key,
    icon: row.icon,
    color: row.color,
    orderIndex: row.order_index,
    parentLevelId: row.parent_level_id,
    isEnabled: row.is_enabled,
    allowMultipleChildren: row.allow_multiple_children,
    supportsOccupancy: row.supports_occupancy,
    supportsAssets: row.supports_assets,
    supportsComplaints: row.supports_complaints,
    visibility: row.visibility,
    metadata: row.metadata ?? {},
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function mapNode(row: any): HierarchyNode {
  return {
    id: row.id,
    propertyId: row.property_id,
    levelId: row.level_id,
    parentNodeId: row.parent_node_id,
    name: row.name,
    code: row.code,
    orderIndex: row.order_index,
    isActive: row.is_active,
    metadata: row.metadata ?? {},
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

export class PgHierarchyLevelRepository implements HierarchyLevelRepository {
  async findByProperty(propertyId: string): Promise<HierarchyLevel[]> {
    const rows = await query(
      `SELECT * FROM hierarchy_levels WHERE property_id = $1`,
      [propertyId],
    );
    return rows.map(mapLevel);
  }

  async findById(id: string): Promise<HierarchyLevel | null> {
    const rows = await query(`SELECT * FROM hierarchy_levels WHERE id = $1`, [id]);
    return rows[0] ? mapLevel(rows[0]) : null;
  }

  async create(input: CreateHierarchyLevelInput & { orderIndex: number }): Promise<HierarchyLevel> {
    const rows = await query(
      `INSERT INTO hierarchy_levels
        (property_id, display_name, internal_key, icon, color, order_index, parent_level_id,
         allow_multiple_children, supports_occupancy, supports_assets, supports_complaints, visibility)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
       RETURNING *`,
      [
        input.propertyId, input.displayName, input.internalKey, input.icon ?? null,
        input.color ?? null, input.orderIndex, input.parentLevelId ?? null,
        input.allowMultipleChildren ?? true, input.supportsOccupancy ?? false,
        input.supportsAssets ?? false, input.supportsComplaints ?? false,
        input.visibility ?? 'internal',
      ],
    );
    return mapLevel(rows[0]);
  }

  async update(id: string, input: UpdateHierarchyLevelInput): Promise<HierarchyLevel> {
    const fields: string[] = [];
    const values: any[] = [];
    let i = 1;

    const columnMap: Record<string, string> = {
      displayName: 'display_name', icon: 'icon', color: 'color', isEnabled: 'is_enabled',
      allowMultipleChildren: 'allow_multiple_children', supportsOccupancy: 'supports_occupancy',
      supportsAssets: 'supports_assets', supportsComplaints: 'supports_complaints',
      visibility: 'visibility', metadata: 'metadata',
    };

    for (const [key, column] of Object.entries(columnMap)) {
      const value = (input as any)[key];
      if (value !== undefined) {
        fields.push(`${column} = $${i++}`);
        values.push(value);
      }
    }
    fields.push(`updated_at = now()`);
    values.push(id);

    const rows = await query(
      `UPDATE hierarchy_levels SET ${fields.join(', ')} WHERE id = $${i} RETURNING *`,
      values,
    );
    return mapLevel(rows[0]);
  }

  async updateOrder(propertyId: string, orderedIds: string[]): Promise<void> {
    await Promise.all(
      orderedIds.map((id, index) =>
        query(`UPDATE hierarchy_levels SET order_index = $1 WHERE id = $2 AND property_id = $3`, [
          index, id, propertyId,
        ]),
      ),
    );
  }

  async delete(id: string): Promise<void> {
    await query(`DELETE FROM hierarchy_levels WHERE id = $1`, [id]);
  }

  async countNodesUsingLevel(levelId: string): Promise<number> {
    const rows = await query<{ count: string }>(
      `SELECT COUNT(*)::text AS count FROM hierarchy_nodes WHERE level_id = $1`,
      [levelId],
    );
    return Number(rows[0]?.count ?? 0);
  }
}

export class PgHierarchyNodeRepository implements HierarchyNodeRepository {
  async findByLevel(levelId: string, parentNodeId?: string | null): Promise<HierarchyNode[]> {
    const rows = parentNodeId
      ? await query(`SELECT * FROM hierarchy_nodes WHERE level_id = $1 AND parent_node_id = $2`, [levelId, parentNodeId])
      : await query(`SELECT * FROM hierarchy_nodes WHERE level_id = $1 AND parent_node_id IS NULL`, [levelId]);
    return rows.map(mapNode);
  }

  async findById(id: string): Promise<HierarchyNode | null> {
    const rows = await query(`SELECT * FROM hierarchy_nodes WHERE id = $1`, [id]);
    return rows[0] ? mapNode(rows[0]) : null;
  }

  async create(input: CreateHierarchyNodeInput & { orderIndex: number }): Promise<HierarchyNode> {
    const rows = await query(
      `INSERT INTO hierarchy_nodes (property_id, level_id, parent_node_id, name, code, order_index, metadata)
       VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING *`,
      [input.propertyId, input.levelId, input.parentNodeId ?? null, input.name, input.code ?? null, input.orderIndex, input.metadata ?? {}],
    );
    return mapNode(rows[0]);
  }

  async update(id: string, input: UpdateHierarchyNodeInput): Promise<HierarchyNode> {
    const fields: string[] = [];
    const values: any[] = [];
    let i = 1;
    const columnMap: Record<string, string> = { name: 'name', code: 'code', isActive: 'is_active', metadata: 'metadata' };
    for (const [key, column] of Object.entries(columnMap)) {
      const value = (input as any)[key];
      if (value !== undefined) {
        fields.push(`${column} = $${i++}`);
        values.push(value);
      }
    }
    fields.push('updated_at = now()');
    values.push(id);
    const rows = await query(`UPDATE hierarchy_nodes SET ${fields.join(', ')} WHERE id = $${i} RETURNING *`, values);
    return mapNode(rows[0]);
  }

  async delete(id: string): Promise<void> {
    await query(`DELETE FROM hierarchy_nodes WHERE id = $1`, [id]);
  }

  async countChildren(nodeId: string): Promise<number> {
    const rows = await query<{ count: string }>(
      `SELECT COUNT(*)::text AS count FROM hierarchy_nodes WHERE parent_node_id = $1`,
      [nodeId],
    );
    return Number(rows[0]?.count ?? 0);
  }
}
