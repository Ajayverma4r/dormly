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

export const MAX_NODE_NAME_LENGTH = 80;

/** Trimmed, single-spaced node name, or a validation error for the user. */
export function normalizeNodeName(raw: unknown): string {
  if (typeof raw !== 'string') throw new StructureValidationError('Name is required.');
  const name = raw.replace(/\s+/g, ' ').trim();
  if (!name) throw new StructureValidationError('Name cannot be empty.');
  if (name.length > MAX_NODE_NAME_LENGTH) {
    throw new StructureValidationError(`Name can be at most ${MAX_NODE_NAME_LENGTH} characters.`);
  }
  return name;
}

/**
 * Lower-cased label a node is shown with: a bare "109" on the Room level reads
 * "Room 109", while a name that already mentions its level is shown as is.
 * Two siblings with the same label are duplicates. Mirrored in SQL by
 * PgHierarchyNodeRepository.findSiblingByLabel.
 */
export function nodeLabelKey(name: string, levelName: string | null | undefined): string {
  const n = name.replace(/\s+/g, ' ').trim().toLowerCase();
  const l = (levelName ?? '').replace(/\s+/g, ' ').trim().toLowerCase();
  return !l || n.includes(l) ? n : `${l} ${n}`;
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

  /** Nodes of [propertyId] only; a level or parent from another property yields none. */
  async listNodes(
    propertyId: string,
    levelId: string,
    parentNodeId?: string | null,
  ): Promise<HierarchyNode[]> {
    const rows = await this.nodes.findByLevel(levelId, parentNodeId ?? null, propertyId);
    return rows.sort((a, b) => a.orderIndex - b.orderIndex);
  }

  async createNode(input: CreateHierarchyNodeInput): Promise<HierarchyNode> {
    const level = await this.levels.findById(input.levelId);
    if (!level || level.propertyId !== input.propertyId) {
      throw new StructureValidationError('Level not found.');
    }
    if (input.parentNodeId) {
      const parent = await this.nodes.findById(input.parentNodeId);
      if (!parent || parent.propertyId !== input.propertyId) {
        throw new StructureValidationError('Parent node not found.');
      }
    }
    if (!level.isEnabled) {
      throw new StructureValidationError('Cannot add a node to a disabled level.');
    }

    const name = normalizeNodeName(input.name);
    const siblings = await this.nodes.findByLevel(input.levelId, input.parentNodeId ?? null);
    if (!level.allowMultipleChildren && siblings.length >= 1) {
      throw new StructureValidationError(
        `"${level.displayName}" does not allow multiple entries under the same parent.`,
      );
    }
    await this.assertNameFree(
      input.propertyId,
      input.parentNodeId ?? null,
      nodeLabelKey(name, level.displayName),
    );

    return this.nodes.create({ ...input, name, orderIndex: siblings.length });
  }

  async updateNode(nodeId: string, input: UpdateHierarchyNodeInput): Promise<HierarchyNode> {
    if (input.name === undefined) return this.nodes.update(nodeId, input);
    const name = normalizeNodeName(input.name);
    const node = await this.nodes.findById(nodeId);
    if (!node) throw new StructureValidationError('Node not found.');
    const level = await this.levels.findById(node.levelId);
    await this.assertNameFree(
      node.propertyId,
      node.parentNodeId ?? null,
      nodeLabelKey(name, level?.displayName),
      nodeId,
    );
    return this.nodes.update(nodeId, { ...input, name });
  }

  // Labels are unique among the children of one parent (rooms on a floor, beds
  // in a room, top-level blocks of a property), ignoring case and spacing.
  private async assertNameFree(
    propertyId: string,
    parentNodeId: string | null,
    labelKey: string,
    excludeNodeId?: string,
  ): Promise<void> {
    const clash = await this.nodes.findSiblingByLabel(
      propertyId,
      parentNodeId,
      labelKey,
      excludeNodeId,
    );
    if (!clash) return;
    const parent = parentNodeId ? await this.nodes.findById(parentNodeId) : null;
    const where = parent?.name ? parent.name : 'this property';
    const kind = clash.levelName?.trim() || 'space';
    throw new StructureValidationError(
      `A ${kind} named "${clash.name}" already exists in ${where}. Choose a different name.`,
    );
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
