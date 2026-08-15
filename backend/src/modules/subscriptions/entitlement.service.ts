// modules/subscriptions/entitlement.service.ts
//
// Pure read service — the single source of truth for feature flags and quotas.
// All other modules should depend on this rather than querying plans/features
// tables directly. Never inspect plan slugs in application code; always use
// feature keys (e.g. 'can_export_pdf', 'max_properties').

import { query } from '@config/db';

export interface OrgEntitlements {
  planSlug: string;
  subscriptionStatus: string;
  trialEndsAt: Date | null;
  currentPeriodEnd: Date | null;
  gracePeriodEndsAt: Date | null;
  /** Resolved feature map: boolean features → boolean, quota features → number (-1 = unlimited). */
  features: Record<string, boolean | number>;
}

interface EntitlementRow {
  plan_slug: string;
  subscription_status: string;
  trial_ends_at: Date | null;
  current_period_end: Date | null;
  grace_period_ends_at: Date | null;
  feature_key: string;
  value_type: 'boolean' | 'quota';
  bool_value: boolean | null;
  quota_value: number | null;
}

export class EntitlementService {
  /**
   * Returns the full resolved entitlement snapshot for an organization.
   * Returns null when the org has no subscription row (treat as free).
   */
  async getOrgEntitlements(organizationId: string): Promise<OrgEntitlements | null> {
    const rows = await query<EntitlementRow>(
      `SELECT plan_slug, subscription_status, trial_ends_at, current_period_end,
              grace_period_ends_at, feature_key, value_type, bool_value, quota_value
       FROM   org_active_entitlements
       WHERE  organization_id = $1`,
      [organizationId],
    );

    if (!rows.length) return null;

    const first = rows[0];
    const features: Record<string, boolean | number> = {};
    for (const row of rows) {
      if (row.value_type === 'boolean' && row.bool_value !== null) {
        features[row.feature_key] = row.bool_value;
      } else if (row.value_type === 'quota' && row.quota_value !== null) {
        features[row.feature_key] = row.quota_value;
      }
    }

    return {
      planSlug: first.plan_slug,
      subscriptionStatus: first.subscription_status,
      trialEndsAt: first.trial_ends_at,
      currentPeriodEnd: first.current_period_end,
      gracePeriodEndsAt: first.grace_period_ends_at,
      features,
    };
  }

  /**
   * Returns the boolean value for a single feature flag.
   * Defaults to false when the org has no subscription or the feature is not mapped.
   */
  async checkBoolFeature(organizationId: string, featureKey: string): Promise<boolean> {
    const rows = await query<{ bool_value: boolean }>(
      `SELECT bool_value
       FROM   org_active_entitlements
       WHERE  organization_id = $1 AND feature_key = $2`,
      [organizationId, featureKey],
    );
    return rows[0]?.bool_value ?? false;
  }

  /**
   * Returns the numeric quota for a feature.
   *  -1  → unlimited
   *   0  → no access (not on any plan, or quota not defined)
   *  >0  → concrete limit
   */
  async checkQuota(organizationId: string, quotaKey: string): Promise<number> {
    const rows = await query<{ quota_value: number }>(
      `SELECT quota_value
       FROM   org_active_entitlements
       WHERE  organization_id = $1 AND feature_key = $2`,
      [organizationId, quotaKey],
    );
    return rows[0]?.quota_value ?? 0;
  }
}
