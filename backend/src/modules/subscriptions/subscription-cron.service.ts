// modules/subscriptions/subscription-cron.service.ts
//
// Daily subscription maintenance helpers (expiry warnings, future renewals).

import { query } from '@config/db';

const WARNING_TYPE = 'subscription_expiry_warning';
const WARNING_TITLE = 'Subscription ending soon';
const WARNING_BODY =
  'Your subscription ends in 7 days. Please renew to keep your premium features.';

export class SubscriptionCronService {
  /**
   * Finds Premium/trial subscriptions expiring in exactly 7 days and creates
   * an in-app notification for each org owner (once per user per day).
   * Skips orgs with auto_renew / mandate_active (they get a quieter UX).
   *
   * @returns number of notifications inserted
   */
  async sendSevenDayExpiryWarnings(): Promise<number> {
    let targets: Array<{
      organization_id: string;
      status: string;
      auto_renew: boolean;
      mandate_active: boolean;
      cancel_at_period_end: boolean;
    }>;

    try {
      targets = await query(
        `SELECT s.organization_id,
                s.status,
                COALESCE(s.auto_renew, false)      AS auto_renew,
                COALESCE(s.mandate_active, false)  AS mandate_active,
                s.cancel_at_period_end
         FROM   subscriptions s
         JOIN   plans p ON p.id = s.plan_id
         WHERE  p.slug <> 'free'
           AND  s.status IN ('trialing', 'active', 'cancelled')
           AND  (
                  (s.status = 'trialing'
                     AND s.trial_ends_at IS NOT NULL
                     AND (s.trial_ends_at::date - CURRENT_DATE) = 7)
               OR (s.status IN ('active', 'cancelled')
                     AND (s.current_period_end::date - CURRENT_DATE) = 7)
               )`,
      );
    } catch (err) {
      // Migration 011 not applied yet — skip quietly until columns exist.
      // eslint-disable-next-line no-console
      console.warn(
        '[subscription-cron] Skipping 7-day warnings (run migration 011_subscription_auto_renew.sql):',
        err instanceof Error ? err.message : err,
      );
      return 0;
    }

    let inserted = 0;

    for (const row of targets) {
      // AutoPay / eMandate: skip the urgent "please renew" push; UI shows a subtle banner instead.
      const willAutoRenew =
        (row.auto_renew || row.mandate_active) && !row.cancel_at_period_end;
      if (willAutoRenew) continue;

      const owners = await query<{ user_id: string }>(
        `SELECT user_id
         FROM   memberships
         WHERE  organization_id = $1
           AND  role IN ('owner', 'admin')`,
        [row.organization_id],
      );

      for (const owner of owners) {
        const existing = await query<{ id: string }>(
          `SELECT id FROM notifications
           WHERE  user_id = $1
             AND  type = $2
             AND  created_at::date = CURRENT_DATE
           LIMIT 1`,
          [owner.user_id, WARNING_TYPE],
        );
        if (existing.length) continue;

        await query(
          `INSERT INTO notifications (user_id, property_id, type, title, body)
           VALUES ($1, NULL, $2, $3, $4)`,
          [owner.user_id, WARNING_TYPE, WARNING_TITLE, WARNING_BODY],
        );
        inserted += 1;
      }
    }

    return inserted;
  }
}
