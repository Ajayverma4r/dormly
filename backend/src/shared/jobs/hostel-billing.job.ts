// Generates check-in anniversary rent invoices for every property type.

import { BillingService } from '@modules/billing/billing.service';

const service = new BillingService();

export async function runHostelBillingJob(): Promise<void> {
  const created = await service.ensureAllHostelPgAnniversaryInvoices();
  if (created > 0) {
    // eslint-disable-next-line no-console
    console.log(`[hostel-billing] Generated ${created} anniversary invoice(s).`);
  }
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
