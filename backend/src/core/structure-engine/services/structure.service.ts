// core/structure-engine/services/structure.service.ts
//
// This is the single authority for structure mutations. Every rule that keeps
// "rename Building -> Block without breaking anything" true lives here.

import {
  HierarchyLevel,
  CreateHierarchyLevelInput,
  UpdateHierarchyLevelInput,
} from '../entities/hierarchy-level.entity';
import {
  HierarchyNode,
  CreateHierarchyNodeInput,
  UpdateHierarchyNodeInput,
} from '../entities/hierarchy-node.entity';
import {
  HierarchyLevelRepository,
  HierarchyNodeRepository,
} from '../repository.interface';

export class StructureValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'StructureValidationError';
  }
}

export class StructureService {
  constructor(
    private readonly levels: HierarchyLevelRepository,
    private readonly nodes: HierarchyNodeRepository,
  ) {}

  async listLevels(propertyId: string): Promise<HierarchyLevel[]> {
    const rows = await this.levels.findByProperty(propertyId);
    return rows.sort((a, b) => a.orderIndex - b.orderIndex);
  }

  async createLevel(input: CreateHierarchyLevelInput): Promise<HierarchyLevel> {
    const existing = await this.levels.findByProperty(input.propertyId);

    if (existing.some((l) => l.internalKey === input.internalKey)) {
      throw new StructureValidationError(
        `A level with internal key "${input.internalKey}" already exists for this property.`,
      );
    }

    if (input.parentLevelId) {
      const parent = existing.find((l) => l.id === input.parentLevelId);
      if (!parent) {
        throw new StructureValidationError('Parent level not found on this property.');
      }
    }

    const nextOrder =
      existing.filter((l) => (l.parentLevelId ?? null) === (input.parentLevelId ?? null))
        .length;

    return this.levels.create({ ...input, orderIndex: nextOrder });
  }

  // Renaming (display_name) is always safe: internal_key, and therefore every
  // foreign key relationship and permission rule, is untouched.
  async renameLevel(levelId: string, displayName: string): Promise<HierarchyLevel> {
    if (!displayName.trim()) {
      throw new StructureValidationError('Display name cannot be empty.');
    }
    return this.levels.update(levelId, { displayName: displayName.trim() });
  }

  async setLevelEnabled(levelId: string, isEnabled: boolean): Promise<HierarchyLevel> {
    // Disabling hides a level from the dashboard/wizard but preserves all data —
    // this is the safe alternative to delete that the spec calls for.
    return this.levels.update(levelId, { isEnabled });
  }

  async updateLevelConfig(
    levelId: string,
    input: UpdateHierarchyLevelInput,
  ): Promise<HierarchyLevel> {
    return this.levels.update(levelId, input);
  }

  async reorderLevels(propertyId: string, orderedIds: string[]): Promise<void> {
    const existing = await this.levels.findByProperty(propertyId);
    const existingIds = new Set(existing.map((l) => l.id));

    if (
      orderedIds.length !== existing.length ||
      !orderedIds.every((id) => existingIds.has(id))
    ) {
      throw new StructureValidationError(
        'Reorder payload must include exactly the existing levels for this property.',
      );
    }

    await this.levels.updateOrder(propertyId, orderedIds);
  }

  // Deleting a level that already has nodes would silently orphan real data
  // (occupants, complaints, assets...). We refuse and ask the caller to
  // disable instead, unless they explicitly confirm cascade deletion.
  async deleteLevel(levelId: string, options: { forceCascade?: boolean } = {}): Promise<void> {
    const nodeCount = await this.levels.countNodesUsingLevel(levelId);
    if (nodeCount > 0 && !options.forceCascade) {
      throw new StructureValidationError(
        `This level has ${nodeCount} existing node(s). Disable it instead, or confirm cascade delete.`,
      );
    }
    await this.levels.delete(levelId);
  }

  // ---- Nodes ----

  async listNodes(levelId: string, parentNodeId?: string | null): Promise<HierarchyNode[]> {
    const rows = await this.nodes.findByLevel(levelId, parentNodeId ?? null);
    return rows.sort((a, b) => a.orderIndex - b.orderIndex);
  }

  async createNode(input: CreateHierarchyNodeInput): Promise<HierarchyNode> {
    const level = await this.levels.findById(input.levelId);
    if (!level) {
      throw new StructureValidationError('Level not found.');
    }
    if (!level.isEnabled) {
      throw new StructureValidationError('Cannot add a node to a disabled level.');
    }

    const siblings = await this.nodes.findByLevel(input.levelId, input.parentNodeId ?? null);
    if (!level.allowMultipleChildren && siblings.length >= 1) {
      throw new StructureValidationError(
        `"${level.displayName}" does not allow multiple entries under the same parent.`,
      );
    }

    return this.nodes.create({ ...input, orderIndex: siblings.length });
  }

  async updateNode(nodeId: string, input: UpdateHierarchyNodeInput): Promise<HierarchyNode> {
    return this.nodes.update(nodeId, input);
  }

  async deleteNode(nodeId: string): Promise<void> {
    const childCount = await this.nodes.countChildren(nodeId);
    if (childCount > 0) {
      throw new StructureValidationError(
        `This node has ${childCount} child node(s). Remove or reassign them first.`,
      );
    }
    await this.nodes.delete(nodeId);
  }
}
