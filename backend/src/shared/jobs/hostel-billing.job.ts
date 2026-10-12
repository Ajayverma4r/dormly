// Generates check-in anniversary rent invoices (as drafts for owner review)
// for every property type, refreshes statuses and sends overdue notices once.

import { timingSafeEqual } from 'crypto';
import type { Request, Response } from 'express';
import { BillingService } from '@modules/billing/billing.service';

const service = new BillingService();

let inFlight: Promise<number> | null = null;

/** Overlapping triggers (timer + cron endpoint) share one run. */
export function runHostelBillingJob(): Promise<number> {
  if (!inFlight) {
    inFlight = service
      .ensureAllHostelPgAnniversaryInvoices()
      .then((created) => {
        if (created > 0) {
          // eslint-disable-next-line no-console
          console.log(`[hostel-billing] Generated ${created} draft invoice(s).`);
        }
        return created;
      })
      .finally(() => {
        inFlight = null;
      });
  }
  return inFlight;
}

export function scheduleHostelBillingJob(
  intervalMs = 60 * 60 * 1000,
): NodeJS.Timeout {
  runHostelBillingJob().catch((err) => {
    // eslint-disable-next-line no-console
    console.error('[hostel-billing] Startup run failed:', err);
  });

  return setInterval(() => {
    runHostelBillingJob().catch((err) => {
      // eslint-disable-next-line no-console
      console.error('[hostel-billing] Scheduled run failed:', err);
    });
  }, intervalMs);
}

/**
 * POST /v1/internal/billing/run — for an external scheduler (Render Cron Job,
 * cron-job.org) so billing still runs when the web service has been asleep.
 * Requires header `x-cron-secret: $CRON_SECRET`; disabled when CRON_SECRET is unset.
 */
export async function hostelBillingCronHandler(req: Request, res: Response) {
  const secret = process.env.CRON_SECRET ?? '';
  if (!secret) return res.status(404).json({ error: 'Not found' });

  const provided = Buffer.from(String(req.header('x-cron-secret') ?? ''));
  const expected = Buffer.from(secret);
  if (provided.length !== expected.length || !timingSafeEqual(provided, expected)) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  try {
    const created = await runHostelBillingJob();
    res.json({ data: { created } });
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error('[hostel-billing] Cron run failed:', err);
    res.status(500).json({ error: 'Billing run failed' });
  }
}
