// core/structure-engine/entities/hierarchy-level.entity.ts
//
// A HierarchyLevel is the ONLY concept the system has for "a tier in a property's
// structure". It is deliberately generic: nothing here says "Room" or "Bed".

export type Visibility = 'internal' | 'public';

export interface HierarchyLevel {
  id: string;
  propertyId: string;
  displayName: string;
  internalKey: string;          // immutable once created
  icon: string | null;
  color: string | null;
  orderIndex: number;
  parentLevelId: string | null;
  isEnabled: boolean;
  allowMultipleChildren: boolean;
  supportsOccupancy: boolean;
  supportsAssets: boolean;
  supportsComplaints: boolean;
  visibility: Visibility;
  metadata: Record<string, unknown>;
  createdAt: string;
  updatedAt: string;
}

export interface CreateHierarchyLevelInput {
  propertyId: string;
  displayName: string;
  internalKey: string;
  icon?: string | null;
  color?: string | null;
  parentLevelId?: string | null;
  allowMultipleChildren?: boolean;
  supportsOccupancy?: boolean;
  supportsAssets?: boolean;
  supportsComplaints?: boolean;
  visibility?: Visibility;
}

export interface UpdateHierarchyLevelInput {
  displayName?: string;
  icon?: string | null;
  color?: string | null;
  isEnabled?: boolean;
  allowMultipleChildren?: boolean;
  supportsOccupancy?: boolean;
  supportsAssets?: boolean;
  supportsComplaints?: boolean;
  visibility?: Visibility;
  metadata?: Record<string, unknown>;
  // Note: internalKey and parentLevelId are intentionally NOT editable after
  // creation — changing them would silently corrupt every node under this level.
}
