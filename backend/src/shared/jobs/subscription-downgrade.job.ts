// shared/jobs/subscription-downgrade.job.ts
//
// Scans for subscriptions whose trial/grace/billing period has lapsed and
// downgrades them to the free plan. Call scheduleSubscriptionDowngradeJob()
// once at server startup.
//
// CRITICAL: This job NEVER deletes properties, rooms, tenants, invoices, or
// any operational data. It only flips plan_id → free and status → expired.
// Over-quota commercial properties remain visible but become write-locked
// via requireWritableProperty / assertCanManageProperty.
//
// Production note: replace setInterval with a proper job queue (BullMQ,
// Agenda, pg-boss) or a cloud scheduler (AWS EventBridge, GCP Cloud Scheduler)
// for guaranteed execution and horizontal-scale safety.

import { SubscriptionService } from '@modules/subscriptions/subscription.service';

const service = new SubscriptionService();

export async function runSubscriptionDowngradeJob(): Promise<void> {
  const count = await service.downgradeExpiredSubscriptions();
  if (count > 0) {
    // eslint-disable-next-line no-console
    console.log(`[subscription-downgrade] Downgraded ${count} expired subscription(s) to free.`);
  }
}

/**
 * Starts a recurring in-process job that checks for expired subscriptions.
 * Default interval: every hour.
 *
 * @returns The interval handle — pass to clearInterval() to stop on shutdown.
 */
export function scheduleSubscriptionDowngradeJob(
  intervalMs = 60 * 60 * 1000,
): NodeJS.Timeout {
  // Run once immediately on startup to catch any backlog
  runSubscriptionDowngradeJob().catch((err) => {
    // eslint-disable-next-line no-console
    console.error('[subscription-downgrade] Startup run failed:', err);
  });

  return setInterval(() => {
    runSubscriptionDowngradeJob().catch((err) => {
      // eslint-disable-next-line no-console
      console.error('[subscription-downgrade] Scheduled run failed:', err);
    });
  }, intervalMs);
}
