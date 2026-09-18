// modules/meter-readings/meter-readings.service.ts
import { query } from '@config/db';
import {
  createNotification,
  ensureLiveOpsSchema,
  notifyPropertyOwners,
} from '@modules/notifications/notify';
import { BillingService } from '@modules/billing/billing.service';

const billing = new BillingService();

function defaultBillingCycle(d = new Date()): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  return `${y}-${m}`;
}

function cycleBounds(cycle: string): { start: string; end: string; due: string } {
  const [y, m] = cycle.split('-').map(Number);
  const start = new Date(y, m - 1, 1);
  const end = new Date(y, m, 0);
  const due = new Date(y, m, 5);
  const iso = (d: Date) => d.toISOString().slice(0, 10);
  return { start: iso(start), end: iso(end), due: iso(due) };
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

  async listByUnit(unitId: string) {
    await ensureLiveOpsSchema();
    return query(
      `SELECT * FROM meter_readings
       WHERE unit_id = $1
       ORDER BY created_at DESC
       LIMIT 50`,
      [unitId],
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
    notifyTenantUserId?: string | null;
  }) {
    await ensureLiveOpsSchema();

    const cycle = input.billingCycle?.trim() || defaultBillingCycle();
    const prevRows = await query<{ meter_reading_value: string }>(
      `SELECT meter_reading_value FROM meter_readings
       WHERE unit_id = $1
       ORDER BY created_at DESC
       LIMIT 1`,
      [input.unitId],
    );
    const previous = prevRows[0]
      ? Number(prevRows[0].meter_reading_value)
      : null;

    if (previous != null && input.readingValue < previous) {
      throw new Error(
        `Reading (${input.readingValue}) cannot be less than previous (${previous}).`,
      );
    }

    let rate = input.ratePerUnit;
    if (rate == null) {
      const chargeTypes = await billing.listChargeTypes(input.propertyId);
      const electricity = chargeTypes.find((c: any) =>
        String(c.name).toLowerCase().includes('electric'),
      ) as any;
      rate = electricity ? Number(electricity.default_amount) || 8 : 8;
    }

    const units =
      previous == null ? 0 : Number((input.readingValue - previous).toFixed(3));
    const amount = Number((units * rate).toFixed(2));

    let tenancyId = input.tenancyId ?? null;
    let tenantUserId = input.notifyTenantUserId ?? null;
    if (!tenancyId || !tenantUserId) {
      const active = await query<{ id: string; user_id: string }>(
        `SELECT id, user_id FROM tenancies
         WHERE node_id = $1 AND property_id = $2 AND status = 'active'
         ORDER BY created_at DESC LIMIT 1`,
        [input.unitId, input.propertyId],
      );
      tenancyId = tenancyId ?? active[0]?.id ?? null;
      tenantUserId = tenantUserId ?? active[0]?.user_id ?? null;
    }

    let invoiceId: string | null = null;
    let lineItemId: string | null = null;

    if (tenancyId && amount > 0) {
      const bounds = cycleBounds(cycle);
      const existingInv = await query<{ id: string }>(
        `SELECT id FROM invoices
         WHERE tenancy_id = $1
           AND property_id = $2
           AND period_start = $3::date
           AND period_end = $4::date
           AND status IN ('pending', 'partial', 'overdue')
         ORDER BY created_at DESC
         LIMIT 1`,
        [tenancyId, input.propertyId, bounds.start, bounds.end],
      );

      const chargeTypes = await billing.listChargeTypes(input.propertyId);
      const electricity = chargeTypes.find((c: any) =>
        String(c.name).toLowerCase().includes('electric'),
      ) as any;
      const lineDesc = `Electricity (${cycle}): ${units} units @ ₹${rate}`;

      if (existingInv[0]) {
        invoiceId = existingInv[0].id;
        const [li] = await query<{ id: string }>(
          `INSERT INTO invoice_line_items (invoice_id, charge_type_id, description, amount)
           VALUES ($1, $2, $3, $4) RETURNING id`,
          [invoiceId, electricity?.id ?? null, lineDesc, amount],
        );
        lineItemId = li.id;
        await query(
          `UPDATE invoices
           SET total_amount = total_amount + $1, updated_at = now()
           WHERE id = $2`,
          [amount, invoiceId],
        );
      } else {
        const inv = await billing.createInvoice({
          tenancyId,
          propertyId: input.propertyId,
          periodStart: bounds.start,
          periodEnd: bounds.end,
          dueDate: bounds.due,
          lineItems: [
            {
              chargeTypeId: electricity?.id,
              description: lineDesc,
              amount,
            },
          ],
        });
        invoiceId = (inv as any).id;
        const lines = await query<{ id: string }>(
          `SELECT id FROM invoice_line_items WHERE invoice_id = $1 ORDER BY id DESC LIMIT 1`,
          [invoiceId],
        );
        lineItemId = lines[0]?.id ?? null;
      }
    }

    const [row] = await query<any>(
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
        rate,
        amount,
        input.meterImageUrl ?? null,
        cycle,
        input.submittedBy,
        invoiceId,
        lineItemId,
      ],
    );

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
            ? `${input.readingValue} units • ₹${amount} added to ${cycle} dues`
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

    if (tenantUserId && amount > 0) {
      await createNotification({
        userId: tenantUserId,
        propertyId: input.propertyId,
        type: 'meter_bill',
        title: 'Electricity charge added',
        body: `${units} units × ₹${rate} = ₹${amount} for ${cycle}`,
        data: {
          meter_reading_id: String(row.id),
          invoice_id: invoiceId,
          property_id: input.propertyId,
          route: '/tenant-home',
        },
      }).catch((e) => console.warn('[meter] tenant notify failed:', e));
    }

    return row;
  }
}
