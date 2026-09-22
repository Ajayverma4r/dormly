// modules/tenant-portal/property-type-access.ts
//
// Server-side feature gates by the 3-archetype model.
// Canonical keys: hostel_pg | apartment | rental_house

export type TenantFeature =
  | 'mess_menu'
  | 'gate_pass'
  | 'society_notices'
  | 'meter_reading'
  | 'lease_details';

/** Canonical property_type_key values (3-archetype catalog). */
export type PropertyKind = 'hostel_pg' | 'apartment' | 'rental_house';

export function resolvePropertyKind(raw: unknown): PropertyKind {
  const key = String(raw ?? '')
    .trim()
    .toLowerCase();
  switch (key) {
    case 'hostel':
    case 'pg':
    case 'hostel_pg':
    case 'coliving':
    case 'staff_housing':
    case 'hotel':
      return 'hostel_pg';
    case 'apartment':
    case 'flat':
      return 'apartment';
    case 'rental':
    case 'rental_house':
    case 'house':
    case 'villa':
    case 'independent':
    case 'commercial':
    case 'office':
    case 'warehouse':
    case 'factory':
    case 'parking':
    case 'school':
    case 'hospital':
    case 'resort':
    case 'custom':
      return 'rental_house';
    default:
      if (!key) return 'hostel_pg';
      return 'rental_house';
  }
}

const FEATURE_KINDS: Record<TenantFeature, PropertyKind[]> = {
  mess_menu: ['hostel_pg'],
  gate_pass: ['apartment'],
  society_notices: ['apartment'],
  meter_reading: ['apartment', 'rental_house'],
  lease_details: ['rental_house', 'apartment'],
};

export class FeatureNotAllowedError extends Error {
  readonly status = 403;
  readonly code = 'FEATURE_NOT_ALLOWED';

  constructor(
    public readonly feature: TenantFeature,
    public readonly kind: PropertyKind,
  ) {
    super(
      `Feature "${feature}" is not available for property type "${kind}".`,
    );
    this.name = 'FeatureNotAllowedError';
  }
}

export function assertFeatureAllowed(
  tenancy: { property_type_key?: unknown; propertyTypeKey?: unknown },
  feature: TenantFeature,
): PropertyKind {
  const kind = resolvePropertyKind(
    tenancy.property_type_key ?? tenancy.propertyTypeKey,
  );
  const allowed = FEATURE_KINDS[feature];
  if (!allowed.includes(kind)) {
    throw new FeatureNotAllowedError(feature, kind);
  }
  return kind;
}

export function isFeatureAllowed(
  tenancy: { property_type_key?: unknown; propertyTypeKey?: unknown },
  feature: TenantFeature,
): boolean {
  try {
    assertFeatureAllowed(tenancy, feature);
    return true;
  } catch {
    return false;
  }
}
