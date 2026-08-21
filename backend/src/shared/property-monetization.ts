// shared/property-monetization.ts
//
// Free-forever residential types vs subscription-limited types.

/** Catalog keys that are 100% free forever (unlimited create, ads-supported). */
export const FREE_RESIDENTIAL_TYPES = [
  'rental', // Rental Property
  'house',  // Independent House
  'villa',  // Villa
] as const;

/** Apartment is subscription-limited: 1 building + 20 rooms/flats on Free. */
export const APARTMENT_TYPE = 'apartment';

export const FREE_APARTMENT_MAX_BUILDINGS = 1;
export const FREE_APARTMENT_MAX_ROOMS = 20;

/** Level internal_keys that count as "buildings" for apartment free limits. */
export const BUILDING_LEVEL_KEYS = ['building', 'tower'] as const;

/** Level internal_keys that count as "rooms" for apartment free limits. */
export const ROOM_LEVEL_KEYS = ['room', 'flat', 'bed'] as const;

export type FreeResidentialType = (typeof FREE_RESIDENTIAL_TYPES)[number];

export function isFreeResidentialType(propertyTypeKey: string): boolean {
  return (FREE_RESIDENTIAL_TYPES as readonly string[]).includes(propertyTypeKey);
}

export function isApartmentType(propertyTypeKey: string): boolean {
  return propertyTypeKey === APARTMENT_TYPE;
}

/** Types that get 1 free property, then require paid for more. */
export function isSubscriptionLimitedPropertyType(propertyTypeKey: string): boolean {
  return !isFreeResidentialType(propertyTypeKey);
}

export function isBuildingLevelKey(internalKey: string): boolean {
  return (BUILDING_LEVEL_KEYS as readonly string[]).includes(internalKey);
}

export function isRoomLevelKey(internalKey: string): boolean {
  return (ROOM_LEVEL_KEYS as readonly string[]).includes(internalKey);
}

/** Paid / unlimited access — not on the free plan. */
export function isPaidSubscription(
  planSlug: string | null | undefined,
  status: string | null | undefined,
): boolean {
  if (!planSlug || planSlug === 'free') return false;
  return status === 'active' || status === 'trialing' || status === 'past_due';
}

export function monetizationMetaForType(propertyTypeKey: string) {
  if (isFreeResidentialType(propertyTypeKey)) {
    return { tier: 'free_forever', badge: 'Free with Ads', freeLimit: null };
  }
  if (isApartmentType(propertyTypeKey)) {
    return {
      tier: 'apartment',
      badge: '1 Building + 20 Rooms free',
      freeLimit: { buildings: FREE_APARTMENT_MAX_BUILDINGS, rooms: FREE_APARTMENT_MAX_ROOMS },
    };
  }
  return { tier: 'commercial', badge: '1 Free, Upgrade for Multi-property', freeLimit: 1 };
}

export class SubscriptionRequiredError extends Error {
  readonly statusCode = 403;
  readonly code = 'SUBSCRIPTION_REQUIRED';

  constructor(message = 'Upgrade required to create another commercial property.') {
    super(message);
    this.name = 'SubscriptionRequiredError';
  }
}
