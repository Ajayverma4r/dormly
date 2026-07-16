// core/structure-engine/repository.interface.ts
//
// Ports the service layer depends on. The Postgres implementation lives in
// modules/structure/structure.repository.ts. Keeping this as an interface
// means the domain logic (ordering, cascade rules) is unit-testable without a DB.

import {
  HierarchyLevel,
  CreateHierarchyLevelInput,
  UpdateHierarchyLevelInput,
} from './entities/hierarchy-level.entity';
import {
  HierarchyNode,
  CreateHierarchyNodeInput,
  UpdateHierarchyNodeInput,
} from './entities/hierarchy-node.entity';

export interface HierarchyLevelRepository {
  findByProperty(propertyId: string): Promise<HierarchyLevel[]>;
  findById(id: string): Promise<HierarchyLevel | null>;
  create(input: CreateHierarchyLevelInput & { orderIndex: number }): Promise<HierarchyLevel>;
  update(id: string, input: UpdateHierarchyLevelInput): Promise<HierarchyLevel>;
  updateOrder(propertyId: string, orderedIds: string[]): Promise<void>;
  delete(id: string): Promise<void>;
  countNodesUsingLevel(levelId: string): Promise<number>;
}

export interface HierarchyNodeRepository {
  findByLevel(levelId: string, parentNodeId?: string | null): Promise<HierarchyNode[]>;
  findById(id: string): Promise<HierarchyNode | null>;
  create(input: CreateHierarchyNodeInput & { orderIndex: number }): Promise<HierarchyNode>;
  update(id: string, input: UpdateHierarchyNodeInput): Promise<HierarchyNode>;
  delete(id: string): Promise<void>;
  countChildren(nodeId: string): Promise<number>;
}
