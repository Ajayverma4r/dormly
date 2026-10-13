import { beforeEach, describe, expect, it, vi } from 'vitest';

type Stmt = { sql: string; params: unknown[]; tx: boolean };

const db = {
  log: [] as Stmt[],
  txEvents: [] as string[],
  tenancy: {
    move_in_at: '2026-08-31T18:30:00Z' as string | null, // 1 Sep 2026 IST
    timezone: 'Asia/Kolkata' as string | null,
  },
  billed: [] as { period_start: string; period_end: string }[],
};

function run(sql: string, params: unknown[] = [], tx = false): unknown[] {
  db.log.push({ sql, params, tx });
  if (/information_schema\.columns[\s\S]*invoice_kind/.test(sql)) {
    return [{ column_name: 'invoice_kind' }, { column_name: 'approved_by' }];
  }
  if (/SELECT t\.move_in_at, p\.timezone/.test(sql)) return [db.tenancy];
  if (/SELECT period_start::text AS period_start/.test(sql)) return db.billed;
  if (/^UPDATE tenancies SET/.test(sql.trim())) return [{ id: 'tenancy-1' }];
  if (/FROM tenancies t\s+JOIN users u/.test(sql)) return [{ id: 'tenancy-1' }];
  return [];
}

vi.mock('@config/db', () => ({
  query: vi.fn(async (sql: string, params?: unknown[]) => run(sql, params ?? [])),
  withTransaction: vi.fn(async (fn: (q: any) => Promise<unknown>) => {
    db.txEvents.push('BEGIN');
    try {
      const result = await fn(async (sql: string, params?: unknown[]) =>
        run(sql, params ?? [], true),
      );
      db.txEvents.push('COMMIT');
      return result;
    } catch (err) {
      db.txEvents.push('ROLLBACK');
      throw err;
    }
  }),
}));

vi.mock('@modules/notifications/move-out-notifications', () => ({
  ensureNotificationsSchema: vi.fn(async () => true),
  resolvePropertyOwnerIds: vi.fn(async () => []),
}));

vi.mock('@modules/notifications/notify', () => ({
  createNotification: vi.fn(async () => true),
  notifyPropertyOwners: vi.fn(async () => 0),
}));

const TENANCY = '22222222-2222-4222-8222-222222222222';
const SEP = { period_start: '2026-09-01', period_end: '2026-09-30' };

async function load() {
  vi.resetModules();
  const { TenancyService } = await import('./tenancy.service.js');
  const billing = await import('../billing/billing.service.js');
  return { service: new TenancyService(), billing };
}

const tenancyUpdates = () => db.log.filter((s) => /^UPDATE tenancies SET/.test(s.sql.trim()));

beforeEach(() => {
  db.log = [];
  db.txEvents = [];
  db.tenancy = { move_in_at: '2026-08-31T18:30:00Z', timezone: 'Asia/Kolkata' };
  db.billed = [];
});

describe('TenancyService.update move-in safeguard', () => {
  it('blocks 1 Sep → 10 Sep once a cycle invoice exists, with a clear message', async () => {
    db.billed = [SEP];
    const { service, billing } = await load();

    const err = await service
      .update(TENANCY, { moveInAt: '2026-09-09T18:30:00Z' })
      .catch((e: unknown) => e);

    expect(err).toBeInstanceOf(billing.MoveInDateLockedError);
    expect((err as Error).message).toBe(
      "The move-in date can't be changed to 10 Sep 2026: it would move the billing day from the 1st to the 10th of each month. Rent is already billed for 1 Sep 2026 – 30 Sep 2026, so the billing periods would overlap or leave days unbilled. Existing invoices and payments are kept as they are. Keep the current move-in date, or add a one-off charge for any adjustment.",
    );
    expect(db.txEvents).toEqual(['BEGIN', 'ROLLBACK']);
    expect(tenancyUpdates()).toHaveLength(0);
    expect(db.log.some((s) => /UPDATE invoices|DELETE FROM invoices|INSERT INTO invoices/.test(s.sql))).toBe(false);
  });

  it('blocks 10 Sep → 1 Sep once 10 Sep–9 Oct is billed', async () => {
    db.tenancy.move_in_at = '2026-09-09T18:30:00Z';
    db.billed = [{ period_start: '2026-09-10', period_end: '2026-10-09' }];
    const { service, billing } = await load();

    await expect(
      service.update(TENANCY, { moveInAt: '2026-08-31T18:30:00Z', fullName: 'Ravi K' }),
    ).rejects.toBeInstanceOf(billing.MoveInDateLockedError);
    // Nothing in the request is applied, including the unrelated name change.
    expect(tenancyUpdates()).toHaveLength(0);
  });

  it('checks under the tenancy row lock and only cycle invoices', async () => {
    db.billed = [SEP];
    const { service } = await load();

    await service.update(TENANCY, { moveInAt: '2026-09-09T18:30:00Z' }).catch(() => undefined);

    const lock = db.log.find((s) => /SELECT t\.move_in_at, p\.timezone/.test(s.sql))!;
    expect(lock.tx).toBe(true);
    expect(lock.sql).toMatch(/FOR UPDATE OF t/);
    const billedQuery = db.log.find((s) => /SELECT period_start::text/.test(s.sql))!;
    expect(billedQuery.tx).toBe(true);
    expect(billedQuery.sql).toMatch(/invoice_kind = 'cycle'/);
  });

  it('allows re-saving the same move-in day with other edits', async () => {
    db.billed = [SEP];
    const { service } = await load();

    // Same calendar day in IST, different time of day.
    await service.update(TENANCY, { moveInAt: '2026-09-01T10:00:00+05:30', fullName: 'Ravi K' });

    expect(db.txEvents).toEqual(['BEGIN', 'COMMIT']);
    const [update] = tenancyUpdates();
    expect(update.tx).toBe(true);
    expect(update.sql).toMatch(/full_name = \$1/);
    expect(update.sql).toMatch(/move_in_at = \$2/);
  });

  it('allows any move-in change while no cycle invoice exists', async () => {
    const { service } = await load();

    await service.update(TENANCY, { moveInAt: '2026-09-09T18:30:00Z' });

    expect(db.txEvents).toEqual(['BEGIN', 'COMMIT']);
    expect(tenancyUpdates()).toHaveLength(1);
  });

  it('allows an earlier date on the same billing day (1 Sep → 1 Aug)', async () => {
    db.billed = [SEP];
    const { service } = await load();

    await service.update(TENANCY, { moveInAt: '2026-07-31T18:30:00Z' });

    expect(db.txEvents).toEqual(['BEGIN', 'COMMIT']);
    expect(tenancyUpdates()).toHaveLength(1);
  });

  it('leaves unrelated edits on the existing path (no lock, no billing check)', async () => {
    db.billed = [SEP];
    const { service } = await load();

    await service.update(TENANCY, { fullName: 'Ravi K', monthlyRent: 6000, status: 'active' });

    expect(db.txEvents).toEqual([]);
    expect(db.log.some((s) => /move_in_at, p\.timezone|period_start::text/.test(s.sql))).toBe(false);
    const [update] = tenancyUpdates();
    expect(update.tx).toBe(false);
    expect(update.params).toEqual(['Ravi K', 6000, 'active', TENANCY]);
  });
});

describe('error handler', () => {
  it('returns 409 with the message and code', async () => {
    const { billing } = await load();
    const { errorHandler } = await import('../../shared/middleware/error-handler.js');
    const res: any = {
      status: vi.fn(() => res),
      json: vi.fn(() => res),
    };

    errorHandler(new billing.MoveInDateLockedError('blocked'), {} as any, res, vi.fn());

    expect(res.status).toHaveBeenCalledWith(409);
    expect(res.json).toHaveBeenCalledWith({ error: 'blocked', code: 'move_in_date_locked' });
  });
});
