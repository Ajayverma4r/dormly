// core/structure-engine/entities/hierarchy-node.entity.ts
//
// A HierarchyNode is an actual instance of a HierarchyLevel — e.g. one specific
// "Building A", or one specific "Rack 12". Operational modules (occupants,
// assets, complaints...) attach to nodes, never to levels directly.

export interface HierarchyNode {
  id: string;
  propertyId: string;
  levelId: string;
  parentNodeId: string | null;
  name: string;
  code: string | null;
  orderIndex: number;
  isActive: boolean;
  metadata: Record<string, unknown>;
  createdAt: string;
  updatedAt: string;
}

export interface CreateHierarchyNodeInput {
  propertyId: string;
  levelId: string;
  parentNodeId?: string | null;
  name: string;
  code?: string | null;
  metadata?: Record<string, unknown>;
}

export interface UpdateHierarchyNodeInput {
  name?: string;
  code?: string | null;
  isActive?: boolean;
  metadata?: Record<string, unknown>;
}

// A node with its children eagerly attached — used to render the dashboard
// and structure editor as a tree without N+1 queries.
export interface HierarchyNodeTree extends HierarchyNode {
  children: HierarchyNodeTree[];
}
