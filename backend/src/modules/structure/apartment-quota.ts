// modules/structure/apartment-quota.ts
//
// Free-plan apartment limits: 1 building (tower) + 20 rooms/flats.
// Paid plans skip these checks.

import { query } from '@config/db';
import { EntitlementService } from '@modules/subscriptions/entitlement.service';
import {
  FREE_APARTMENT_MAX_BUILDINGS,
  FREE_APARTMENT_MAX_ROOMS,
  isApartmentType,
  isBuildingLevelKey,
  isPaidSubscription,
  isRoomLevelKey,
  SubscriptionRequiredError,
} from '@shared/property-monetization';

const entitlementService = new EntitlementService();

export async function assertApartmentNodeQuota(
  propertyId: string,
  levelId: string,
): Promise<void> {
  const props = await query<{ property_type_key: string; organization_id: string }>(
    `SELECT property_type_key, organization_id FROM properties WHERE id = $1`,
    [propertyId],
  );
  const property = props[0];
  if (!property || !isApartmentType(property.property_type_key)) return;

  const entitlements = await entitlementService.getOrgEntitlements(property.organization_id);
  if (isPaidSubscription(entitlements?.planSlug, entitlements?.subscriptionStatus)) {
    return;
  }

  const levels = await query<{ id: string; internal_key: string; supports_occupancy: boolean }>(
    `SELECT id, internal_key, supports_occupancy FROM hierarchy_levels WHERE id = $1`,
    [levelId],
  );
  const level = levels[0];
  if (!level) return;

  if (isBuildingLevelKey(level.internal_key)) {
    const rows = await query<{ count: string }>(
      `SELECT COUNT(*)::text AS count
       FROM   hierarchy_nodes n
       JOIN   hierarchy_levels l ON l.id = n.level_id
       WHERE  n.property_id = $1
         AND  l.internal_key = ANY($2::text[])`,
      [propertyId, ['building', 'tower']],
    );
    const count = Number(rows[0]?.count ?? 0);
    if (count >= FREE_APARTMENT_MAX_BUILDINGS) {
      throw new SubscriptionRequiredError(
        `Free Apartment plan allows ${FREE_APARTMENT_MAX_BUILDINGS} building only. Upgrade to Pro to add more.`,
      );
    }
  }

  if (isRoomLevelKey(level.internal_key) || level.supports_occupancy) {
    const rows = await query<{ count: string }>(
      `SELECT COUNT(*)::text AS count
       FROM   hierarchy_nodes n
       JOIN   hierarchy_levels l ON l.id = n.level_id
       WHERE  n.property_id = $1
         AND  (l.supports_occupancy = true OR l.internal_key = ANY($2::text[]))`,
      [propertyId, ['room', 'flat', 'bed']],
    );
    const count = Number(rows[0]?.count ?? 0);
    if (count >= FREE_APARTMENT_MAX_ROOMS) {
      throw new SubscriptionRequiredError(
        `Free Apartment plan allows ${FREE_APARTMENT_MAX_ROOMS} rooms/flats. Upgrade to Pro to add more.`,
      );
    }
  }
}
