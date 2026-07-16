// modules/billing/billing.service.ts
import { query } from '@config/db';

interface LineItemInput {
  chargeTypeId?: string;
  description: string;
  amount: number;
}

interface CreateInvoiceInput {
  tenancyId: string;
  propertyId: string;
  periodStart: string;
  periodEnd: string;
  dueDate: string;
  lineItems: LineItemInput[];
}

export class BillingService {
  // ---- Charge Types ----

  async listChargeTypes(propertyId: string) {
    return query(
      `SELECT * FROM charge_types WHERE property_id = $1 AND is_active = true ORDER BY order_index`,
      [propertyId],
    );
  }

  async createChargeType(propertyId: string, name: string, defaultAmount: number, isRecurring: boolean) {
    const existing = await query<{ count: string }>(
      `SELECT COUNT(*)::text AS count FROM charge_types WHERE property_id = $1`,
      [propertyId],
    );
    const [row] = await query(
      `INSERT INTO charge_types (property_id, name, default_amount, is_recurring, order_index)
       VALUES ($1,$2,$3,$4,$5) RETURNING *`,
      [propertyId, name, defaultAmount, isRecurring, Number(existing[0].count)],
    );
    return row;
  }

  async deleteChargeType(chargeTypeId: string) {
    // Soft delete — invoices already referencing this charge type keep working.
    await query(`UPDATE charge_types SET is_active = false WHERE id = $1`, [chargeTypeId]);
  }

  // ---- Invoices ----

  async createInvoice(input: CreateInvoiceInput) {
    const totalAmount = input.lineItems.reduce((sum, li) => sum + li.amount, 0);
    const isPastDue = new Date(input.dueDate) < new Date();

    const [invoice] = await query<{ id: string }>(
      `INSERT INTO invoices (tenancy_id, property_id, period_start, period_end, due_date, total_amount, status)
       VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING *`,
      [
        input.tenancyId, input.propertyId, input.periodStart, input.periodEnd,
        input.dueDate, totalAmount, isPastDue ? 'overdue' : 'pending',
      ],
    );

    for (const li of input.lineItems) {
      await query(
        `INSERT INTO invoice_line_items (invoice_id, charge_type_id, description, amount)
         VALUES ($1,$2,$3,$4)`,
        [(invoice as any).id, li.chargeTypeId ?? null, li.description, li.amount],
      );
    }

    return this.getById((invoice as any).id);
  }

  async getById(invoiceId: string) {
    const [invoice] = await query<any>(`SELECT * FROM invoices WHERE id = $1`, [invoiceId]);
    if (!invoice) return null;
    const lineItems = await query(`SELECT * FROM invoice_line_items WHERE invoice_id = $1`, [invoiceId]);
    const payments = await query(`SELECT * FROM payments WHERE invoice_id = $1 ORDER BY paid_at DESC`, [invoiceId]);
    return { ...invoice, lineItems, payments };
  }

  async listByProperty(propertyId: string) {
    return query(
      `SELECT i.*, t.full_name, u.phone, n.name AS node_name,
              COALESCE((SELECT SUM(amount) FROM payments WHERE invoice_id = i.id), 0) AS paid_amount
       FROM invoices i
       JOIN tenancies t ON t.id = i.tenancy_id
       JOIN users u ON u.id = t.user_id
       JOIN hierarchy_nodes n ON n.id = t.node_id
       WHERE i.property_id = $1
       ORDER BY i.due_date DESC`,
      [propertyId],
    );
  }

  async listByTenancy(tenancyId: string) {
    return query(
      `SELECT i.*,
              COALESCE((SELECT SUM(amount) FROM payments WHERE invoice_id = i.id), 0) AS paid_amount
       FROM invoices i
       WHERE i.tenancy_id = $1
       ORDER BY i.due_date DESC`,
      [tenancyId],
    );
  }

  async recordPayment(invoiceId: string, amount: number, method: string, note: string | undefined, recordedBy: string) {
    await query(
      `INSERT INTO payments (invoice_id, amount, method, note, recorded_by) VALUES ($1,$2,$3,$4,$5)`,
      [invoiceId, amount, method, note ?? null, recordedBy],
    );
    await this.recomputeStatus(invoiceId);
    return this.getById(invoiceId);
  }

  private async recomputeStatus(invoiceId: string) {
    const [invoice] = await query<any>(`SELECT * FROM invoices WHERE id = $1`, [invoiceId]);
    const [{ paid }] = await query<{ paid: string }>(
      `SELECT COALESCE(SUM(amount), 0)::text AS paid FROM payments WHERE invoice_id = $1`,
      [invoiceId],
    );
    const paidAmount = Number(paid);
    const total = Number(invoice.total_amount);
    let status: string;
    if (paidAmount >= total) status = 'paid';
    else if (paidAmount > 0) status = 'partial';
    else if (new Date(invoice.due_date) < new Date()) status = 'overdue';
    else status = 'pending';

    await query(`UPDATE invoices SET status = $1, updated_at = now() WHERE id = $2`, [status, invoiceId]);
  }

  // ---- Reminders (console-logged for now; swap for real SMS/Push/WhatsApp/Email later) ----

  async sendReminder(invoiceId: string) {
    const invoice = await this.getById(invoiceId);
    if (!invoice) throw new Error('Invoice not found');

    const [tenancy] = await query<any>(
      `SELECT t.user_id, t.full_name, u.phone
       FROM tenancies t JOIN users u ON u.id = t.user_id
       WHERE t.id = $1`,
      [(invoice as any).tenancy_id],
    );

    const paidAmount = Number((invoice as any).paid_amount ?? 0);
    const pending = Number((invoice as any).total_amount) - paidAmount;
    const title = 'Rent Reminder';
    const body = `Hi ${tenancy.full_name}, your payment of ₹${pending} is due on ${
      new Date((invoice as any).due_date).toLocaleDateString()
    }. Please pay as soon as possible.`;

    await query(
      `INSERT INTO notifications (user_id, property_id, type, title, body) VALUES ($1,$2,$3,$4,$5)`,
      [tenancy.user_id, (invoice as any).property_id, 'rent_reminder', title, body],
    );

    // eslint-disable-next-line no-console
    console.log(`[REMINDER] -> ${tenancy.phone}: ${title} — ${body}`);
    return { sent: true };
  }
}