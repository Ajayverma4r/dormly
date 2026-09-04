// modules/expenses/expense.service.ts
import { query } from '@config/db';

export class ExpenseService {
  async listByProperty(propertyId: string) {
    return query(
      `SELECT * FROM expenses
       WHERE property_id = $1
       ORDER BY expense_date DESC, created_at DESC`,
      [propertyId],
    );
  }

  async totalThisMonth(propertyId: string) {
    const [row] = await query<{ total: string }>(
      `SELECT COALESCE(SUM(amount), 0)::text AS total
       FROM expenses
       WHERE property_id = $1
         AND expense_date >= date_trunc('month', CURRENT_DATE)::date
         AND expense_date < (date_trunc('month', CURRENT_DATE) + interval '1 month')::date`,
      [propertyId],
    );
    return Number(row?.total ?? 0);
  }

  async create(
    propertyId: string,
    recordedBy: string,
    input: {
      title: string;
      amount: number;
      expenseDate?: string;
      category?: string;
    },
  ) {
    const category = input.category ?? 'other';
    const [row] = await query(
      `INSERT INTO expenses (
         property_id, category, description, amount, expense_date, recorded_by
       ) VALUES ($1, $2::expense_category, $3, $4, COALESCE($5::date, CURRENT_DATE), $6)
       RETURNING *`,
      [
        propertyId,
        category,
        input.title,
        input.amount,
        input.expenseDate ?? null,
        recordedBy,
      ],
    );
    return row;
  }
}
