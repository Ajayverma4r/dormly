import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

type Stmt = { sql: string; params: unknown[]; tx: boolean };

const db = {
  caps: { invoiceKind: true, approvedBy: true },
  log: [] as Stmt[],
  txEvents: [] as string[],
  owners: ['owner-1', 'owner-2'] as string[],
  handle: (_sql: string, _params: unknown[], _tx: boolean): unknown[] => [],
};

function capsRows() {
  const rows: { column_name: string }[] = [];
  if (db.caps.invoiceKind) rows.push({ column_name: 'invoice_kind' });
  if (db.caps.approvedBy) rows.push({ column_name: 'approved_by' });
  return rows;
}

function run(sql: string, params: unknown[] = [], tx = false) {
  db.log.push({ sql, params, tx });
  if (/information_schema\.columns[\s\S]*invoice_kind/.test(sql)) return capsRows();
  if (/overdue_notified_at'\s*\)\s*AS exists/.test(sql)) return [{ exists: true }];
  if (/SELECT timezone FROM properties/.test(sql)) return [{ timezone: 'Asia/Kolkata' }];
  return db.handle(sql, params, tx);
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
  resolvePropertyOwnerIds: vi.fn(async () => db.owners),
}));

vi.mock('@modules/notifications/notify', () => ({
  createNotification: vi.fn(async () => true),
  notifyPropertyOwners: vi.fn(async () => 0),
}));

const PROPERTY = '11111111-1111-4111-8111-111111111111';
const TENANCY = '22222222-2222-4222-8222-222222222222';
const INVOICE = '33333333-3333-4333-8333-333333333333';
const APPROVER = '44444444-4444-4444-8444-444444444444';
const TENANT_USER = '55555555-5555-4555-8555-555555555555';

async function loadService() {
  vi.resetModules();
  const mod = await import('./billing.service.js');
  const service = new mod.BillingService();
  vi.spyOn(service, 'getById').mockImplementation(
    async (id: unknown) => ({ id }) as any,
  );
  return { mod, service };
}

const txStmts = () => db.log.filter((s) => s.tx);
const notificationInserts = () =>
  txStmts().filter((s) => /INSERT INTO notifications/.test(s.sql));

beforeEach(() => {
  db.caps = { invoiceKind: true, approvedBy: true };
  db.log = [];
  db.txEvents = [];
  db.owners = ['owner-1', 'owner-2'];
  db.handle = () => [];
  vi.useFakeTimers();
  vi.setSystemTime(new Date('2026-10-12T06:00:00Z'));
});

afterEach(() => {
  vi.useRealTimers();
});

describe('sendInvoice (approval)', () => {
  const draftRow = {
    id: INVOICE,
    tenancy_id: TENANCY,
    sent_at: null,
    total_amount: '5000.00',
    paid: '0',
    user_id: TENANT_USER,
    period_start: '2026-09-01',
    period_end: '2026-09-30',
    due_date: '2026-10-06',
  };

  it('marks sent, records the authenticated approver and notifies the tenant in one transaction', async () => {
    db.handle = (sql) => (/FOR UPDATE OF i/.test(sql) ? [draftRow] : []);
    const { service } = await loadService();

    const result = await service.sendInvoice(INVOICE, PROPERTY, APPROVER);

    expect(result).toMatchObject({ id: INVOICE, newly_sent: true });
    expect(db.txEvents).toEqual(['BEGIN', 'COMMIT']);
    const update = txStmts().find((s) => /UPDATE invoices\s+SET sent_at/.test(s.sql))!;
    expect(update.sql).toMatch(/approved_by = \$4/);
    expect(update.sql).toMatch(/sent_at IS NULL/);
    expect(update.params).toEqual([INVOICE, PROPERTY, '2026-10-12', APPROVER]);
    const notes = notificationInserts();
    expect(notes).toHaveLength(1);
    expect(notes[0].params[0]).toBe(TENANT_USER);
    expect(notes[0].params[2]).toBe('invoice_sent');
  });

  it('rolls back (invoice stays a draft) when the tenant notification cannot be stored', async () => {
    db.handle = (sql) => {
      if (/FOR UPDATE OF i/.test(sql)) return [draftRow];
      if (/INSERT INTO notifications/.test(sql)) throw new Error('insert failed');
      return [];
    };
    const { service } = await loadService();

    await expect(service.sendInvoice(INVOICE, PROPERTY, APPROVER)).rejects.toThrow(
      'insert failed',
    );
    expect(db.txEvents).toEqual(['BEGIN', 'ROLLBACK']);
  });

  it('is idempotent: an already-sent invoice is not updated or re-notified', async () => {
    db.handle = (sql) =>
      /FOR UPDATE OF i/.test(sql) ? [{ ...draftRow, sent_at: new Date() }] : [];
    const { service } = await loadService();

    const result = await service.sendInvoice(INVOICE, PROPERTY, APPROVER);

    expect(result).toMatchObject({ newly_sent: false });
    expect(txStmts().some((s) => /UPDATE invoices/.test(s.sql))).toBe(false);
    expect(notificationInserts()).toHaveLength(0);
  });

  it('returns null for an invoice outside the property', async () => {
    const { service } = await loadService();
    expect(await service.sendInvoice(INVOICE, PROPERTY, APPROVER)).toBeNull();
    expect(notificationInserts()).toHaveLength(0);
  });

  it('refuses to send a zero-total draft', async () => {
    db.handle = (sql) =>
      /FOR UPDATE OF i/.test(sql) ? [{ ...draftRow, total_amount: '0' }] : [];
    const { service } = await loadService();
    await expect(service.sendInvoice(INVOICE, PROPERTY, APPROVER)).rejects.toThrow(
      /above 0/,
    );
    expect(db.txEvents).toEqual(['BEGIN', 'ROLLBACK']);
  });

  it('works before migration 026 (no approved_by column)', async () => {
    db.caps = { invoiceKind: false, approvedBy: false };
    db.handle = (sql) => (/FOR UPDATE OF i/.test(sql) ? [draftRow] : []);
    const { service } = await loadService();

    await service.sendInvoice(INVOICE, PROPERTY, APPROVER);

    const update = txStmts().find((s) => /UPDATE invoices\s+SET sent_at/.test(s.sql))!;
    expect(update.sql).not.toMatch(/approved_by/);
    expect(update.params).toEqual([INVOICE, PROPERTY, '2026-10-12']);
  });
});

describe('ensureHostelPgAnniversaryInvoices (draft generation)', () => {
  const tenancyRow = {
    id: TENANCY,
    full_name: 'Ravi',
    monthly_rent: '5000',
    move_in_at: '2026-08-31T18:30:00Z', // 1 Sep 2026 in Asia/Kolkata
    move_out_at: null,
    status: 'active',
  };

  type BilledFixture = { period_start: string; period_end: string }[];

  function generatorDb(
    opts: {
      insertReturns?: unknown[];
      notificationFails?: boolean;
      listed?: Record<string, unknown>;
      locked?: Record<string, unknown> | null;
      billedBefore?: BilledFixture;
      billedInTx?: BilledFixture;
    } = {},
  ) {
    db.handle = (sql, _params, tx) => {
      if (!tx && /FROM tenancies\s+WHERE property_id/.test(sql)) {
        return [opts.listed ?? tenancyRow];
      }
      if (tx && /FROM tenancies[\s\S]*FOR UPDATE/.test(sql)) {
        return opts.locked === null ? [] : [opts.locked ?? opts.listed ?? tenancyRow];
      }
      if (/SELECT period_start::text AS period_start/.test(sql)) {
        return tx ? (opts.billedInTx ?? opts.billedBefore ?? []) : (opts.billedBefore ?? []);
      }
      if (/FROM charge_types/.test(sql)) return [{ id: 'ct-rent', name: 'Rent' }];
      if (tx && /INSERT INTO invoices/.test(sql)) return opts.insertReturns ?? [{ id: INVOICE }];
      if (tx && /SELECT id, tenancy_id, property_id FROM invoices/.test(sql)) {
        return [{ id: INVOICE, tenancy_id: TENANCY, property_id: PROPERTY }];
      }
      if (tx && /INSERT INTO notifications/.test(sql) && opts.notificationFails) {
        throw new Error('notification insert failed');
      }
      return [];
    };
  }

  it('creates the Sep cycle draft, its rent line and owner notifications in one transaction', async () => {
    generatorDb();
    const { service } = await loadService();

    const created = await service.ensureHostelPgAnniversaryInvoices(PROPERTY);

    expect(created).toBe(1);
    expect(db.txEvents).toEqual(['BEGIN', 'COMMIT']);
    const billedLookups = db.log.filter((s) => /SELECT period_start::text/.test(s.sql));
    expect(billedLookups.every((s) => /invoice_kind = 'cycle'/.test(s.sql))).toBe(true);
    const insert = txStmts().find((s) => /INSERT INTO invoices/.test(s.sql))!;
    expect(insert.sql).toMatch(/invoice_kind/);
    expect(insert.sql).toMatch(/ON CONFLICT DO NOTHING/);
    expect(insert.sql).toMatch(/sent_at, is_auto_generated/);
    expect(insert.params).toEqual([
      TENANCY,
      PROPERTY,
      '2026-09-01',
      '2026-09-30',
      '2026-10-06',
      5000,
    ]);
    expect(txStmts().some((s) => /INSERT INTO invoice_line_items/.test(s.sql))).toBe(true);
    const notes = notificationInserts();
    expect(notes.map((n) => n.params[0])).toEqual(['owner-1', 'owner-2']);
    expect(notes.every((n) => n.params[2] === 'invoice_draft_ready')).toBe(true);
  });

  it('does not notify when a concurrent run already inserted the cycle (retry-safe)', async () => {
    generatorDb({ insertReturns: [] });
    const { service } = await loadService();

    const created = await service.ensureHostelPgAnniversaryInvoices(PROPERTY);

    expect(created).toBe(0);
    expect(notificationInserts()).toHaveLength(0);
    expect(txStmts().some((s) => /INSERT INTO invoice_line_items/.test(s.sql))).toBe(false);
  });

  it('rolls back the whole batch when owner notification fails, so the next run retries', async () => {
    generatorDb({ notificationFails: true });
    const { service } = await loadService();

    const created = await service.ensureHostelPgAnniversaryInvoices(PROPERTY);

    expect(created).toBe(0);
    expect(db.txEvents).toEqual(['BEGIN', 'ROLLBACK']);
  });

  it('defers drafts when no owner recipient can be resolved', async () => {
    generatorDb();
    db.owners = [];
    const { service } = await loadService();

    const created = await service.ensureHostelPgAnniversaryInvoices(PROPERTY);

    expect(created).toBe(0);
    expect(db.txEvents).toEqual([]);
  });

  it('before migration 026, inserts without invoice_kind and checks all invoices', async () => {
    db.caps = { invoiceKind: false, approvedBy: false };
    generatorDb();
    const { service } = await loadService();

    await service.ensureHostelPgAnniversaryInvoices(PROPERTY);

    const existingLookup = db.log.find((s) => /SELECT period_start::text/.test(s.sql))!;
    expect(existingLookup.sql).not.toMatch(/invoice_kind/);
    expect(existingLookup.sql).toMatch(/NOT \(NOT is_auto_generated AND period_start = period_end\)/);
    const insert = txStmts().find((s) => /INSERT INTO invoices/.test(s.sql))!;
    expect(insert.sql).not.toMatch(/invoice_kind/);
  });

  it('only lists active tenancies (pending and ended are never billed)', async () => {
    generatorDb();
    const { service } = await loadService();

    await service.ensureHostelPgAnniversaryInvoices(PROPERTY);

    const list = db.log.find((s) => /FROM tenancies\s+WHERE property_id/.test(s.sql))!;
    expect(list.sql).toMatch(/status = 'active'/);
  });

  it('skips a pending tenancy even if it reaches the planner', async () => {
    generatorDb({ listed: { ...tenancyRow, status: 'pending' } });
    const { service } = await loadService();

    expect(await service.ensureHostelPgAnniversaryInvoices(PROPERTY)).toBe(0);
    expect(db.txEvents).toEqual([]);
  });

  it('re-checks status under the row lock: a tenancy ended mid-run gets no draft', async () => {
    generatorDb({ locked: { ...tenancyRow, status: 'ended' } });
    const { service } = await loadService();

    expect(await service.ensureHostelPgAnniversaryInvoices(PROPERTY)).toBe(0);
    expect(txStmts().some((s) => /INSERT INTO/.test(s.sql))).toBe(false);
    expect(db.txEvents).toEqual(['BEGIN', 'COMMIT']);
  });

  it('a draft past its due date is still created as pending, never overdue', async () => {
    // Today is 12 Oct; the Sep cycle was due 6 Oct.
    generatorDb();
    const { service } = await loadService();

    await service.ensureHostelPgAnniversaryInvoices(PROPERTY);

    const insert = txStmts().find((s) => /INSERT INTO invoices/.test(s.sql))!;
    expect(insert.sql).toMatch(/'pending'::invoice_status/);
    expect(insert.sql).not.toMatch(/overdue/);
  });

  it('snapshots the rent read under the lock into the line item and total', async () => {
    generatorDb({ locked: { ...tenancyRow, monthly_rent: '6500.5' } });
    const { service } = await loadService();

    await service.ensureHostelPgAnniversaryInvoices(PROPERTY);

    const insert = txStmts().find((s) => /INSERT INTO invoices/.test(s.sql))!;
    expect(insert.params[5]).toBe(6500.5);
    const line = txStmts().find((s) => /INSERT INTO invoice_line_items/.test(s.sql))!;
    expect(line.params).toEqual([INVOICE, 'ct-rent', 'Sep 2026 Rent', 6500.5]);
  });

  it('never updates or deletes existing invoices when the rent later changes', async () => {
    generatorDb({
      listed: { ...tenancyRow, monthly_rent: '9000' },
      billedBefore: [{ period_start: '2026-09-01', period_end: '2026-09-30' }],
    });
    const { service } = await loadService();

    expect(await service.ensureHostelPgAnniversaryInvoices(PROPERTY)).toBe(0);
    expect(db.log.some((s) => /UPDATE invoices|DELETE FROM invoices/.test(s.sql))).toBe(false);
    expect(db.txEvents).toEqual([]);
  });

  it('a second scheduler run that lost the race plans nothing under the lock', async () => {
    // The pre-check saw no invoice; by the time the lock is held, the first
    // run has committed the September cycle.
    generatorDb({
      billedBefore: [],
      billedInTx: [{ period_start: '2026-09-01', period_end: '2026-09-30' }],
    });
    const { service } = await loadService();

    expect(await service.ensureHostelPgAnniversaryInvoices(PROPERTY)).toBe(0);
    expect(txStmts().some((s) => /INSERT INTO/.test(s.sql))).toBe(false);
    expect(notificationInserts()).toHaveLength(0);
  });

  it('after a move-in edit (1 Sep → 10 Sep) it resumes after the billed period without overlap', async () => {
    vi.setSystemTime(new Date('2026-11-10T06:00:00Z'));
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => undefined);
    generatorDb({
      listed: { ...tenancyRow, move_in_at: '2026-09-09T18:30:00Z' }, // 10 Sep IST
      billedBefore: [{ period_start: '2026-09-01', period_end: '2026-09-30' }],
    });
    const { service } = await loadService();

    expect(await service.ensureHostelPgAnniversaryInvoices(PROPERTY)).toBe(1);

    const inserts = txStmts().filter((s) => /INSERT INTO invoices/.test(s.sql));
    expect(inserts.map((s) => s.params.slice(2, 5))).toEqual([
      ['2026-10-10', '2026-11-09', '2026-11-15'],
    ]);
    expect(
      warn.mock.calls.some((c) => String(c[0]).includes('2026-10-01..2026-10-09')),
    ).toBe(true);
    warn.mockRestore();
  });

  it('refreshes statuses so only sent invoices can become overdue', async () => {
    const { service } = await loadService();

    await service.refreshHostelInvoiceStatuses(PROPERTY);

    const refresh = db.log.find((s) => /UPDATE invoices i\s+SET status/.test(s.sql))!;
    expect(refresh.sql).toMatch(/WHEN i2\.sent_at IS NOT NULL AND i2\.due_date < \$2::date THEN 'overdue'/);
  });
});

describe('recordPayment', () => {
  it('rejects a payment on a draft and writes nothing', async () => {
    db.handle = (sql, _params, tx) =>
      tx && /SELECT total_amount, sent_at FROM invoices/.test(sql)
        ? [{ total_amount: '5000.00', sent_at: null }]
        : [];
    const { service } = await loadService();

    await expect(
      service.recordPayment(INVOICE, PROPERTY, 1000, 'cash', undefined, APPROVER),
    ).rejects.toThrow(/still a draft/);
    expect(db.txEvents).toEqual(['BEGIN', 'ROLLBACK']);
    expect(db.log.some((s) => /INSERT INTO payments/.test(s.sql))).toBe(false);
  });

  it('still records a payment on a sent invoice', async () => {
    db.handle = (sql, _params, tx) => {
      if (tx && /SELECT total_amount, sent_at FROM invoices/.test(sql)) {
        return [{ total_amount: '5000.00', sent_at: new Date() }];
      }
      if (tx && /SUM\(amount\)/.test(sql)) return [{ paid: '0' }];
      return [];
    };
    const { service } = await loadService();

    await service.recordPayment(INVOICE, PROPERTY, 1000, 'cash', undefined, APPROVER);

    expect(db.txEvents).toEqual(['BEGIN', 'COMMIT']);
    const pay = txStmts().find((s) => /INSERT INTO payments/.test(s.sql))!;
    expect(pay.params).toEqual([INVOICE, 1000, 'cash', null, APPROVER]);
  });
});

describe('createInvoice (manual / ad hoc)', () => {
  function createDb(opts: { notificationFails?: boolean } = {}) {
    db.handle = (sql, _params, tx) => {
      if (!tx && /SELECT id FROM tenancies WHERE id = \$1 AND property_id = \$2/.test(sql)) {
        return [{ id: TENANCY }];
      }
      if (tx && /INSERT INTO invoices/.test(sql)) return [{ id: INVOICE }];
      if (tx && /SELECT i\.total_amount::text/.test(sql)) {
        return [{
          total_amount: '750.00',
          line_count: '1',
          user_id: TENANT_USER,
          period_start: '2026-10-12',
          period_end: '2026-10-12',
          due_date: '2026-10-19',
        }];
      }
      if (tx && /INSERT INTO notifications/.test(sql) && opts.notificationFails) {
        throw new Error('notification insert failed');
      }
      return [];
    };
  }

  const adhocInput = {
    tenancyId: TENANCY,
    propertyId: PROPERTY,
    periodStart: '2026-10-12',
    periodEnd: '2026-10-12',
    dueDate: '2026-10-19',
    lineItems: [{ description: 'Key replacement', amount: 750 }],
    includeArrears: false,
    includePendingCharges: false,
    invoiceKind: 'adhoc' as const,
    approvedBy: APPROVER,
  };

  it('stores an ad hoc invoice with approver and tenant notification atomically, without the cycle duplicate check', async () => {
    createDb();
    const { service } = await loadService();

    await service.createInvoice(adhocInput);

    expect(db.log.some((s) => /SELECT id, sent_at FROM invoices/.test(s.sql))).toBe(false);
    const insert = txStmts().find((s) => /INSERT INTO invoices/.test(s.sql))!;
    expect(insert.sql).toMatch(/invoice_kind, approved_by/);
    expect(insert.params.slice(-2)).toEqual(['adhoc', APPROVER]);
    expect(notificationInserts()).toHaveLength(1);
    expect(db.txEvents).toEqual(['BEGIN', 'COMMIT']);
  });

  it('leaves no invoice behind when the tenant notification fails', async () => {
    createDb({ notificationFails: true });
    const { service } = await loadService();

    await expect(service.createInvoice(adhocInput)).rejects.toThrow(
      'notification insert failed',
    );
    expect(db.txEvents).toEqual(['BEGIN', 'ROLLBACK']);
  });

  it('treats a one-day manual invoice without invoiceKind as adhoc (current Add Charge)', async () => {
    createDb();
    const { service } = await loadService();
    const { invoiceKind: _omit, ...legacyInput } = adhocInput;

    await service.createInvoice(legacyInput);

    const insert = txStmts().find((s) => /INSERT INTO invoices/.test(s.sql))!;
    expect(insert.params.slice(-2)).toEqual(['adhoc', APPROVER]);
  });

  it('treats a multi-day manual invoice without invoiceKind as cycle', async () => {
    createDb();
    const { service } = await loadService();
    const { invoiceKind: _omit, ...legacyInput } = adhocInput;

    await service.createInvoice({ ...legacyInput, periodStart: '2026-09-01', periodEnd: '2026-09-30' });

    const insert = txStmts().find((s) => /INSERT INTO invoices/.test(s.sql))!;
    expect(insert.params.slice(-2)).toEqual(['cycle', APPROVER]);
  });

  it('cycle invoices still run the duplicate check, limited to cycle rows', async () => {
    createDb();
    const { service } = await loadService();

    await service.createInvoice({ ...adhocInput, invoiceKind: 'cycle' });

    const dup = db.log.find((s) => /SELECT id, sent_at FROM invoices/.test(s.sql))!;
    expect(dup.sql).toMatch(/invoice_kind = 'cycle'/);
  });

  describe('NUMERIC(12,2) total with rent and pending meter charges', () => {
    const rentInput = (rent: number, extra: { description: string; amount: number }[] = []) => ({
      ...adhocInput,
      periodStart: '2026-09-01',
      periodEnd: '2026-09-30',
      invoiceKind: 'cycle' as const,
      lineItems: [{ description: 'Sep 2026 Rent', amount: rent }, ...extra],
      includePendingCharges: true,
    });

    /** Inserted invoice total is the rent; pending readings come from meter_readings. */
    function pendingDb(pendingAmounts: string[]) {
      let insertedTotal = '0';
      db.handle = (sql, params, tx) => {
        if (!tx && /SELECT id FROM tenancies WHERE id = \$1 AND property_id = \$2/.test(sql)) {
          return [{ id: TENANCY }];
        }
        if (tx && /INSERT INTO invoices/.test(sql)) {
          insertedTotal = String(params[5]);
          return [{ id: INVOICE }];
        }
        if (tx && /SELECT id, tenancy_id, property_id FROM invoices/.test(sql)) {
          return [{ id: INVOICE, tenancy_id: TENANCY, property_id: PROPERTY }];
        }
        if (tx && /FROM meter_readings mr/.test(sql)) {
          return pendingAmounts.map((amount, i) => ({
            id: `mr-${i}`,
            amount,
            billing_cycle: '2026-09',
            units_consumed: '1',
            rate_per_unit: amount,
          }));
        }
        if (tx && /SELECT total_amount::text AS total_amount FROM invoices/.test(sql)) {
          return [{ total_amount: insertedTotal }];
        }
        if (tx && /INSERT INTO invoice_line_items[\s\S]*RETURNING id/.test(sql)) return [{ id: 'li-m' }];
        if (tx && /SELECT i\.total_amount::text/.test(sql)) {
          return [{
            total_amount: '1',
            line_count: '2',
            user_id: TENANT_USER,
            period_start: '2026-09-01',
            period_end: '2026-09-30',
            due_date: '2026-10-06',
          }];
        }
        return [];
      };
    }
    const meterWrites = () =>
      txStmts().filter((s) => /UPDATE meter_readings|UPDATE invoices|INSERT INTO notifications/.test(s.sql));

    it('rent plus pending charges exactly at the limit is created', async () => {
      pendingDb(['0.99', '1.00']);
      const { service } = await loadService();

      await service.createInvoice(rentInput(9_999_999_998.00));

      expect(db.txEvents).toEqual(['BEGIN', 'COMMIT']);
      const total = txStmts().find((s) => /UPDATE invoices\s+SET total_amount = total_amount \+ \$1/.test(s.sql))!;
      expect(total.params).toEqual([1.99, INVOICE]);
    });

    it('rent plus pending charges one paisa above the limit leaves no invoice, line or link', async () => {
      pendingDb(['1.00', '1.00']);
      const { service, mod } = await loadService();

      const err = await service.createInvoice(rentInput(9_999_999_998.00)).catch((e) => e);

      expect(err).toBeInstanceOf(mod.InvoiceAmountRangeError);
      expect(err.code).toBe('invoice_total_out_of_range');
      expect(db.txEvents).toEqual(['BEGIN', 'ROLLBACK']);
      expect(meterWrites()).toEqual([]);
    });

    it('line items over the limit are refused before the transaction', async () => {
      pendingDb([]);
      const { service } = await loadService();

      const err = await service
        .createInvoice(rentInput(9_999_999_999.99, [{ description: 'Maintenance', amount: 0.01 }]))
        .catch((e) => e);

      expect(err.code).toBe('invoice_total_out_of_range');
      expect(db.txEvents).toEqual([]);
      expect(db.log.some((s) => /INSERT INTO/.test(s.sql))).toBe(false);
    });
  });
});

describe('ensureBillingSchema', () => {
  const createsLegacy = () =>
    db.log.some((s) =>
      /CREATE UNIQUE INDEX IF NOT EXISTS invoices_tenancy_period_start_uniq/.test(s.sql),
    );
  const mutations = () =>
    db.log.filter((s) => /\b(ALTER|CREATE|DROP|UPDATE|INSERT|DELETE)\b/i.test(s.sql));

  afterEach(() => {
    vi.unstubAllEnvs();
  });

  it('issues no SQL at all while DB_SCHEMA_AUTO_MIGRATE is off (default)', async () => {
    db.caps = { invoiceKind: false, approvedBy: false };
    const { mod } = await loadService();
    await mod.ensureBillingSchema();
    expect(db.log).toEqual([]);
  });

  it('treats any value other than "true" as off', async () => {
    vi.stubEnv('DB_SCHEMA_AUTO_MIGRATE', 'yes');
    vi.spyOn(console, 'warn').mockImplementation(() => undefined);
    const { mod } = await loadService();
    await mod.ensureBillingSchema();
    expect(mutations()).toEqual([]);
  });

  it('with auto-migrate on, creates the legacy index only before 026', async () => {
    vi.stubEnv('DB_SCHEMA_AUTO_MIGRATE', 'true');
    db.caps = { invoiceKind: false, approvedBy: false };
    const { mod } = await loadService();
    await mod.ensureBillingSchema();
    expect(createsLegacy()).toBe(true);
    expect(db.txEvents).toEqual([]);
  });

  it('with auto-migrate on after 026, never recreates, relabels or drops anything index-related', async () => {
    vi.stubEnv('DB_SCHEMA_AUTO_MIGRATE', 'true');
    const { mod } = await loadService();
    await mod.ensureBillingSchema();
    expect(createsLegacy()).toBe(false);
    expect(db.log.some((s) => /DROP INDEX|SET invoice_kind/.test(s.sql))).toBe(false);
    expect(db.txEvents).toEqual([]);
  });
});

describe('retireLegacyInvoiceIndex (explicit, LEGACY_INVOICE_INDEX_CLEANUP)', () => {
  const indexState = (cycleValid: boolean, legacyExists: boolean) => {
    db.handle = (sql) =>
      /cycle_index_valid/.test(sql)
        ? [{ cycle_index_valid: cycleValid, legacy_index_exists: legacyExists }]
        : [];
  };
  const caps = { invoiceKind: true, approvedBy: true };

  it('relabels old-build one-day charges and drops the legacy index in one transaction', async () => {
    indexState(true, true);
    const { mod } = await loadService();
    await mod.retireLegacyInvoiceIndex(caps);

    expect(db.txEvents).toEqual(['BEGIN', 'COMMIT']);
    const [relabel, drop] = txStmts();
    expect(relabel.sql).toMatch(/SET invoice_kind = 'adhoc'/);
    expect(relabel.sql).toMatch(/NOT is_auto_generated/);
    expect(relabel.sql).toMatch(/period_start = period_end/);
    expect(relabel.sql).toMatch(/approved_by IS NULL/);
    expect(drop.sql).toMatch(/DROP INDEX IF EXISTS invoices_tenancy_period_start_uniq/);
    expect(db.log.some((s) => /DELETE/i.test(s.sql))).toBe(false);
  });

  it('keeps the legacy index when the cycle-only index is not valid', async () => {
    indexState(false, true);
    const { mod } = await loadService();
    await mod.retireLegacyInvoiceIndex(caps);

    expect(db.txEvents).toEqual([]);
    expect(db.log.some((s) => /DROP INDEX|SET invoice_kind/.test(s.sql))).toBe(false);
  });

  it('only relabels (no drop) once the legacy index is already gone', async () => {
    indexState(true, false);
    const { mod } = await loadService();
    await mod.retireLegacyInvoiceIndex(caps);

    expect(txStmts().some((s) => /DROP INDEX/.test(s.sql))).toBe(false);
    expect(txStmts().some((s) => /SET invoice_kind = 'adhoc'/.test(s.sql))).toBe(true);
  });
});

describe('invoiceFormCycle (Add Utilities period, property calendar)', () => {
  const tenancyRow = { move_in_at: '2026-08-31T18:30:00Z', move_out_at: null }; // 1 Sep IST

  it('suggests the oldest unbilled stay with a late due date, scoped to the property', async () => {
    db.handle = (sql) => {
      if (/FROM tenancies WHERE id = \$1 AND property_id = \$2/.test(sql)) return [tenancyRow];
      return [];
    };
    const { service } = await loadService();
    const r = await service.invoiceFormCycle(PROPERTY, TENANCY);

    expect(r.today).toBe('2026-10-12');
    expect(r.draft).toBeNull();
    expect(r.cycle).toMatchObject({
      periodStart: '2026-09-01',
      periodEnd: '2026-09-30',
      standardDueDate: '2026-10-06',
      dueDate: '2026-10-17',
      isLate: true,
    });
    const lookup = db.log.find((s) => /FROM tenancies WHERE id/.test(s.sql))!;
    expect(lookup.params).toEqual([TENANCY, PROPERTY]);
    expect(db.log.some((s) => /\b(INSERT|UPDATE|DELETE)\b/.test(s.sql))).toBe(false);
  });

  it('moves on to the running stay once Sep is billed, and surfaces an unsent draft', async () => {
    db.handle = (sql) => {
      if (/FROM tenancies WHERE id = \$1 AND property_id = \$2/.test(sql)) return [tenancyRow];
      if (/sent_at IS NULL[\s\S]*ORDER BY period_start/.test(sql)) {
        return [{ id: INVOICE, period_start: '2026-09-01', period_end: '2026-09-30' }];
      }
      if (/SELECT period_start::text AS period_start, period_end::text AS period_end/.test(sql)) {
        return [{ period_start: '2026-09-01', period_end: '2026-09-30' }];
      }
      return [];
    };
    const { service } = await loadService();
    const r = await service.invoiceFormCycle(PROPERTY, TENANCY);

    expect(r.cycle).toMatchObject({
      periodStart: '2026-10-01',
      periodEnd: '2026-10-31',
      dueDate: '2026-11-06',
      isLate: false,
      unbilled: [],
    });
    expect(r.draft).toEqual({ id: INVOICE, periodStart: '2026-09-01', periodEnd: '2026-09-30' });
    const draftSql = db.log.find((s) => /sent_at IS NULL/.test(s.sql))!.sql;
    expect(draftSql).toMatch(/invoice_kind = 'cycle'/);
  });

  it('no move-in date: no cycle', async () => {
    db.handle = (sql) =>
      /FROM tenancies WHERE id/.test(sql) ? [{ move_in_at: null, move_out_at: null }] : [];
    const { service } = await loadService();
    expect((await service.invoiceFormCycle(PROPERTY, TENANCY)).cycle).toBeNull();
  });

  it('a tenancy from another property is rejected', async () => {
    const { service } = await loadService();
    await expect(service.invoiceFormCycle(PROPERTY, TENANCY)).rejects.toThrow(
      'Tenant not found for this property.',
    );
  });
});
