import { beforeEach, describe, expect, it, vi } from 'vitest';

type Stmt = { sql: string; params: unknown[]; tx: boolean };

type InvoiceFixture = {
  id: string;
  tenancy_id: string;
  tenant_user_id: string | null;
  sent_at: Date | null;
  is_auto_generated: boolean;
  period_start: string;
  period_end: string;
  due_date: string;
  total_amount: string;
  invoice_kind: 'cycle' | 'adhoc';
  paid: string;
};

const db = {
  log: [] as Stmt[],
  txEvents: [] as string[],
  invoice: null as InvoiceFixture | null,
  lines: [] as {
    id: string;
    description: string;
    amount: string;
    charge_type_id: string | null;
    meter_linked: boolean;
  }[],
  /** Unattached meter readings returned by listPendingUtilityCharges. */
  pending: [] as { id: string; amount: string; billing_cycle: string; units_consumed: string; rate_per_unit: string }[],
  failNotification: false,
};

function run(sql: string, params: unknown[] = [], tx = false): unknown[] {
  db.log.push({ sql, params, tx });
  if (/information_schema\.columns[\s\S]*invoice_kind/.test(sql)) {
    return [{ column_name: 'invoice_kind' }, { column_name: 'approved_by' }];
  }
  if (/overdue_notified_at'\s*\)\s*AS exists/.test(sql)) return [{ exists: true }];
  if (/cycle_index_valid/.test(sql)) return [{ cycle_index_valid: true, legacy_index_exists: false }];
  if (/SELECT timezone FROM properties/.test(sql)) return [{ timezone: 'Asia/Kolkata' }];
  if (
    tx &&
    /FROM invoices i\s+LEFT JOIN tenancies t ON t\.id = i\.tenancy_id\s+WHERE i\.id = \$1 AND i\.property_id = \$2\s+FOR UPDATE OF i/.test(sql)
  ) {
    return db.invoice ? [db.invoice] : [];
  }
  if (tx && /INSERT INTO notifications/.test(sql) && db.failNotification) {
    throw new Error('notification insert failed');
  }
  if (tx && /SELECT sent_at FROM invoices\s+WHERE id = \$1 AND property_id = \$2/.test(sql)) {
    return db.invoice ? [{ sent_at: db.invoice.sent_at }] : [];
  }
  if (tx && /FROM invoice_line_items li WHERE li\.invoice_id = \$1/.test(sql)) return db.lines;
  if (tx && /SELECT id, tenancy_id, property_id FROM invoices WHERE id/.test(sql)) {
    return [{ id: INVOICE, tenancy_id: TENANCY, property_id: PROPERTY }];
  }
  if (tx && /FROM meter_readings mr/.test(sql)) return db.pending;
  if (tx && /SELECT total_amount::text AS total_amount FROM invoices WHERE id = \$1/.test(sql)) {
    return db.invoice ? [{ total_amount: db.invoice.total_amount }] : [];
  }
  if (tx && /INSERT INTO invoice_line_items[\s\S]*RETURNING id/.test(sql)) return [{ id: 'li-new' }];
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
  resolvePropertyOwnerIds: vi.fn(async () => ['owner-1']),
}));

vi.mock('@modules/notifications/notify', () => ({
  createNotification: vi.fn(async () => true),
  notifyPropertyOwners: vi.fn(async () => 0),
}));

const PROPERTY = '11111111-1111-4111-8111-111111111111';
const TENANCY = '22222222-2222-4222-8222-222222222222';
const INVOICE = '33333333-3333-4333-8333-333333333333';

const TENANT_USER = '77777777-7777-4777-8777-777777777777';

const RENT_LINE = {
  id: 'li-rent',
  description: 'Sep 2026 Rent',
  amount: '5000.00',
  charge_type_id: 'ct-rent',
  meter_linked: false,
};
const METER_LINE = {
  id: 'li-meter',
  description: 'Electricity (2026-09): 50 units @ ₹8',
  amount: '400.00',
  charge_type_id: 'ct-el',
  meter_linked: true,
};

const sentUnpaid = (): InvoiceFixture => ({
  id: INVOICE,
  tenancy_id: TENANCY,
  tenant_user_id: TENANT_USER,
  sent_at: new Date('2026-10-02T05:00:00Z'),
  is_auto_generated: true,
  period_start: '2026-09-01',
  period_end: '2026-09-30',
  due_date: '2026-10-06',
  total_amount: '5000.00',
  invoice_kind: 'cycle',
  paid: '0',
});

const sameForm = {
  periodStart: '2026-09-01',
  periodEnd: '2026-09-30',
  dueDate: '2026-10-06',
  lineItems: [{ description: 'Sep 2026 Rent', amount: 5000 }],
};

async function loadService() {
  vi.resetModules();
  const mod = await import('./billing.service.js');
  const service = new mod.BillingService();
  vi.spyOn(service, 'getById').mockImplementation(async (id: unknown) => ({ id }) as any);
  // Boot-time schema work (including its own transaction) is not under test.
  await mod.ensureBillingSchema();
  db.log = [];
  db.txEvents = [];
  return { mod, service };
}

const txStmts = () => db.log.filter((s) => s.tx);
const writes = () =>
  txStmts().filter((s) =>
    /^\s*(UPDATE invoices|UPDATE invoice_line_items|DELETE FROM|INSERT INTO)/.test(s.sql),
  );
const notifications = () => txStmts().filter((s) => /INSERT INTO notifications/.test(s.sql));
const notice = (i = 0) => {
  const params = notifications()[i].params;
  return { userId: params[0], type: params[2], title: params[3], body: String(params[4]), data: JSON.parse(String(params[5])) };
};

beforeEach(() => {
  db.log = [];
  db.txEvents = [];
  db.invoice = sentUnpaid();
  db.lines = [RENT_LINE];
  db.pending = [];
  db.failNotification = false;
});

describe('invoiceEditBlock rules', () => {
  const state = { sent: true, kind: 'cycle' as const, total: 5000, paid: 0 };
  const none = { periodChanged: false, dueDateChanged: false, chargesChanged: false };

  it('allows charges and due date on an unpaid sent invoice', async () => {
    const { mod } = await loadService();
    expect(
      mod.invoiceEditBlock(state, { ...none, chargesChanged: true, dueDateChanged: true }),
    ).toBeNull();
  });

  it('locks the period of a sent invoice', async () => {
    const { mod } = await loadService();
    expect(mod.invoiceEditBlock(state, { ...none, periodChanged: true })?.code).toBe(
      'invoice_period_locked',
    );
    expect(
      mod.invoiceEditBlock({ ...state, kind: 'adhoc' }, { ...none, periodChanged: true })?.code,
    ).toBe('invoice_period_locked');
  });

  it('locks a cycle draft period but lets a one-off draft move', async () => {
    const { mod } = await loadService();
    expect(
      mod.invoiceEditBlock({ ...state, sent: false }, { ...none, periodChanged: true })?.code,
    ).toBe('cycle_period_locked');
    expect(
      mod.invoiceEditBlock(
        { ...state, sent: false, kind: 'adhoc' },
        { ...none, periodChanged: true },
      ),
    ).toBeNull();
  });

  it('partially paid: charges locked, due date may move, unchanged re-save allowed', async () => {
    const { mod } = await loadService();
    const partial = { ...state, paid: 2000 };
    const err = mod.invoiceEditBlock(partial, { ...none, chargesChanged: true });
    expect(err?.code).toBe('invoice_partially_paid');
    expect(err?.message).toMatch(/can still change the due date/);
    expect(
      mod.invoiceEditBlock(partial, { ...none, chargesChanged: true, dueDateChanged: true })?.code,
    ).toBe('invoice_partially_paid');
    expect(mod.invoiceEditBlock(partial, { ...none, dueDateChanged: true })).toBeNull();
    expect(mod.invoiceEditBlock(partial, none)).toBeNull();
  });

  it('fully paid: charges and due date locked', async () => {
    const { mod } = await loadService();
    const paid = { ...state, paid: 5000 };
    const err = mod.invoiceEditBlock(paid, { ...none, chargesChanged: true });
    expect(err?.code).toBe('invoice_paid');
    expect(err?.message).toMatch(/fully paid/);
    expect(mod.invoiceEditBlock(paid, { ...none, dueDateChanged: true })?.code).toBe('invoice_paid');
  });

  it('sameCharges ignores order and a missing charge type, but not amounts', async () => {
    const { mod } = await loadService();
    const current = [
      { description: 'Rent', amount: 5000, chargeTypeId: 'ct-rent' },
      { description: 'Electricity', amount: 400, chargeTypeId: 'ct-el' },
    ];
    expect(
      mod.sameCharges(current, [
        { description: 'Electricity', amount: 400, chargeTypeId: null },
        { description: 'Rent', amount: 5000, chargeTypeId: null },
      ]),
    ).toBe(true);
    expect(
      mod.sameCharges(current, [
        { description: 'Rent', amount: 5000, chargeTypeId: null },
        { description: 'Electricity', amount: 450, chargeTypeId: null },
      ]),
    ).toBe(false);
    expect(
      mod.sameCharges(current, [{ description: 'Rent', amount: 5000, chargeTypeId: 'other' }, current[1]]),
    ).toBe(false);
  });
});

describe('updateInvoice', () => {
  it('edits charges and due date on an unpaid sent invoice in one transaction', async () => {
    const { service } = await loadService();

    await service.updateInvoice(INVOICE, PROPERTY, {
      ...sameForm,
      dueDate: '2026-10-10',
      lineItems: [
        { description: 'Sep 2026 Rent', amount: 5000 },
        { description: 'Late fee', amount: 200 },
      ],
    });

    expect(db.txEvents).toEqual(['BEGIN', 'COMMIT']);
    const update = txStmts().find((s) => /^\s*UPDATE invoices/.test(s.sql))!;
    expect(update.params).toEqual(['2026-09-01', '2026-09-30', '2026-10-10', 5200, INVOICE, PROPERTY]);
    expect(update.sql).toMatch(/overdue_notified_at = CASE/);
    // The unchanged rent line keeps its row; only the new charge is inserted.
    const inserts = txStmts().filter((s) => /INSERT INTO invoice_line_items/.test(s.sql));
    expect(inserts).toHaveLength(1);
    expect(inserts[0].params[2]).toBe('Late fee');
    expect(txStmts().some((s) => /DELETE FROM invoice_line_items/.test(s.sql))).toBe(false);
  });

  it('a due-date-only save keeps existing line items (and their meter links)', async () => {
    const { service } = await loadService();

    await service.updateInvoice(INVOICE, PROPERTY, { ...sameForm, dueDate: '2026-10-12' });

    expect(db.txEvents).toEqual(['BEGIN', 'COMMIT']);
    expect(txStmts().some((s) => /DELETE FROM invoice_line_items/.test(s.sql))).toBe(false);
    const update = txStmts().find((s) => /^\s*UPDATE invoices/.test(s.sql))!;
    expect(update.params[3]).toBe(5000);
  });

  it('notifies the tenant of a charge change on a sent invoice, in the same transaction', async () => {
    const { service } = await loadService();

    await service.updateInvoice(INVOICE, PROPERTY, {
      ...sameForm,
      lineItems: [
        { description: 'Sep 2026 Rent', amount: 5000 },
        { description: 'Late fee', amount: 200 },
      ],
    });

    expect(db.txEvents).toEqual(['BEGIN', 'COMMIT']);
    expect(notifications()).toHaveLength(1);
    const n = notice();
    expect(n.userId).toBe(TENANT_USER);
    expect(n.type).toBe('invoice_updated');
    expect(n.body).toContain('New total: ₹5200');
    expect(n.body).not.toContain('New due date');
    expect(n.data).toMatchObject({ invoice_id: INVOICE, total_amount: 5200, amount_due: 5200, due_date: '2026-10-06' });
  });

  it('notifies the tenant of a new due date on a sent invoice', async () => {
    const { service } = await loadService();

    await service.updateInvoice(INVOICE, PROPERTY, { ...sameForm, dueDate: '2026-10-12' });

    expect(notifications()).toHaveLength(1);
    expect(notice().body).toContain('New due date');
    expect(notice().body).not.toContain('New total');
    expect(notice().data.due_date).toBe('2026-10-12');
  });

  it('does not notify for a no-op save, and a repeated edit notifies only once', async () => {
    const { service } = await loadService();

    await service.updateInvoice(INVOICE, PROPERTY, sameForm);
    expect(notifications()).toHaveLength(0);

    // Retrying the same edit after it committed is a no-op.
    await service.updateInvoice(INVOICE, PROPERTY, { ...sameForm, dueDate: '2026-10-12' });
    db.invoice = { ...db.invoice!, due_date: '2026-10-12' };
    await service.updateInvoice(INVOICE, PROPERTY, { ...sameForm, dueDate: '2026-10-12' });
    expect(notifications()).toHaveLength(1);
  });

  it('does not notify the tenant about draft edits', async () => {
    db.invoice = { ...sentUnpaid(), sent_at: null };
    const { service } = await loadService();

    await service.updateInvoice(INVOICE, PROPERTY, {
      ...sameForm,
      dueDate: '2026-10-09',
      lineItems: [{ description: 'Sep 2026 Rent', amount: 5500 }],
    });

    expect(db.txEvents).toEqual(['BEGIN', 'COMMIT']);
    expect(notifications()).toHaveLength(0);
  });

  it('rolls the edit back if the tenant notification cannot be stored', async () => {
    db.failNotification = true;
    const { service } = await loadService();

    await expect(
      service.updateInvoice(INVOICE, PROPERTY, { ...sameForm, dueDate: '2026-10-12' }),
    ).rejects.toThrow('notification insert failed');
    expect(db.txEvents).toEqual(['BEGIN', 'ROLLBACK']);
  });

  it('skips the notice when the tenancy has no app user', async () => {
    db.invoice = { ...sentUnpaid(), tenant_user_id: null };
    const { service } = await loadService();

    await service.updateInvoice(INVOICE, PROPERTY, { ...sameForm, dueDate: '2026-10-12' });
    expect(db.txEvents).toEqual(['BEGIN', 'COMMIT']);
    expect(notifications()).toHaveLength(0);
  });

  it('blocks a billing-period change on a sent invoice and writes nothing', async () => {
    const { service, mod } = await loadService();

    const err = await service
      .updateInvoice(INVOICE, PROPERTY, { ...sameForm, periodStart: '2026-09-05' })
      .catch((e: unknown) => e);

    expect(err).toBeInstanceOf(mod.InvoiceLockedError);
    expect((err as any).code).toBe('invoice_period_locked');
    expect(db.txEvents).toEqual(['BEGIN', 'ROLLBACK']);
    expect(writes()).toHaveLength(0);
  });

  it('blocks a period change on a cycle draft (cycle idempotency)', async () => {
    db.invoice = { ...sentUnpaid(), sent_at: null };
    const { service } = await loadService();

    await expect(
      service.updateInvoice(INVOICE, PROPERTY, { ...sameForm, periodEnd: '2026-10-05' }),
    ).rejects.toMatchObject({ code: 'cycle_period_locked' });
    expect(writes()).toHaveLength(0);
  });

  it('keeps the existing draft workflow for charges and due date', async () => {
    db.invoice = { ...sentUnpaid(), sent_at: null };
    const { service } = await loadService();

    await service.updateInvoice(INVOICE, PROPERTY, {
      ...sameForm,
      dueDate: '2026-10-09',
      lineItems: [{ description: 'Sep 2026 Rent', amount: 5500 }],
    });

    expect(db.txEvents).toEqual(['BEGIN', 'COMMIT']);
  });

  it('lets a one-off draft change its period', async () => {
    db.invoice = {
      ...sentUnpaid(),
      sent_at: null,
      is_auto_generated: false,
      invoice_kind: 'adhoc',
      period_start: '2026-10-12',
      period_end: '2026-10-12',
    };
    db.lines = [
      { id: 'li-key', description: 'Key replacement', amount: '750.00', charge_type_id: null, meter_linked: false },
    ];
    const { service } = await loadService();

    await service.updateInvoice(INVOICE, PROPERTY, {
      periodStart: '2026-10-13',
      periodEnd: '2026-10-13',
      dueDate: '2026-10-20',
      lineItems: [{ description: 'Key replacement', amount: 750 }],
    });

    expect(db.txEvents).toEqual(['BEGIN', 'COMMIT']);
  });

  it('partially paid: blocks a charge change', async () => {
    db.invoice = { ...sentUnpaid(), paid: '2000' };
    const { service } = await loadService();

    await expect(
      service.updateInvoice(INVOICE, PROPERTY, {
        ...sameForm,
        lineItems: [{ description: 'Sep 2026 Rent', amount: 1500 }],
      }),
    ).rejects.toMatchObject({ code: 'invoice_partially_paid' });
    expect(db.txEvents).toEqual(['BEGIN', 'ROLLBACK']);
    expect(writes()).toHaveLength(0);
  });

  it('partially paid: allows a due-date change and tells the tenant the balance', async () => {
    db.invoice = { ...sentUnpaid(), paid: '2000' };
    const { service } = await loadService();

    await service.updateInvoice(INVOICE, PROPERTY, { ...sameForm, dueDate: '2026-10-20' });

    expect(db.txEvents).toEqual(['BEGIN', 'COMMIT']);
    const update = txStmts().find((s) => /^\s*UPDATE invoices/.test(s.sql))!;
    expect(update.params.slice(2, 4)).toEqual(['2026-10-20', 5000]);
    expect(
      txStmts().some(
        (s) => /^\s*(DELETE FROM|INSERT INTO|UPDATE) invoice_line_items/.test(s.sql),
      ),
    ).toBe(false);
    expect(notice().body).toContain('Balance due: ₹3000');
    expect(notice().data.amount_due).toBe(3000);
  });

  it('fully paid: blocks a due-date change but allows an unchanged re-save', async () => {
    db.invoice = { ...sentUnpaid(), paid: '5000' };
    const { service } = await loadService();

    await expect(
      service.updateInvoice(INVOICE, PROPERTY, { ...sameForm, dueDate: '2026-10-20' }),
    ).rejects.toMatchObject({ code: 'invoice_paid' });

    db.txEvents = [];
    await service.updateInvoice(INVOICE, PROPERTY, sameForm);
    expect(db.txEvents).toEqual(['BEGIN', 'COMMIT']);
    expect(txStmts().some((s) => /DELETE FROM invoice_line_items/.test(s.sql))).toBe(false);
  });

  it('refuses to empty a sent invoice', async () => {
    const { service } = await loadService();

    await expect(
      service.updateInvoice(INVOICE, PROPERTY, {
        ...sameForm,
        lineItems: [{ description: 'Waived', amount: 0 }],
      }),
    ).rejects.toThrow(/at least one charge/);
    expect(writes()).toHaveLength(0);
  });

  it('returns null for an invoice outside the property (scoped lookup)', async () => {
    db.invoice = null;
    const { service } = await loadService();

    expect(await service.updateInvoice(INVOICE, PROPERTY, sameForm)).toBeNull();
    const lookup = txStmts().find((s) => /FOR UPDATE OF i/.test(s.sql))!;
    expect(lookup.params).toEqual([INVOICE, PROPERTY]);
    expect(writes()).toHaveLength(0);
  });
});

describe('meter-reading line links', () => {
  const rent = { description: 'Sep 2026 Rent', amount: 5000 };
  const meter = { description: METER_LINE.description, amount: 400 };

  beforeEach(() => {
    db.lines = [RENT_LINE, METER_LINE];
    db.invoice = { ...sentUnpaid(), total_amount: '5400.00' };
  });

  it('planLineItemChanges keeps matches, updates a meter line in place, blocks its removal', async () => {
    const { mod } = await loadService();
    const current = [
      { id: 'a', description: 'Rent', amount: 5000, chargeTypeId: 'ct-rent', meterLinked: false },
      { id: 'm', description: 'Electricity', amount: 400, chargeTypeId: 'ct-el', meterLinked: true },
      { id: 'x', description: 'Old fee', amount: 100, chargeTypeId: null, meterLinked: false },
    ];
    const plan = mod.planLineItemChanges(current, [
      { description: 'Rent', amount: 5000, chargeTypeId: null },
      { description: 'Electricity', amount: 350, chargeTypeId: null },
      { description: 'Late fee', amount: 200, chargeTypeId: null },
    ]);
    expect(plan.keep).toEqual(['a']);
    expect(plan.update).toEqual([{ id: 'm', line: { description: 'Electricity', amount: 350, chargeTypeId: null } }]);
    expect(plan.remove).toEqual(['x']);
    expect(plan.insert.map((l) => l.description)).toEqual(['Late fee']);
    expect(plan.blocked).toEqual([]);

    const removed = mod.planLineItemChanges(current, [{ description: 'Rent', amount: 5000, chargeTypeId: null }]);
    expect(removed.blocked.map((l) => l.id)).toEqual(['m']);
  });

  it('a duplicate-looking manual line never takes a meter line\'s exact match', async () => {
    const { mod } = await loadService();
    const plan = mod.planLineItemChanges(
      [
        { id: 'manual', description: 'Electricity', amount: 400, chargeTypeId: null, meterLinked: false },
        { id: 'meter', description: 'Electricity', amount: 400, chargeTypeId: null, meterLinked: true },
      ],
      [{ description: 'Electricity', amount: 400, chargeTypeId: null }],
    );
    expect(plan.keep).toEqual(['meter']);
    expect(plan.remove).toEqual(['manual']);
  });

  it('adding a charge leaves the meter line row (and the reading link) untouched', async () => {
    const { service } = await loadService();

    await service.updateInvoice(INVOICE, PROPERTY, {
      ...sameForm,
      lineItems: [rent, meter, { description: 'Late fee', amount: 200 }],
    });

    expect(db.txEvents).toEqual(['BEGIN', 'COMMIT']);
    expect(txStmts().some((s) => /DELETE FROM invoice_line_items/.test(s.sql))).toBe(false);
    expect(txStmts().some((s) => /UPDATE invoice_line_items/.test(s.sql))).toBe(false);
    expect(txStmts().some((s) => /meter_readings/.test(s.sql) && /^\s*(UPDATE|DELETE)/.test(s.sql))).toBe(false);
  });

  it('changing the meter line amount updates the same row in place', async () => {
    const { service } = await loadService();

    await service.updateInvoice(INVOICE, PROPERTY, {
      ...sameForm,
      lineItems: [rent, { ...meter, amount: 360 }],
    });

    expect(db.txEvents).toEqual(['BEGIN', 'COMMIT']);
    const upd = txStmts().find((s) => /UPDATE invoice_line_items/.test(s.sql))!;
    expect(upd.params).toEqual([METER_LINE.description, 360, null, null, 'li-meter', INVOICE]);
    expect(txStmts().some((s) => /DELETE FROM invoice_line_items/.test(s.sql))).toBe(false);
    const inv = txStmts().find((s) => /^\s*UPDATE invoices/.test(s.sql))!;
    expect(inv.params[3]).toBe(5360);
  });

  it('removing a non-meter line deletes only that row, guarded against meter links', async () => {
    db.lines = [RENT_LINE, METER_LINE, { ...RENT_LINE, id: 'li-fee', description: 'Old fee', amount: '100.00', charge_type_id: null }];
    const { service } = await loadService();

    await service.updateInvoice(INVOICE, PROPERTY, { ...sameForm, lineItems: [rent, meter] });

    const del = txStmts().find((s) => /DELETE FROM invoice_line_items/.test(s.sql))!;
    expect(del.params).toEqual([INVOICE, ['li-fee']]);
    expect(del.sql).toMatch(/NOT EXISTS \(SELECT 1 FROM meter_readings mr/);
  });

  it('blocks removing or renaming a meter line with 409 and writes nothing', async () => {
    const { service, mod } = await loadService();

    const removed = await service
      .updateInvoice(INVOICE, PROPERTY, { ...sameForm, lineItems: [rent] })
      .catch((e: unknown) => e);
    expect(removed).toBeInstanceOf(mod.InvoiceLockedError);
    expect((removed as any).code).toBe('meter_line_linked');
    expect(db.txEvents).toEqual(['BEGIN', 'ROLLBACK']);

    await expect(
      service.updateInvoice(INVOICE, PROPERTY, {
        ...sameForm,
        lineItems: [rent, { description: 'Power', amount: 400 }],
      }),
    ).rejects.toMatchObject({ code: 'meter_line_linked' });
    expect(writes()).toHaveLength(0);

    const { errorHandler } = await import('../../shared/middleware/error-handler.js');
    const res: any = { status: vi.fn(() => res), json: vi.fn(() => res) };
    errorHandler(removed, {} as any, res, vi.fn());
    expect(res.status).toHaveBeenCalledWith(409);
  });

  it('also protects meter lines on drafts', async () => {
    db.invoice = { ...sentUnpaid(), sent_at: null, total_amount: '5400.00' };
    const { service } = await loadService();

    await expect(
      service.updateInvoice(INVOICE, PROPERTY, { ...sameForm, lineItems: [rent] }),
    ).rejects.toMatchObject({ code: 'meter_line_linked' });
  });
});

describe('updateDueDate', () => {
  it('allows an unpaid sent invoice and resets the overdue notice', async () => {
    const { service } = await loadService();

    await service.updateDueDate(INVOICE, PROPERTY, '2026-10-15');

    expect(db.txEvents).toEqual(['BEGIN', 'COMMIT']);
    const update = txStmts().find((s) => /^\s*UPDATE invoices/.test(s.sql))!;
    expect(update.sql).toMatch(/overdue_notified_at = CASE/);
    expect(update.params).toEqual(['2026-10-15', INVOICE, PROPERTY]);
  });

  it('allows a partially paid invoice and notifies the tenant once, with the balance', async () => {
    db.invoice = { ...sentUnpaid(), paid: '1000' };
    const { service } = await loadService();

    await service.updateDueDate(INVOICE, PROPERTY, '2026-10-15');

    expect(db.txEvents).toEqual(['BEGIN', 'COMMIT']);
    const update = txStmts().find((s) => /^\s*UPDATE invoices/.test(s.sql))!;
    expect(update.params).toEqual(['2026-10-15', INVOICE, PROPERTY]);
    expect(notifications()).toHaveLength(1);
    expect(notice().userId).toBe(TENANT_USER);
    expect(notice().body).toContain('New due date');
    expect(notice().body).toContain('Balance due: ₹4000');
    expect(notice().data).toMatchObject({ due_date: '2026-10-15', amount_due: 4000 });
  });

  it('blocks a fully paid invoice', async () => {
    db.invoice = { ...sentUnpaid(), paid: '5000' };
    const { service } = await loadService();

    await expect(service.updateDueDate(INVOICE, PROPERTY, '2026-10-15')).rejects.toMatchObject({
      code: 'invoice_paid',
    });
    expect(db.txEvents).toEqual(['BEGIN', 'ROLLBACK']);
    expect(writes()).toHaveLength(0);
  });

  it('same due date: no write and no notification', async () => {
    const { service } = await loadService();

    await service.updateDueDate(INVOICE, PROPERTY, '2026-10-06');
    expect(db.txEvents).toEqual(['BEGIN', 'COMMIT']);
    expect(writes()).toHaveLength(0);
  });

  it('rolls back if the tenant notification fails', async () => {
    db.failNotification = true;
    const { service } = await loadService();

    await expect(service.updateDueDate(INVOICE, PROPERTY, '2026-10-15')).rejects.toThrow(
      'notification insert failed',
    );
    expect(db.txEvents).toEqual(['BEGIN', 'ROLLBACK']);
  });

  it('allows a draft without notifying the tenant', async () => {
    db.invoice = { ...sentUnpaid(), sent_at: null };
    const { service } = await loadService();

    await service.updateDueDate(INVOICE, PROPERTY, '2026-10-15');
    expect(db.txEvents).toEqual(['BEGIN', 'COMMIT']);
    expect(notifications()).toHaveLength(0);
  });

  it('returns null outside the property', async () => {
    db.invoice = null;
    const { service } = await loadService();
    expect(await service.updateDueDate(INVOICE, PROPERTY, '2026-10-15')).toBeNull();
  });
});

describe('attachPendingChargesToDraft', () => {
  it('refuses a sent invoice; pending readings stay unattached', async () => {
    const { service, mod } = await loadService();

    const err = await service
      .attachPendingChargesToDraft(INVOICE, PROPERTY, TENANCY)
      .catch((e: unknown) => e);

    expect(err).toBeInstanceOf(mod.InvoiceLockedError);
    expect((err as any).code).toBe('invoice_sent');
    expect(db.txEvents).toEqual(['BEGIN', 'ROLLBACK']);
    expect(db.log.some((s) => /UPDATE meter_readings|INSERT INTO invoice_line_items/.test(s.sql))).toBe(false);
  });

  it('attaches to a draft on the same transaction', async () => {
    db.invoice = { ...sentUnpaid(), sent_at: null };
    const { service } = await loadService();

    await service.attachPendingChargesToDraft(INVOICE, PROPERTY, TENANCY);

    expect(db.txEvents).toEqual(['BEGIN', 'COMMIT']);
    const pending = txStmts().find((s) => /FROM meter_readings mr/.test(s.sql))!;
    expect(pending.sql).toMatch(/FOR UPDATE OF mr/);
  });

  it('returns null outside the property', async () => {
    db.invoice = null;
    const { service } = await loadService();
    expect(await service.attachPendingChargesToDraft(INVOICE, PROPERTY, TENANCY)).toBeNull();
  });
});

describe('pending charges and the NUMERIC(12,2) invoice total', () => {
  const reading = (id: string, amount: string) => ({
    id,
    amount,
    billing_cycle: '2026-09',
    units_consumed: '1',
    rate_per_unit: amount,
  });
  const draftWithTotal = (total_amount: string) => ({ ...sentUnpaid(), sent_at: null, total_amount });
  const attachWrites = () =>
    txStmts().filter((s) =>
      /INSERT INTO invoice_line_items|UPDATE meter_readings|UPDATE invoices/.test(s.sql),
    );

  it('attaches a pending charge that brings the total exactly to 9,999,999,999.99', async () => {
    db.invoice = draftWithTotal('9999999000.00');
    db.pending = [reading('mr-1', '999.99')];
    const { service } = await loadService();

    const result = await service.attachPendingChargesToDraft(INVOICE, PROPERTY, TENANCY);

    expect(result).toEqual({ added: 1, amount: 999.99 });
    expect(db.txEvents).toEqual(['BEGIN', 'COMMIT']);
    const total = txStmts().find((s) => /UPDATE invoices\s+SET total_amount = total_amount \+ \$1/.test(s.sql))!;
    expect(total.params).toEqual([999.99, INVOICE]);
  });

  it('refuses a total one paisa above the limit and writes nothing', async () => {
    db.invoice = draftWithTotal('9999999000.00');
    db.pending = [reading('mr-1', '1000.00')];
    const { service, mod } = await loadService();

    const err = await service
      .attachPendingChargesToDraft(INVOICE, PROPERTY, TENANCY)
      .catch((e: unknown) => e);

    expect(err).toBeInstanceOf(mod.InvoiceAmountRangeError);
    expect((err as any).code).toBe('invoice_total_out_of_range');
    expect(db.txEvents).toEqual(['BEGIN', 'ROLLBACK']);
    expect(attachWrites()).toEqual([]);
  });

  it('refuses several pending charges that only overflow together, attaching none of them', async () => {
    db.invoice = draftWithTotal('9999990000.00');
    // Each fits on its own; together they are 10,000.01 on top of the draft.
    db.pending = [reading('mr-1', '4000.00'), reading('mr-2', '3000.00'), reading('mr-3', '3000.01')];
    const { service } = await loadService();

    const err = await service
      .attachPendingChargesToDraft(INVOICE, PROPERTY, TENANCY)
      .catch((e: unknown) => e);

    expect((err as any).code).toBe('invoice_total_out_of_range');
    expect(db.txEvents).toEqual(['BEGIN', 'ROLLBACK']);
    expect(attachWrites()).toEqual([]);
  });

  it('several pending charges that land exactly on the limit are all attached', async () => {
    db.invoice = draftWithTotal('9999990000.00');
    db.pending = [reading('mr-1', '4000.00'), reading('mr-2', '3000.00'), reading('mr-3', '2999.99')];
    const { service } = await loadService();

    const result = await service.attachPendingChargesToDraft(INVOICE, PROPERTY, TENANCY);

    expect(result).toEqual({ added: 3, amount: 9999.99 });
    expect(db.txEvents).toEqual(['BEGIN', 'COMMIT']);
    expect(txStmts().filter((s) => /UPDATE meter_readings/.test(s.sql))).toHaveLength(3);
  });

  it('called without a transaction, it opens one so a refusal leaves nothing attached', async () => {
    db.invoice = draftWithTotal('9999999999.99');
    db.pending = [reading('mr-1', '0.01')];
    const { service } = await loadService();

    const err = await service.addPendingChargesToInvoice(TENANCY, INVOICE).catch((e: unknown) => e);

    expect((err as any).code).toBe('invoice_total_out_of_range');
    expect(db.txEvents).toEqual(['BEGIN', 'ROLLBACK']);
    expect(attachWrites()).toEqual([]);
  });

  it('the API answers the refusal with a 400 and the stable code', async () => {
    const { mod } = await loadService();
    const { errorHandler } = await import('../../shared/middleware/error-handler.js');
    const res: any = { status: vi.fn(() => res), json: vi.fn(() => res) };

    errorHandler(new mod.InvoiceAmountRangeError(), {} as any, res, () => undefined);

    expect(res.status).toHaveBeenCalledWith(400);
    expect(res.json).toHaveBeenCalledWith({
      error: expect.stringContaining('largest amount supported'),
      code: 'invoice_total_out_of_range',
    });
  });

  it('editing a draft past the limit is refused before the transaction', async () => {
    db.invoice = draftWithTotal('5000.00');
    const { service } = await loadService();

    const err = await service
      .updateInvoice(INVOICE, PROPERTY, {
        ...sameForm,
        lineItems: [
          { description: 'Sep 2026 Rent', amount: 9_999_999_999.99 },
          { description: 'Maintenance', amount: 0.01 },
        ],
      })
      .catch((e: unknown) => e);

    expect((err as any).code).toBe('invoice_total_out_of_range');
    expect(db.txEvents).toEqual([]);
  });
});

describe('API layer', () => {
  it('rejects identity fields on edit with 400, and accepts the app payload', async () => {
    const { assertNoIdentityFields } = await import('./billing.controller.js');
    const { errorHandler } = await import('../../shared/middleware/error-handler.js');

    expect(() => assertNoIdentityFields(sameForm)).not.toThrow();

    let caught: unknown;
    try {
      assertNoIdentityFields({ ...sameForm, tenancyId: TENANCY, invoice_kind: 'adhoc' });
    } catch (e) {
      caught = e;
    }
    const res: any = { status: vi.fn(() => res), json: vi.fn(() => res) };
    errorHandler(caught, {} as any, res, vi.fn());
    expect(res.status).toHaveBeenCalledWith(400);
    expect(res.json.mock.calls[0][0]).toMatchObject({
      code: 'invoice_identity_locked',
      error: expect.stringContaining('tenancyId, invoice_kind'),
    });
  });

  it('maps blocked edits to 409', async () => {
    const { mod } = await loadService();
    const { errorHandler } = await import('../../shared/middleware/error-handler.js');
    const res: any = { status: vi.fn(() => res), json: vi.fn(() => res) };

    errorHandler(new mod.InvoiceLockedError('locked', 'invoice_paid'), {} as any, res, vi.fn());

    expect(res.status).toHaveBeenCalledWith(409);
    expect(res.json).toHaveBeenCalledWith({ error: 'locked', code: 'invoice_paid' });
  });
});
