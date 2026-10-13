// config/runtime-flags.ts
//
// Deployment switches for anything that changes the database or runs work in
// the background without a user request. Every flag is off unless its
// environment variable is exactly "true" (case-insensitive). Read on demand so
// tests can toggle them; this module must not import config/env.

export const RUNTIME_FLAG_ENV = {
  /** Idempotent schema changes (ALTER/CREATE) from ensure*Schema(). */
  schemaAutoMigrate: 'DB_SCHEMA_AUTO_MIGRATE',
  /** One-off post-026 relabel of old one-day charges + DROP of the legacy index. */
  legacyInvoiceIndexCleanup: 'LEGACY_INVOICE_INDEX_CLEANUP',
  /** In-process hourly hostel billing timer. */
  billingScheduler: 'BILLING_SCHEDULER_ENABLED',
  /** Also run the billing job once when the process starts. */
  billingSchedulerRunOnBoot: 'BILLING_SCHEDULER_RUN_ON_BOOT',
  /** In-process subscription downgrade (hourly) and expiry warning (daily) timers. */
  subscriptionJobs: 'SUBSCRIPTION_JOBS_ENABLED',
  /** Also run the subscription jobs shortly after the process starts. */
  subscriptionJobsRunOnBoot: 'SUBSCRIPTION_JOBS_RUN_ON_BOOT',
} as const;

export type RuntimeFlags = { [K in keyof typeof RUNTIME_FLAG_ENV]: boolean };

type Env = Record<string, string | undefined>;

function parseFlag(name: string, env: Env): boolean {
  const raw = (env[name] ?? '').trim().toLowerCase();
  if (raw === 'true') return true;
  if (raw !== '' && raw !== 'false') {
    // eslint-disable-next-line no-console
    console.warn(`[config] ${name} must be "true" or "false"; treating it as false`);
  }
  return false;
}

export function readRuntimeFlags(env: Env = process.env): RuntimeFlags {
  return Object.fromEntries(
    Object.entries(RUNTIME_FLAG_ENV).map(([key, name]) => [key, parseFlag(name, env)]),
  ) as RuntimeFlags;
}

export function schemaAutoMigrateEnabled(env: Env = process.env): boolean {
  return parseFlag(RUNTIME_FLAG_ENV.schemaAutoMigrate, env);
}
