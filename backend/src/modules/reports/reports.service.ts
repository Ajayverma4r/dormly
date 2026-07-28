// modules/reports/reports.service.ts
import { query } from '@config/db';

export class ReportsService {
  async getRentCollectionRows(propertyId: string, startDate: string, endDate: string) {
    return query<any>(
      `SELECT t.full_name, u.phone, n.name AS node_name,
              i.period_start, i.period_end, i.due_date, i.status,
              i.total_amount,
              COALESCE((SELECT SUM(amount) FROM payments WHERE invoice_id = i.id), 0) AS paid_amount
       FROM invoices i
       JOIN tenancies t ON t.id = i.tenancy_id
       JOIN users u ON u.id = t.user_id
       JOIN hierarchy_nodes n ON n.id = t.node_id
       WHERE i.property_id = $1 AND i.due_date BETWEEN $2 AND $3
       ORDER BY i.due_date`,
      [propertyId, startDate, endDate],
    );
  }

  async getOccupancyRows(propertyId: string) {
    return query<any>(
      `SELECT l.display_name AS level_name, n.name AS node_name,
              t.full_name, u.phone, t.move_in_at,
              CASE WHEN t.id IS NOT NULL THEN 'Occupied' ELSE 'Vacant' END AS occupancy_status
       FROM hierarchy_nodes n
       JOIN hierarchy_levels l ON l.id = n.level_id
       LEFT JOIN tenancies t ON t.node_id = n.id AND t.status = 'active'
       LEFT JOIN users u ON u.id = t.user_id
       WHERE n.property_id = $1 AND n.is_active = true AND l.supports_occupancy = true
       ORDER BY l.order_index, n.name`,
      [propertyId],
    );
  }
}