// modules/mess-menu/mess-menu.service.ts
import { query } from '@config/db';
import { ensureLiveOpsSchema } from '@modules/notifications/notify';

const EMPTY_WEEK = [1, 2, 3, 4, 5, 6, 7].map((d) => ({
  day_of_week: d,
  breakfast: '',
  lunch: '',
  dinner: '',
}));

export class MessMenuService {
  async listByProperty(propertyId: string) {
    await ensureLiveOpsSchema();
    const rows = await query<any>(
      `SELECT * FROM mess_menus WHERE property_id = $1 ORDER BY day_of_week`,
      [propertyId],
    );
    if (!rows.length) return EMPTY_WEEK.map((d) => ({ ...d, property_id: propertyId }));

    const byDay = new Map(rows.map((r) => [Number(r.day_of_week), r]));
    return EMPTY_WEEK.map((d) => {
      const existing = byDay.get(d.day_of_week);
      return (
        existing ?? {
          ...d,
          property_id: propertyId,
        }
      );
    });
  }

  async upsertDay(
    propertyId: string,
    dayOfWeek: number,
    meals: { breakfast: string; lunch: string; dinner: string },
    updatedBy: string,
  ) {
    await ensureLiveOpsSchema();
    if (dayOfWeek < 1 || dayOfWeek > 7) {
      throw new Error('day_of_week must be 1 (Mon) through 7 (Sun).');
    }
    const [row] = await query(
      `INSERT INTO mess_menus (property_id, day_of_week, breakfast, lunch, dinner, updated_by)
       VALUES ($1, $2, $3, $4, $5, $6)
       ON CONFLICT (property_id, day_of_week)
       DO UPDATE SET
         breakfast = EXCLUDED.breakfast,
         lunch = EXCLUDED.lunch,
         dinner = EXCLUDED.dinner,
         updated_by = EXCLUDED.updated_by,
         updated_at = now()
       RETURNING *`,
      [
        propertyId,
        dayOfWeek,
        meals.breakfast.trim(),
        meals.lunch.trim(),
        meals.dinner.trim(),
        updatedBy,
      ],
    );
    return row;
  }

  async upsertWeek(
    propertyId: string,
    days: Array<{
      dayOfWeek: number;
      breakfast: string;
      lunch: string;
      dinner: string;
    }>,
    updatedBy: string,
  ) {
    const results = [];
    for (const day of days) {
      results.push(
        await this.upsertDay(
          propertyId,
          day.dayOfWeek,
          {
            breakfast: day.breakfast,
            lunch: day.lunch,
            dinner: day.dinner,
          },
          updatedBy,
        ),
      );
    }
    return results;
  }
}
