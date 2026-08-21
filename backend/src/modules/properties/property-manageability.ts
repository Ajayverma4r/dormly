// modules/properties/property-manageability.ts
//
// After trial/paid expiry: never delete data. Free users may still SEE all
// properties, but may only WRITE to:
//   • every free-forever residential property (rental / house / villa)
//   • the single oldest commercial property (by created_at ASC)
// Surplus commercial properties are "frozen" — reads OK, mutations → 403.

import { query } from '@config/db';
import { EntitlementService } from '@modules/subscriptions/entitlement.service';
import {
  FREE_RESIDENTIAL_TYPES,
  isFreeResidentialType,
  isPaidSubscription,
  SubscriptionRequiredError,
} from '@shared/property-monetization';

const entitlementService = new EntitlementService();

export const EXPIRED_PROPERTY_LOCK_MESSAGE =
  'Your Premium plan has expired. Upgrade to access all your properties.';

/**
 * Oldest commercial (non free-residential) property — the one free users
 * may continue managing after downgrade.
 */
export async function getFreeTierCommercialPropertyId(
  organizationId: string,
): Promise<string | null> {
  const rows = await query<{ id: string }>(
    `SELECT id
     FROM   properties
     WHERE  organization_id = $1
       AND  property_type_key <> ALL($2::text[])
     ORDER  BY created_at ASC
     LIMIT  1`,
    [organizationId, [...FREE_RESIDENTIAL_TYPES]],
  );
  return rows[0]?.id ?? null;
}

/**
 * Whether the org may mutate this property on the current plan.
 * Paid/trialing/past_due → always true.
 */
export async function isPropertyManageable(
  organizationId: string,
  propertyId: string,
): Promise<boolean> {
  const entitlements = await entitlementService.getOrgEntitlements(organizationId);
  if (isPaidSubscription(entitlements?.planSlug, entitlements?.subscriptionStatus)) {
    return true;
  }

  const props = await query<{ id: string; property_type_key: string; organization_id: string }>(
    `SELECT id, property_type_key, organization_id FROM properties WHERE id = $1`,
    [propertyId],
  );
  const property = props[0];
  if (!property || property.organization_id !== organizationId) {
    return false;
  }

  if (isFreeResidentialType(property.property_type_key)) {
    return true;
  }

  const freeCommercialId = await getFreeTierCommercialPropertyId(organizationId);
  return property.id === freeCommercialId;
}

/**
 * Throws SubscriptionRequiredError when the property is frozen for free tier.
 */
export async function assertCanManageProperty(
  organizationId: string,
  propertyId: string,
): Promise<void> {
  const ok = await isPropertyManageable(organizationId, propertyId);
  if (!ok) {
    throw new SubscriptionRequiredError(EXPIRED_PROPERTY_LOCK_MESSAGE);
  }
}

/**
 * Annotates each property with `manageable` + `is_locked` for the Flutter list.
 * Does not filter or delete rows.
 */
export async function annotatePropertyManageability(
  organizationId: string,
  properties: Array<Record<string, unknown>>,
): Promise<Array<Record<string, unknown>>> {
  const entitlements = await entitlementService.getOrgEntitlements(organizationId);
  const paid = isPaidSubscription(
    entitlements?.planSlug,
    entitlements?.subscriptionStatus,
  );

  if (paid) {
    return properties.map((p) => ({
      ...p,
      manageable: true,
      is_locked: false,
    }));
  }

  const freeCommercialId = await getFreeTierCommercialPropertyId(organizationId);

  return properties.map((p) => {
    const typeKey = String(p.property_type_key ?? '');
    const id = String(p.id ?? '');
    const manageable =
      isFreeResidentialType(typeKey) || id === freeCommercialId;
    return {
      ...p,
      manageable,
      is_locked: !manageable,
    };
  });
}
