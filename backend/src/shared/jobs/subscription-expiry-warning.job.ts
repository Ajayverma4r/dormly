// shared/jobs/subscription-expiry-warning.job.ts
//
// Daily cron: notify org owners whose Premium / trial ends in exactly 7 days.
// Writes in-app notification rows (no push provider required yet).
//
// Dedupes per user per calendar day via type = subscription_expiry_warning.

import { query } from '@config/db';
import { SubscriptionCronService } from '@modules/subscriptions/subscription-cron.service';

const cron = new SubscriptionCronService();

export async function runSubscriptionExpiryWarningJob(): Promise<void> {
  const count = await cron.sendSevenDayExpiryWarnings();
  if (count > 0) {
    // eslint-disable-next-line no-console
    console.log(
      `[subscription-expiry-warning] Created ${count} in-app notification(s).`,
    );
  }
}

/**
 * Schedules the daily 7-day expiry warning job.
 * Default: every 24 hours, plus one run shortly after startup.
 */
export function scheduleSubscriptionExpiryWarningJob(
  intervalMs = 24 * 60 * 60 * 1000,
): NodeJS.Timeout {
  // Delay startup run slightly so DB pool is ready
  setTimeout(() => {
    runSubscriptionExpiryWarningJob().catch((err) => {
      // eslint-disable-next-line no-console
      console.error('[subscription-expiry-warning] Startup run failed:', err);
    });
  }, 15_000);

  return setInterval(() => {
    runSubscriptionExpiryWarningJob().catch((err) => {
      // eslint-disable-next-line no-console
      console.error('[subscription-expiry-warning] Scheduled run failed:', err);
    });
  }, intervalMs);
}

/** Exposed for tests / manual admin triggers. */
export async function findSubscriptionsExpiringInDays(days: number) {
  return query(
    `SELECT s.id, s.organization_id, s.status, s.auto_renew, s.mandate_active,
            s.trial_ends_at, s.current_period_end, s.cancel_at_period_end
     FROM   subscriptions s
     JOIN   plans p ON p.id = s.plan_id
     WHERE  p.slug <> 'free'
       AND  s.status IN ('trialing', 'active', 'cancelled')
       AND  (
              (s.status = 'trialing'
                 AND s.trial_ends_at IS NOT NULL
                 AND (s.trial_ends_at::date - CURRENT_DATE) = $1)
           OR (s.status IN ('active', 'cancelled')
                 AND (s.current_period_end::date - CURRENT_DATE) = $1)
           )`,
    [days],
  );
}
