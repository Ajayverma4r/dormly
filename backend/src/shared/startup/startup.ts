// shared/startup/startup.ts
//
// Everything the process does before and after it starts listening that
// touches the database without a user request. Each step is behind an
// explicit flag in config/runtime-flags (all default off).

import { RUNTIME_FLAG_ENV, type RuntimeFlags } from '@config/runtime-flags';
import { ensureNotificationsSchema } from '@modules/notifications/move-out-notifications';
import { ensureLiveOpsSchema } from '@modules/notifications/notify';
import {
  billingSchemaCaps,
  ensureBillingSchema,
  retireLegacyInvoiceIndex,
} from '@modules/billing/billing.service';
import { scheduleHostelBillingJob } from '@shared/jobs/hostel-billing.job';
import { scheduleSubscriptionDowngradeJob } from '@shared/jobs/subscription-downgrade.job';
import { scheduleSubscriptionExpiryWarningJob } from '@shared/jobs/subscription-expiry-warning.job';
import {
  checkSchemaReadiness,
  type MissingSchemaObject,
  type SchemaReadiness,
} from './schema-readiness';

export class SchemaNotReadyError extends Error {
  constructor(readonly missing: MissingSchemaObject[], autoMigrate: boolean) {
    const lines = missing.map((m) => `  - ${m.object} (migration ${m.migration})`).join('\n');
    super(
      `Database schema is not ready; the backend will not start.\n${lines}\n` +
        (autoMigrate
          ? `${RUNTIME_FLAG_ENV.schemaAutoMigrate}=true could not create these objects; ` +
            'apply the listed migrations manually from src/db/migrations.'
          : `${RUNTIME_FLAG_ENV.schemaAutoMigrate} is off, so no schema change was attempted. ` +
            'Apply the listed migrations manually from src/db/migrations.'),
    );
    this.name = 'SchemaNotReadyError';
  }
}

/**
 * Log-safe one-line description of a startup failure. Driver and network
 * errors can carry hostnames, users or SQL, so only the class and code are
 * reported for anything that is not a SchemaNotReadyError.
 */
export function describeStartupError(err: unknown): string {
  if (err instanceof SchemaNotReadyError) return err.message;
  const e = err as { name?: unknown; code?: unknown } | null;
  const name = typeof e?.name === 'string' ? e.name : 'Error';
  const code = typeof e?.code === 'string' ? ` (${e.code})` : '';
  return `Could not verify the database schema: ${name}${code}. Check database connectivity.`;
}

/**
 * Runs before the server listens. With DB_SCHEMA_AUTO_MIGRATE off (default)
 * this only reads the catalog. Throws SchemaNotReadyError when required
 * objects are missing.
 */
export async function prepareDatabase(flags: RuntimeFlags): Promise<SchemaReadiness> {
  if (flags.schemaAutoMigrate) {
    // eslint-disable-next-line no-console
    console.warn(
      `[startup] ${RUNTIME_FLAG_ENV.schemaAutoMigrate}=true: applying idempotent schema changes`,
    );
    await ensureNotificationsSchema();
    await ensureLiveOpsSchema();
    await ensureBillingSchema();
  }

  const readiness = await checkSchemaReadiness();
  if (readiness.missing.length > 0) {
    throw new SchemaNotReadyError(readiness.missing, flags.schemaAutoMigrate);
  }

  if (readiness.legacyIndexPresent && readiness.invoiceKind) {
    if (flags.legacyInvoiceIndexCleanup) {
      // eslint-disable-next-line no-console
      console.warn(
        `[startup] ${RUNTIME_FLAG_ENV.legacyInvoiceIndexCleanup}=true: retiring legacy invoice index`,
      );
      await retireLegacyInvoiceIndex(await billingSchemaCaps());
    } else {
      // eslint-disable-next-line no-console
      console.warn(
        '[startup] legacy index invoices_tenancy_period_start_uniq still exists after 026; ' +
          'ad hoc charges sharing a cycle start date will be rejected. Set ' +
          `${RUNTIME_FLAG_ENV.legacyInvoiceIndexCleanup}=true for one start to retire it.`,
      );
    }
  } else if (flags.legacyInvoiceIndexCleanup) {
    // eslint-disable-next-line no-console
    console.warn(
      `[startup] ${RUNTIME_FLAG_ENV.legacyInvoiceIndexCleanup}=true ignored: ` +
        (readiness.invoiceKind ? 'legacy index already absent' : 'migration 026 not applied'),
    );
  }
  return readiness;
}

export type StartedJobs = { names: string[]; timers: NodeJS.Timeout[] };

/** Starts only the in-process schedulers whose flags are on. */
export function startBackgroundJobs(
  flags: RuntimeFlags,
  env: Record<string, string | undefined> = process.env,
): StartedJobs {
  const started: StartedJobs = { names: [], timers: [] };

  if (flags.billingScheduler) {
    if (env.CRON_SECRET) {
      // eslint-disable-next-line no-console
      console.warn(
        `[startup] both ${RUNTIME_FLAG_ENV.billingScheduler}=true and CRON_SECRET are set; ` +
          'billing can be triggered by two schedulers. Use one.',
      );
    }
    started.timers.push(
      scheduleHostelBillingJob({ runOnBoot: flags.billingSchedulerRunOnBoot }),
    );
    started.names.push('hostel-billing');
  }

  if (flags.subscriptionJobs) {
    started.timers.push(
      scheduleSubscriptionDowngradeJob({ runOnBoot: flags.subscriptionJobsRunOnBoot }),
      scheduleSubscriptionExpiryWarningJob({ runOnBoot: flags.subscriptionJobsRunOnBoot }),
    );
    started.names.push('subscription-downgrade', 'subscription-expiry-warning');
  }

  // eslint-disable-next-line no-console
  console.log(
    `[startup] in-process jobs: ${started.names.length ? started.names.join(', ') : 'none'}`,
  );
  return started;
}
