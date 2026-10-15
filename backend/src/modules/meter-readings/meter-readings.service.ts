// modules/meter-readings/meter-readings.service.ts
import { query, withTransaction } from '@config/db';
import { ensureLiveOpsSchema, notifyPropertyOwners } from '@modules/notifications/notify';
import { assertMeterTarget, type TenantMeterScope } from './meter-access';
import {
  BillingService,
  billingSchemaCaps,
  ensureBillingSchema,
} from '@modules/billing/billing.service';
import {
  DUE_DAYS_AFTER_BILL,
  DEFAULT_PROPERTY_TIME_ZONE,
  calendarDateInTimeZone,
  hostelBillingTimeZone,
} from '@modules/billing/hostel-billing-cycle';

const billing = new BillingService();

function defaultBillingCycle(d = new Date()): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  return `${y}-${m}`;
}

/**
 * Days after a period ends in which a reading still closes that period:
 * from the bill date (period end + 1) through the default due date.
 */
export const READING_CLOSE_WINDOW_DAYS = 1 + DUE_DAYS_AFTER_BILL;

/**
 * The draft a new reading may join: the tenancy's unsent rent-cycle draft
 * whose anniversary period ended just before the reading date (within
 * READING_CLOSE_WINDOW_DAYS), for a tenancy living in the reading's unit.
 * Readings outside that window stay pending and are added when the next
 * cycle draft is generated.
 */
export function closingDraftSql(hasInvoiceKind: boolean): string {
  return `SELECT i.id, i.total_amount::text AS total_amount FROM invoices i
     JOIN tenancies t ON t.id = i.tenancy_id
     WHERE i.tenancy_id = $1
       AND i.property_id = $2
       AND t.node_id = $3
       AND i.sent_at IS NULL
       AND ${hasInvoiceKind ? `i.invoice_kind = 'cycle'` : `(i.is_auto_generated OR i.period_start <> i.period_end)`}
       AND $4::date > i.period_end
       AND $4::date <= i.period_end + $5::int
     ORDER BY i.period_start DESC
     LIMIT 1
     FOR UPDATE OF i`;
}

/** Largest value NUMERIC(14,3) can store. */
export const MAX_METER_READING = 99_999_999_999.999;

/** Largest value NUMERIC(12,2) can store: reading amount, line item and invoice total. */
export const MAX_MONEY_AMOUNT = 9_999_999_999.99;

/** Largest value NUMERIC(12,4) (meter_readings.rate_per_unit) can store. */
export const MAX_RATE_PER_UNIT = 99_999_999.9999;

export type MeterReadingErrorCode =
  | 'invalid_reading'
  | 'reading_below_previous'
  | 'invalid_rate'
  | 'amount_out_of_range';

/** A reading the server refuses; mapped to 400 with a stable code. */
export class MeterReadingValidationError extends Error {
  constructor(
    readonly code: MeterReadingErrorCode,
    message: string,
  ) {
    super(message);
    this.name = 'MeterReadingValidationError';
  }
}

export function assertValidReadingValue(value: number): void {
  if (!Number.isFinite(value) || value <= 0 || value > MAX_METER_READING) {
    throw new MeterReadingValidationError(
      'invalid_reading',
      'Reading must be a positive number.',
    );
  }
}

function amountOutOfRange(): MeterReadingValidationError {
  return new MeterReadingValidationError(
    'amount_out_of_range',
    'This reading would bill more than the allowed maximum. Check the reading and the rate.',
  );
}

/** Reading fields staff need to record and check readings; no rate, amount or invoice links. */
export const STAFF_METER_READING_FIELDS = [
  'id', 'property_id', 'unit_id', 'unit_name', 'tenancy_id',
  'meter_reading_value', 'previous_reading', 'units_consumed',
  'meter_image_url', 'billing_cycle', 'submitted_by', 'submitted_by_name', 'created_at',
] as const;

export function meterReadingForStaff(row: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const key of STAFF_METER_READING_FIELDS) {
    if (key in row) out[key] = row[key];
  }
  return out;
}

export class MeterReadingsService {
  async listByProperty(propertyId: string) {
    await ensureLiveOpsSchema();
    return query(
      `SELECT mr.*, n.name AS unit_name, u.name AS submitted_by_name
       FROM meter_readings mr
       JOIN hierarchy_nodes n ON n.id = mr.unit_id
       JOIN users u ON u.id = mr.submitted_by
       WHERE mr.property_id = $1
       ORDER BY mr.created_at DESC
       LIMIT 100`,
      [propertyId],
    );
  }

  /** A tenant's own readings: their tenancy, on their unit, in their property. */
  async listForTenancy(scope: TenantMeterScope) {
    await ensureLiveOpsSchema();
    return query(
      `SELECT * FROM meter_readings
       WHERE tenancy_id = $1 AND unit_id = $2 AND property_id = $3
       ORDER BY created_at DESC
       LIMIT 50`,
      [scope.tenancyId, scope.unitId, scope.propertyId],
    );
  }

  async submit(input: {
    propertyId: string;
    unitId: string;
    tenancyId?: string | null;
    readingValue: number;
    meterImageUrl?: string | null;
    billingCycle?: string;
    submittedBy: string;
    ratePerUnit?: number;
    notifyOwners?: boolean;
  }) {
    assertValidReadingValue(input.readingValue);
    await ensureLiveOpsSchema();
    await ensureBillingSchema();
    await assertMeterTarget(input.propertyId, input.unitId, input.tenancyId);

    const cycle = input.billingCycle?.trim() || defaultBillingCycle();

    let rate = input.ratePerUnit;
    if (rate == null) {
      const chargeTypes = await billing.listChargeTypes(input.propertyId);
      const electricity = chargeTypes.find((c: any) =>
        String(c.name).toLowerCase().includes('electric'),
      ) as any;
      rate = electricity ? Number(electricity.default_amount) || 8 : 8;
    }
    if (!Number.isFinite(rate) || Math.abs(rate) > MAX_RATE_PER_UNIT) {
      throw new MeterReadingValidationError('invalid_rate', 'Rate per unit is out of range.');
    }
    const ratePerUnit = rate;

    let tenancyId = input.tenancyId ?? null;
    if (!tenancyId) {
      const active = await query<{ id: string }>(
        `SELECT id FROM tenancies
         WHERE node_id = $1 AND property_id = $2 AND status = 'active'
         ORDER BY created_at DESC LIMIT 1`,
        [input.unitId, input.propertyId],
      );
      tenancyId = active[0]?.id ?? null;
    }

    const chargeTypes = await billing.listChargeTypes(input.propertyId);
    const electricity = chargeTypes.find((c: any) =>
      String(c.name).toLowerCase().includes('electric'),
    ) as any;

    const caps = await billingSchemaCaps();
    const [property] = await query<{ timezone: string | null }>(
      `SELECT timezone FROM properties WHERE id = $1`,
      [input.propertyId],
    );
    let readingDate: string;
    try {
      readingDate = calendarDateInTimeZone(new Date(), hostelBillingTimeZone(property?.timezone));
    } catch {
      readingDate = calendarDateInTimeZone(new Date(), DEFAULT_PROPERTY_TIME_ZONE);
    }

    const { row, invoiceId, amount } = await withTransaction(async (q) => {
      let invoiceId: string | null = null;
      let lineItemId: string | null = null;

      // Serialise readings per unit: the previous value is read under the
      // unit's row lock, so two concurrent submits cannot both pass the check.
      // NO KEY UPDATE still conflicts with itself and with node deletes, but not
      // with the KEY SHARE locks taken by inserts that reference this node.
      await q(`SELECT id FROM hierarchy_nodes WHERE id = $1 FOR NO KEY UPDATE`, [input.unitId]);
      const prevRows = await q<{ meter_reading_value: string }>(
        `SELECT meter_reading_value FROM meter_readings
         WHERE unit_id = $1
         ORDER BY created_at DESC
         LIMIT 1`,
        [input.unitId],
      );
      const previous = prevRows[0] ? Number(prevRows[0].meter_reading_value) : null;
      if (previous != null && input.readingValue < previous) {
        throw new MeterReadingValidationError(
          'reading_below_previous',
          `Reading cannot be less than the previous reading (${previous}).`,
        );
      }

      const units =
        previous == null ? 0 : Number((input.readingValue - previous).toFixed(3));
      const amount = Number((units * ratePerUnit).toFixed(2));
      if (!Number.isFinite(amount) || Math.abs(amount) > MAX_MONEY_AMOUNT) {
        throw amountOutOfRange();
      }
      const lineDesc = `Electricity (${cycle}): ${units} units @ ₹${ratePerUnit}`;

      if (tenancyId && amount > 0) {
        // Only an unsent draft may absorb the reading; a sent invoice is an
        // issued bill. The row lock re-checks sent_at if a send races this.
        const [draft] = await q<{ id: string; total_amount: string }>(
          closingDraftSql(caps.invoiceKind),
          [tenancyId, input.propertyId, input.unitId, readingDate, READING_CLOSE_WINDOW_DAYS],
        );

        if (draft && Number((Number(draft.total_amount) + amount).toFixed(2)) > MAX_MONEY_AMOUNT) {
          throw amountOutOfRange();
        }

        if (draft) {
          invoiceId = draft.id;
          const [li] = await q<{ id: string }>(
            `INSERT INTO invoice_line_items
               (invoice_id, charge_type_id, description, amount, charge_kind)
             VALUES ($1, $2, $3, $4, 'electricity') RETURNING id`,
            [invoiceId, electricity?.id ?? null, lineDesc, amount],
          );
          lineItemId = li.id;
          await q(
            `UPDATE invoices
             SET total_amount = total_amount + $1, updated_at = now()
             WHERE id = $2`,
            [amount, invoiceId],
          );
        }
        // Otherwise leave invoice_id NULL — picked up by addPendingChargesToInvoice
        // when the next invoice is generated or created.
      }

      const [row] = await q<any>(
        `INSERT INTO meter_readings (
           property_id, unit_id, tenancy_id, meter_reading_value, previous_reading,
           units_consumed, rate_per_unit, amount, meter_image_url, billing_cycle,
           submitted_by, invoice_id, invoice_line_item_id
         ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)
         RETURNING *`,
        [
          input.propertyId,
          input.unitId,
          tenancyId,
          input.readingValue,
          previous,
          units,
          ratePerUnit,
          amount,
          input.meterImageUrl ?? null,
          cycle,
          input.submittedBy,
          invoiceId,
          lineItemId,
        ],
      );
      return { row, invoiceId, amount };
    });

    const unitRows = await query<{ name: string }>(
      `SELECT name FROM hierarchy_nodes WHERE id = $1`,
      [input.unitId],
    );
    const unitName = unitRows[0]?.name ?? 'Unit';

    if (input.notifyOwners !== false) {
      await notifyPropertyOwners({
        propertyId: input.propertyId,
        type: 'meter_reading',
        title: `Meter reading: ${unitName}`,
        body:
          amount > 0
            ? invoiceId
              ? `${input.readingValue} units • ₹${amount} added to the draft invoice — review and send it`
              : `${input.readingValue} units • ₹${amount} pending for next invoice`
            : `New reading ${input.readingValue} recorded for ${cycle}`,
        data: {
          meter_reading_id: String(row.id),
          unit_id: input.unitId,
          property_id: input.propertyId,
          propertyId: input.propertyId,
          invoice_id: invoiceId,
          route: '/payments',
        },
      }).catch((e) => console.warn('[meter] owner notify failed:', e));
    }

    // The tenant hears about the charge only when the owner sends the invoice.
    return row;
  }
}
