import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

type Stmt = { sql: string; params: unknown[]; tx: boolean };

type InvoiceRow = {
  id: string;
  tenancy_id: string;
  property_id: string;
  /** Unit of the invoice's tenancy (tenancies.node_id). */
  node_id: string;
  sent_at: Date | null;
  invoice_kind: 'cycle' | 'adhoc';
  period_start: string;
  period_end: string;
};

const db = {
  log: [] as Stmt[],
  txEvents: [] as string[],
  invoices: [] as InvoiceRow[],
  failReadingInsert: false,
  targetOk: true,
};

const PROPERTY = '11111111-1111-4111-8111-111111111111';
const TENANCY = '22222222-2222-4222-8222-222222222222';
const OTHER_TENANCY = '88888888-8888-4888-8888-888888888888';
const INVOICE = '33333333-3333-4333-8333-333333333333';
const UNIT = '44444444-4444-4444-8444-444444444444';
const OTHER_UNIT = '99999999-9999-4999-8999-999999999999';

function addDays(ymd: string, n: number): string {
  const d = new Date(`${ymd}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

const CLOSING_DRAFT = /FROM invoices i\s+JOIN tenancies t[\s\S]*sent_at IS NULL[\s\S]*FOR UPDATE OF i/;

function run(sql: string, params: unknown[] = [], tx = false): unknown[] {
  db.log.push({ sql, params, tx });
  if (/information_schema\.columns[\s\S]*invoice_kind/.test(sql)) {
    return [{ column_name: 'invoice_kind' }, { column_name: 'approved_by' }];
  }
  if (/overdue_notified_at'\s*\)\s*AS exists/.test(sql)) return [{ exists: true }];
  if (/cycle_index_valid/.test(sql)) return [{ cycle_index_valid: true, legacy_index_exists: false }];
  if (/SELECT timezone FROM properties/.test(sql)) return [{ timezone: 'Asia/Kolkata' }];
  if (/AS unit_ok/.test(sql)) return [{ unit_ok: db.targetOk, tenancy_ok: db.targetOk }];
  if (/SELECT meter_reading_value FROM meter_readings/.test(sql)) {
    return [{ meter_reading_value: '100' }];
  }
  if (/FROM charge_types/.test(sql)) return [{ id: 'ct-el', name: 'Electricity', default_amount: '8' }];
  if (tx && CLOSING_DRAFT.test(sql)) {
    // Mirrors the WHERE clause of closingDraftSql (asserted separately).
    const [tenancyId, propertyId, unitId, date, windowDays] = params as [
      string, string, string, string, number,
    ];
    return db.invoices
      .filter(
        (i) =>
          i.tenancy_id === tenancyId &&
          i.property_id === propertyId &&
          i.node_id === unitId &&
          i.sent_at === null &&
          i.invoice_kind === 'cycle' &&
          date > i.period_end &&
          date <= addDays(i.period_end, windowDays),
      )
      .sort((a, b) => b.period_start.localeCompare(a.period_start))
      .slice(0, 1)
      .map((i) => ({ id: i.id }));
  }
  if (tx && /INSERT INTO invoice_line_items/.test(sql)) return [{ id: 'li-1' }];
  if (tx && /INSERT INTO meter_readings/.test(sql)) {
    if (db.failReadingInsert) throw new Error('insert failed');
    return [{ id: 'mr-1' }];
  }
  if (/SELECT name FROM hierarchy_nodes/.test(sql)) return [{ name: 'G01' }];
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
  ensureLiveOpsSchema: vi.fn(async () => undefined),
}));

const input = {
  propertyId: PROPERTY,
  unitId: UNIT,
  tenancyId: TENANCY,
  readingValue: 150,
  // The app sends the calendar month; it no longer decides the invoice.
  billingCycle: '2026-10',
  submittedBy: '66666666-6666-4666-8666-666666666666',
  ratePerUnit: 8,
};

/** Anniversary-cycle draft: move-in on the 12th, so 12 Sep – 11 Oct. */
const anniversaryDraft = (over: Partial<InvoiceRow> = {}): InvoiceRow => ({
  id: INVOICE,
  tenancy_id: TENANCY,
  property_id: PROPERTY,
  node_id: UNIT,
  sent_at: null,
  invoice_kind: 'cycle',
  period_start: '2026-09-12',
  period_end: '2026-10-11',
  ...over,
});

/** Sets "now" to a wall-clock time in Asia/Kolkata (UTC+5:30). */
function nowInKolkata(local: string) {
  vi.setSystemTime(new Date(`${local}+05:30`));
}

async function load() {
  vi.resetModules();
  const { MeterReadingsService } = await import('./meter-readings.service.js');
  const { ensureBillingSchema } = await import('../billing/billing.service.js');
  // Boot-time schema work (including its own transaction) is not under test.
  await ensureBillingSchema();
  db.log = [];
  db.txEvents = [];
  return new MeterReadingsService();
}

const readingInsert = () => db.log.find((s) => /INSERT INTO meter_readings/.test(s.sql))!;
const attachedTo = () => readingInsert().params.slice(-2);

beforeEach(() => {
  vi.clearAllMocks();
  vi.useFakeTimers({ toFake: ['Date'] });
  nowInKolkata('2026-10-14T10:00:00');
  db.log = [];
  db.txEvents = [];
  db.invoices = [];
  db.failReadingInsert = false;
  db.targetOk = true;
});

afterEach(() => {
  vi.useRealTimers();
});

describe('meter reading submit', () => {
  it('looks up the closing draft by anniversary period, tenancy and unit, under a row lock', async () => {
    const service = await load();
    await service.submit(input);

    const lookup = db.log.find((s) => CLOSING_DRAFT.test(s.sql))!;
    expect(lookup.tx).toBe(true);
    expect(lookup.sql).toMatch(/i\.tenancy_id = \$1/);
    expect(lookup.sql).toMatch(/i\.property_id = \$2/);
    expect(lookup.sql).toMatch(/t\.node_id = \$3/);
    expect(lookup.sql).toMatch(/i\.invoice_kind = 'cycle'/);
    expect(lookup.sql).toMatch(/\$4::date > i\.period_end/);
    expect(lookup.sql).toMatch(/\$4::date <= i\.period_end \+ \$5::int/);
    // Reading date is the property's local date; window = bill date .. default due date.
    expect(lookup.params).toEqual([TENANCY, PROPERTY, UNIT, '2026-10-14', 6]);
    // No calendar-month bounds any more.
    expect(lookup.params).not.toContain('2026-10-01');
  });

  it('attaches a reading taken after the period closes to that anniversary draft', async () => {
    db.invoices = [anniversaryDraft()];
    const service = await load();

    await service.submit(input);

    expect(db.txEvents).toEqual(['BEGIN', 'COMMIT']);
    const tx = db.log.filter((s) => s.tx).map((s) => s.sql);
    expect(tx.some((s) => /INSERT INTO invoice_line_items/.test(s))).toBe(true);
    expect(tx.some((s) => /UPDATE invoices\s+SET total_amount = total_amount \+ \$1/.test(s))).toBe(true);
    expect(attachedTo()).toEqual([INVOICE, 'li-1']);
  });

  it('still attaches on the last day of the window (default due date)', async () => {
    db.invoices = [anniversaryDraft()];
    nowInKolkata('2026-10-17T21:00:00');
    const service = await load();

    await service.submit(input);
    expect(attachedTo()).toEqual([INVOICE, 'li-1']);
  });

  it('uses the property time zone: just after midnight IST is already outside the window', async () => {
    db.invoices = [anniversaryDraft()];
    // 18 Oct 00:30 IST is still 17 Oct in UTC.
    nowInKolkata('2026-10-18T00:30:00');
    const service = await load();

    await service.submit(input);
    expect(db.log.find((s) => CLOSING_DRAFT.test(s.sql))!.params[3]).toBe('2026-10-18');
    expect(attachedTo()).toEqual([null, null]);
  });

  it('leaves a reading pending when it falls inside a period whose draft does not exist yet', async () => {
    // Previous cycle's draft is unsent, but this reading belongs to the running period.
    db.invoices = [anniversaryDraft()];
    nowInKolkata('2026-10-25T10:00:00');
    const service = await load();

    await service.submit(input);
    expect(db.txEvents).toEqual(['BEGIN', 'COMMIT']);
    expect(attachedTo()).toEqual([null, null]);
    expect(readingInsert().params[7]).toBe(400);
  });

  it('never attaches to another tenancy, another unit, an ad hoc draft or a sent invoice', async () => {
    db.invoices = [
      anniversaryDraft({ id: 'other-tenancy', tenancy_id: OTHER_TENANCY }),
      anniversaryDraft({ id: 'other-unit', node_id: OTHER_UNIT }),
      anniversaryDraft({ id: 'adhoc', invoice_kind: 'adhoc' }),
      anniversaryDraft({ id: 'sent', sent_at: new Date('2026-10-12T05:00:00Z') }),
    ];
    const service = await load();

    await service.submit(input);

    expect(db.log.some((s) => /INSERT INTO invoice_line_items|UPDATE invoices/.test(s.sql))).toBe(false);
    expect(attachedTo()).toEqual([null, null]);
  });

  it('with only a sent invoice for the cycle, leaves the bill untouched and keeps the reading pending', async () => {
    db.invoices = [anniversaryDraft({ sent_at: new Date('2026-10-12T05:00:00Z') })];
    const service = await load();

    await service.submit(input);

    expect(db.txEvents).toEqual(['BEGIN', 'COMMIT']);
    expect(db.log.some((s) => /INSERT INTO invoice_line_items|UPDATE invoices/.test(s.sql))).toBe(false);
    expect(readingInsert().tx).toBe(true);
    expect(attachedTo()).toEqual([null, null]);
  });

  it('rolls the draft change back if the reading cannot be stored', async () => {
    db.invoices = [anniversaryDraft()];
    db.failReadingInsert = true;
    const service = await load();

    await expect(service.submit(input)).rejects.toThrow('insert failed');
    expect(db.txEvents).toEqual(['BEGIN', 'ROLLBACK']);
  });

  it('rejects a unit or tenancy outside the property before reading or writing anything', async () => {
    db.invoices = [anniversaryDraft()];
    db.targetOk = false;
    const service = await load();

    await expect(service.submit(input)).rejects.toThrow('Not found');
    const check = db.log.find((s) => /AS unit_ok/.test(s.sql))!;
    expect(check.params).toEqual([UNIT, PROPERTY, TENANCY]);
    expect(db.txEvents).toEqual([]);
    expect(db.log.some((s) => /INSERT INTO|UPDATE /.test(s.sql))).toBe(false);
  });

  it('never deletes readings, line items or invoices', async () => {
    db.invoices = [anniversaryDraft()];
    const service = await load();
    await service.submit(input);
    expect(db.log.some((s) => /DELETE/i.test(s.sql))).toBe(false);
  });
});

describe('meter reading notifications', () => {
  it('does not notify the tenant when the reading is attached to a draft; owners are told to review', async () => {
    db.invoices = [anniversaryDraft()];
    const service = await load();
    const notify = await import('../notifications/notify.js');

    await service.submit({ ...input, notifyOwners: true });

    expect(attachedTo()).toEqual([INVOICE, 'li-1']);
    expect(notify.createNotification).not.toHaveBeenCalled();
    expect(notify.notifyPropertyOwners).toHaveBeenCalledTimes(1);
    const owner = vi.mocked(notify.notifyPropertyOwners).mock.calls[0][0] as any;
    expect(owner.type).toBe('meter_reading');
    expect(owner.body).toMatch(/draft invoice/);
    expect(owner.data.invoice_id).toBe(INVOICE);
  });

  it('does not notify the tenant about a pending reading either', async () => {
    const service = await load();
    const notify = await import('../notifications/notify.js');

    await service.submit(input);

    expect(attachedTo()).toEqual([null, null]);
    expect(notify.createNotification).not.toHaveBeenCalled();
  });
});
