// Startup schema gating and in-process scheduler flags. The database is a fake
// catalog behind a mocked @config/db: no server, no network, no real database.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

type Catalog = {
  columns: string[];
  tables: string[];
  charge_kind_type: boolean;
  complaint_assigned: boolean;
  unique_indexes: string[];
};

const db = vi.hoisted(() => ({
  log: [] as { sql: string; tx: boolean }[],
  txEvents: [] as string[],
  catalog: null as unknown as Catalog,
  /** Simulates DDL taking effect (auto-migrate path). */
  onSql: (_sql: string) => undefined as void,
  connectError: null as Error | null,
}));

const jobs = vi.hoisted(() => ({
  downgrade: null as any,
  expiryWarning: null as any,
}));

vi.mock('@config/env', () => ({ env: { port: 0, nodeEnv: 'test' } }));

vi.mock('@config/db', () => {
  const run = async (sql: string, tx: boolean) => {
    if (db.connectError) throw db.connectError;
    db.log.push({ sql, tx });
    db.onSql(sql);
    if (/AS unique_indexes/.test(sql)) return [{ ...db.catalog }];
    if (/column_name IN \('invoice_kind', 'approved_by'\)/.test(sql)) {
      return db.catalog.columns
        .filter((c) => c === 'invoices.invoice_kind' || c === 'invoices.approved_by')
        .map((c) => ({ column_name: c.split('.')[1] }));
    }
    if (/table_name = 'notifications'[\s\S]*column_name = 'data'/.test(sql)) {
      return [{ exists: db.catalog.columns.includes('notifications.data') }];
    }
    if (/overdue_notified_at'\s*\)\s*AS exists/.test(sql)) return [{ exists: true }];
    if (/cycle_index_valid/.test(sql)) {
      return [
        {
          cycle_index_valid: db.catalog.unique_indexes.includes('invoices_cycle_tenancy_period_start_uniq'),
          legacy_index_exists: db.catalog.unique_indexes.includes('invoices_tenancy_period_start_uniq'),
        },
      ];
    }
    return [];
  };
  return {
    query: vi.fn(async (sql: string) => run(sql, false)),
    withTransaction: vi.fn(async (fn: (q: any) => Promise<unknown>) => {
      db.txEvents.push('BEGIN');
      try {
        const out = await fn(async (sql: string) => run(sql, true));
        db.txEvents.push('COMMIT');
        return out;
      } catch (err) {
        db.txEvents.push('ROLLBACK');
        throw err;
      }
    }),
  };
});

vi.mock('@modules/subscriptions/subscription.service', () => {
  jobs.downgrade = vi.fn(async () => 0);
  return {
    SubscriptionService: class {
      downgradeExpiredSubscriptions = (...args: unknown[]) => jobs.downgrade(...args);
    },
  };
});

vi.mock('@modules/subscriptions/subscription-cron.service', () => {
  jobs.expiryWarning = vi.fn(async () => 0);
  return {
    SubscriptionCronService: class {
      sendSevenDayExpiryWarnings = (...args: unknown[]) => jobs.expiryWarning(...args);
    },
  };
});

const FULL_COLUMNS = [
  'notifications.data',
  'complaints.photo_urls',
  'complaints.ticket_number',
  'invoice_line_items.charge_kind',
  'tenancies.include_past_rent_arrears',
  'invoices.sent_at',
  'invoices.is_auto_generated',
  'invoices.overdue_notified_at',
  'invoices.invoice_kind',
  'invoices.approved_by',
];

function fullCatalog(): Catalog {
  return {
    columns: [...FULL_COLUMNS],
    tables: ['mess_menus', 'meter_readings', 'gate_passes'],
    charge_kind_type: true,
    complaint_assigned: true,
    unique_indexes: ['invoices_cycle_tenancy_period_start_uniq'],
  };
}

const OFF = {
  schemaAutoMigrate: false,
  legacyInvoiceIndexCleanup: false,
  billingScheduler: false,
  billingSchedulerRunOnBoot: false,
  subscriptionJobs: false,
  subscriptionJobsRunOnBoot: false,
};

const MUTATION = /\b(ALTER|CREATE|DROP|UPDATE|INSERT|DELETE|TRUNCATE)\b/i;
const mutations = () => db.log.filter((s) => MUTATION.test(s.sql));

async function load() {
  vi.resetModules();
  return import('./startup.js');
}

let warn: ReturnType<typeof vi.spyOn>;
beforeEach(() => {
  db.log = [];
  db.txEvents = [];
  db.catalog = fullCatalog();
  db.onSql = () => undefined;
  db.connectError = null;
  warn = vi.spyOn(console, 'warn').mockImplementation(() => undefined);
  vi.spyOn(console, 'log').mockImplementation(() => undefined);
  vi.spyOn(console, 'error').mockImplementation(() => undefined);
});

afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllEnvs();
  vi.restoreAllMocks();
});

describe('readRuntimeFlags', () => {
  it('every flag defaults to off', async () => {
    const { readRuntimeFlags } = await import('../../config/runtime-flags.js');
    expect(readRuntimeFlags({})).toEqual(OFF);
  });

  it('only "true" (any case) turns a flag on; other values warn and stay off', async () => {
    const { readRuntimeFlags } = await import('../../config/runtime-flags.js');
    const flags = readRuntimeFlags({
      DB_SCHEMA_AUTO_MIGRATE: 'TRUE',
      BILLING_SCHEDULER_ENABLED: 'true',
      SUBSCRIPTION_JOBS_ENABLED: '1',
      LEGACY_INVOICE_INDEX_CLEANUP: 'yes',
      BILLING_SCHEDULER_RUN_ON_BOOT: 'false',
    });
    expect(flags).toEqual({
      ...OFF,
      schemaAutoMigrate: true,
      billingScheduler: true,
    });
    expect(warn).toHaveBeenCalledTimes(2);
  });
});

describe('prepareDatabase with DB_SCHEMA_AUTO_MIGRATE off (default)', () => {
  it('starts when the schema is present, using only one read-only catalog query', async () => {
    const { prepareDatabase } = await load();
    const readiness = await prepareDatabase(OFF);
    expect(readiness.missing).toEqual([]);
    expect(db.log).toHaveLength(1);
    expect(mutations()).toEqual([]);
    expect(db.txEvents).toEqual([]);
  });

  it('also works on a 025-only schema (legacy index, no invoice_kind)', async () => {
    db.catalog.columns = db.catalog.columns.filter((c) => !/invoice_kind|approved_by/.test(c));
    db.catalog.unique_indexes = ['invoices_tenancy_period_start_uniq'];
    const { prepareDatabase } = await load();
    const readiness = await prepareDatabase(OFF);
    expect(readiness).toMatchObject({ missing: [], invoiceKind: false, legacyIndexPresent: true });
    expect(mutations()).toEqual([]);
  });

  it('fails fast with a safe diagnostic and changes nothing when schema is missing', async () => {
    vi.stubEnv('DATABASE_URL', 'postgres://dormly:s3cret-pass@db.example.internal:5432/prod');
    db.catalog.columns = db.catalog.columns.filter((c) => c !== 'invoices.sent_at');
    db.catalog.tables = ['mess_menus', 'meter_readings'];
    db.catalog.complaint_assigned = false;
    db.catalog.unique_indexes = [];
    const { prepareDatabase, SchemaNotReadyError, describeStartupError } = await load();

    const err = await prepareDatabase(OFF).catch((e: unknown) => e);
    expect(err).toBeInstanceOf(SchemaNotReadyError);
    const message = describeStartupError(err);
    expect(message).toContain('column invoices.sent_at (migration 025_invoice_review_workflow)');
    expect(message).toContain('table gate_passes (migration 018_gate_passes)');
    expect(message).toContain("enum value complaint_status 'assigned' (migration 017_live_ops_contracts)");
    expect(message).toContain('unique index on invoices (tenancy_id, period_start)');
    expect(message).toContain('DB_SCHEMA_AUTO_MIGRATE is off, so no schema change was attempted');
    expect(message).not.toMatch(/s3cret|db\.example|postgres:\/\//);
    expect(mutations()).toEqual([]);
    expect(db.txEvents).toEqual([]);
  });

  it('reports only the error class and code when the database is unreachable', async () => {
    db.connectError = Object.assign(
      new Error('connect ECONNREFUSED 10.1.2.3:5432 user=dormly password=hunter2'),
      { code: 'ECONNREFUSED' },
    );
    const { prepareDatabase, describeStartupError } = await load();
    const err = await prepareDatabase(OFF).catch((e: unknown) => e);
    const message = describeStartupError(err);
    expect(message).toBe(
      'Could not verify the database schema: Error (ECONNREFUSED). Check database connectivity.',
    );
  });

  it('request-path ensure helpers do not mutate either', async () => {
    vi.resetModules();
    const { ensureLiveOpsSchema } = await import('../../modules/notifications/notify.js');
    const { ensureNotificationsSchema } = await import(
      '../../modules/notifications/move-out-notifications.js'
    );
    const { ensureBillingSchema } = await import('../../modules/billing/billing.service.js');
    await ensureLiveOpsSchema();
    await ensureBillingSchema();
    expect(await ensureNotificationsSchema()).toBe(true);
    expect(mutations()).toEqual([]);
  });
});

describe('prepareDatabase with DB_SCHEMA_AUTO_MIGRATE=true (explicit opt-in)', () => {
  it('applies the idempotent schema changes, then verifies', async () => {
    vi.stubEnv('DB_SCHEMA_AUTO_MIGRATE', 'true');
    db.catalog.columns = db.catalog.columns.filter((c) => c !== 'notifications.data');
    db.catalog.tables = ['mess_menus', 'meter_readings'];
    db.onSql = (sql) => {
      if (/ALTER TABLE notifications[\s\S]*ADD COLUMN IF NOT EXISTS data/.test(sql)) {
        db.catalog.columns.push('notifications.data');
      }
      if (/CREATE TABLE IF NOT EXISTS gate_passes/.test(sql)) db.catalog.tables.push('gate_passes');
    };
    const { prepareDatabase } = await load();
    const readiness = await prepareDatabase({ ...OFF, schemaAutoMigrate: true });

    expect(readiness.missing).toEqual([]);
    const ddl = mutations().map((s) => s.sql);
    expect(ddl.some((s) => /ALTER TABLE notifications/.test(s))).toBe(true);
    expect(ddl.some((s) => /CREATE TABLE IF NOT EXISTS gate_passes/.test(s))).toBe(true);
    expect(ddl.some((s) => /ADD COLUMN IF NOT EXISTS sent_at/.test(s))).toBe(true);
    // Index cleanup stays behind its own flag.
    expect(ddl.some((s) => /DROP INDEX/.test(s))).toBe(false);
  });

  it('still fails fast when the changes could not be applied', async () => {
    vi.stubEnv('DB_SCHEMA_AUTO_MIGRATE', 'true');
    db.catalog.tables = ['mess_menus', 'meter_readings'];
    const { prepareDatabase, describeStartupError } = await load();
    const err = await prepareDatabase({ ...OFF, schemaAutoMigrate: true }).catch((e: unknown) => e);
    expect(describeStartupError(err)).toContain(
      'DB_SCHEMA_AUTO_MIGRATE=true could not create these objects',
    );
  });
});

describe('legacy invoice index cleanup (LEGACY_INVOICE_INDEX_CLEANUP)', () => {
  beforeEach(() => {
    db.catalog.unique_indexes = [
      'invoices_cycle_tenancy_period_start_uniq',
      'invoices_tenancy_period_start_uniq',
    ];
  });

  it('off (default): never drops or relabels, only warns', async () => {
    const { prepareDatabase } = await load();
    await prepareDatabase(OFF);
    expect(mutations()).toEqual([]);
    expect(db.txEvents).toEqual([]);
    expect(warn.mock.calls.flat().join(' ')).toMatch(/LEGACY_INVOICE_INDEX_CLEANUP=true/);
  });

  it('auto-migrate alone does not drop the index', async () => {
    vi.stubEnv('DB_SCHEMA_AUTO_MIGRATE', 'true');
    const { prepareDatabase } = await load();
    await prepareDatabase({ ...OFF, schemaAutoMigrate: true });
    expect(db.log.some((s) => /DROP INDEX|SET invoice_kind/.test(s.sql))).toBe(false);
  });

  it('on: relabels and drops in one transaction', async () => {
    const { prepareDatabase } = await load();
    await prepareDatabase({ ...OFF, legacyInvoiceIndexCleanup: true });
    expect(db.txEvents).toEqual(['BEGIN', 'COMMIT']);
    const tx = db.log.filter((s) => s.tx).map((s) => s.sql);
    expect(tx[0]).toMatch(/SET invoice_kind = 'adhoc'/);
    expect(tx[1]).toMatch(/DROP INDEX IF EXISTS invoices_tenancy_period_start_uniq/);
    expect(db.log.some((s) => /DELETE/i.test(s.sql))).toBe(false);
  });

  it('on but 026 not applied: ignored', async () => {
    db.catalog.columns = db.catalog.columns.filter((c) => !/invoice_kind|approved_by/.test(c));
    db.catalog.unique_indexes = ['invoices_tenancy_period_start_uniq'];
    const { prepareDatabase } = await load();
    await prepareDatabase({ ...OFF, legacyInvoiceIndexCleanup: true });
    expect(mutations()).toEqual([]);
    expect(db.txEvents).toEqual([]);
  });
});

describe('startBackgroundJobs', () => {
  const HOUR = 60 * 60 * 1000;
  let billingRun: ReturnType<typeof vi.fn>;
  let started: { timers: NodeJS.Timeout[] } | null = null;

  async function loadJobs() {
    const startup = await load();
    const { BillingService } = await import('../../modules/billing/billing.service.js');
    billingRun = vi.fn(async () => 0);
    vi.spyOn(BillingService.prototype, 'ensureAllHostelPgAnniversaryInvoices').mockImplementation(
      billingRun as never,
    );
    return startup;
  }

  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    started?.timers.forEach((t) => clearInterval(t));
    started = null;
  });

  it('with every flag off nothing is scheduled and nothing runs', async () => {
    const { startBackgroundJobs } = await loadJobs();
    started = startBackgroundJobs(OFF, {});
    expect(started).toEqual({ names: [], timers: [] });
    await vi.advanceTimersByTimeAsync(48 * HOUR);
    expect(billingRun).not.toHaveBeenCalled();
    expect(jobs.downgrade).not.toHaveBeenCalled();
    expect(jobs.expiryWarning).not.toHaveBeenCalled();
    expect(db.log).toEqual([]);
  });

  it('billing scheduler on: no run at boot, first run after one interval', async () => {
    const { startBackgroundJobs } = await loadJobs();
    started = startBackgroundJobs({ ...OFF, billingScheduler: true }, {});
    await vi.advanceTimersByTimeAsync(HOUR - 1);
    expect(billingRun).not.toHaveBeenCalled();
    await vi.advanceTimersByTimeAsync(1);
    expect(billingRun).toHaveBeenCalledTimes(1);
    expect(jobs.downgrade).not.toHaveBeenCalled();
  });

  it('billing run-on-boot is a separate opt-in', async () => {
    const { startBackgroundJobs } = await loadJobs();
    started = startBackgroundJobs(
      { ...OFF, billingScheduler: true, billingSchedulerRunOnBoot: true },
      {},
    );
    await vi.advanceTimersByTimeAsync(0);
    expect(billingRun).toHaveBeenCalledTimes(1);
  });

  it('run-on-boot without the scheduler flag does nothing', async () => {
    const { startBackgroundJobs } = await loadJobs();
    started = startBackgroundJobs(
      { ...OFF, billingSchedulerRunOnBoot: true, subscriptionJobsRunOnBoot: true },
      {},
    );
    await vi.advanceTimersByTimeAsync(48 * HOUR);
    expect(billingRun).not.toHaveBeenCalled();
    expect(jobs.downgrade).not.toHaveBeenCalled();
    expect(jobs.expiryWarning).not.toHaveBeenCalled();
  });

  it('warns when both the in-process scheduler and CRON_SECRET are configured', async () => {
    const { startBackgroundJobs } = await loadJobs();
    started = startBackgroundJobs({ ...OFF, billingScheduler: true }, { CRON_SECRET: 'x' });
    expect(warn.mock.calls.flat().join(' ')).toMatch(/two schedulers/);
  });

  it('subscription jobs on: hourly downgrade and daily warning, nothing at boot', async () => {
    jobs.downgrade.mockClear();
    jobs.expiryWarning.mockClear();
    const { startBackgroundJobs } = await loadJobs();
    started = startBackgroundJobs({ ...OFF, subscriptionJobs: true }, {});
    await vi.advanceTimersByTimeAsync(15_000);
    expect(jobs.downgrade).not.toHaveBeenCalled();
    expect(jobs.expiryWarning).not.toHaveBeenCalled();
    await vi.advanceTimersByTimeAsync(HOUR);
    expect(jobs.downgrade).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(23 * HOUR);
    expect(jobs.expiryWarning).toHaveBeenCalledTimes(1);
    expect(billingRun).not.toHaveBeenCalled();
  });

  it('subscription run-on-boot runs downgrade now and the warning after 15 s', async () => {
    jobs.downgrade.mockClear();
    jobs.expiryWarning.mockClear();
    const { startBackgroundJobs } = await loadJobs();
    started = startBackgroundJobs(
      { ...OFF, subscriptionJobs: true, subscriptionJobsRunOnBoot: true },
      {},
    );
    await vi.advanceTimersByTimeAsync(0);
    expect(jobs.downgrade).toHaveBeenCalledTimes(1);
    expect(jobs.expiryWarning).not.toHaveBeenCalled();
    await vi.advanceTimersByTimeAsync(15_000);
    expect(jobs.expiryWarning).toHaveBeenCalledTimes(1);
  });
});

describe('createApp', () => {
  it('has no startup side effects (no SQL, no timers)', async () => {
    vi.resetModules();
    const setIntervalSpy = vi.spyOn(globalThis, 'setInterval');
    const setTimeoutSpy = vi.spyOn(globalThis, 'setTimeout');
    const { createApp } = await import('../../app.js');
    const before = { i: setIntervalSpy.mock.calls.length, t: setTimeoutSpy.mock.calls.length };
    createApp();
    await new Promise((r) => setImmediate(r));
    expect(setIntervalSpy.mock.calls.length).toBe(before.i);
    expect(setTimeoutSpy.mock.calls.length).toBe(before.t);
    expect(db.log).toEqual([]);
  });
});
