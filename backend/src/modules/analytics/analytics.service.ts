// modules/analytics/analytics.service.ts
//
// Occupancy is computed generically: any hierarchy_level with
// supports_occupancy = true defines what "a unit" means for THIS property
// (a Bed for a hostel, a Flat for an apartment, a Rack space for a
// warehouse...). Nothing here is hardcoded to a specific level name.

import { query } from '@config/db';

export class AnalyticsService {
  async getPropertyAnalytics(propertyId: string) {
    const [{ total_revenue }] = await query<{ total_revenue: string }>(
      `SELECT COALESCE(SUM(p.amount), 0)::text AS total_revenue
       FROM payments p
       JOIN invoices i ON i.id = p.invoice_id
       WHERE i.property_id = $1`,
      [propertyId],
    );

    const [{ pending_rent }] = await query<{ pending_rent: string }>(
      `SELECT COALESCE(SUM(
         i.total_amount - COALESCE((SELECT SUM(amount) FROM payments WHERE invoice_id = i.id), 0)
       ), 0)::text AS pending_rent
       FROM invoices i
       WHERE i.property_id = $1 AND i.status != 'paid'`,
      [propertyId],
    );

    const [{ overdue_count }] = await query<{ overdue_count: string }>(
      `SELECT COUNT(*)::text AS overdue_count FROM invoices WHERE property_id = $1 AND status = 'overdue'`,
      [propertyId],
    );

    const [{ total_units, occupied_units }] = await query<{ total_units: string; occupied_units: string }>(
      `SELECT
         COUNT(DISTINCT n.id)::text AS total_units,
         COUNT(DISTINCT CASE WHEN t.id IS NOT NULL THEN n.id END)::text AS occupied_units
       FROM hierarchy_nodes n
       JOIN hierarchy_levels l ON l.id = n.level_id
       LEFT JOIN tenancies t ON t.node_id = n.id AND t.status = 'active'
       WHERE n.property_id = $1 AND n.is_active = true AND l.supports_occupancy = true`,
      [propertyId],
    );

    const recentPayments = await query<any>(
      `SELECT p.amount, p.paid_at, p.method, t.full_name, n.name AS node_name
       FROM payments p
       JOIN invoices i ON i.id = p.invoice_id
       JOIN tenancies t ON t.id = i.tenancy_id
       JOIN hierarchy_nodes n ON n.id = t.node_id
       WHERE i.property_id = $1
       ORDER BY p.paid_at DESC
       LIMIT 5`,
      [propertyId],
    );

    const totalUnits = Number(total_units);
    const occupiedUnits = Number(occupied_units);

    return {
      totalRevenue: Number(total_revenue),
      pendingRent: Number(pending_rent),
      overdueCount: Number(overdue_count),
      totalUnits,
      occupiedUnits,
      vacantUnits: totalUnits - occupiedUnits,
      occupancyRate: totalUnits > 0 ? Math.round((occupiedUnits / totalUnits) * 100) : 0,
      recentPayments,
    };
  }
  async getOrganizationAnalytics(organizationId: string) {
    const [{ total_properties }] = await query<{ total_properties: string }>(
      `SELECT COUNT(*)::text AS total_properties FROM properties WHERE organization_id = $1`,
      [organizationId],
    );

    const [{ total_revenue }] = await query<{ total_revenue: string }>(
      `SELECT COALESCE(SUM(p.amount), 0)::text AS total_revenue
       FROM payments p
       JOIN invoices i ON i.id = p.invoice_id
       JOIN properties pr ON pr.id = i.property_id
       WHERE pr.organization_id = $1`,
      [organizationId],
    );

    const [{ total_units, occupied_units }] = await query<{ total_units: string; occupied_units: string }>(
      `SELECT
         COUNT(DISTINCT n.id)::text AS total_units,
         COUNT(DISTINCT CASE WHEN t.id IS NOT NULL THEN n.id END)::text AS occupied_units
       FROM hierarchy_nodes n
       JOIN hierarchy_levels l ON l.id = n.level_id
       JOIN properties pr ON pr.id = n.property_id
       LEFT JOIN tenancies t ON t.node_id = n.id AND t.status = 'active'
       WHERE pr.organization_id = $1 AND n.is_active = true AND l.supports_occupancy = true`,
      [organizationId],
    );

    const [{ total_residents }] = await query<{ total_residents: string }>(
      `SELECT COUNT(*)::text AS total_residents
       FROM tenancies t
       JOIN properties pr ON pr.id = t.property_id
       WHERE pr.organization_id = $1 AND t.status = 'active'`,
      [organizationId],
    );

    const totalUnits = Number(total_units);
    const occupiedUnits = Number(occupied_units);

    return {
      totalProperties: Number(total_properties),
      totalRevenue: Number(total_revenue),
      totalResidents: Number(total_residents),
      occupancyRate: totalUnits > 0 ? Math.round((occupiedUnits / totalUnits) * 100) : 0,
    };
  }
  async getRecentActivity(propertyId: string) {
    const rows = await query<any>(
      `(
        SELECT 'resident' AS type, t.created_at AS ts,
               t.full_name AS title, n.name AS subtitle
        FROM tenancies t
        JOIN hierarchy_nodes n ON n.id = t.node_id
        WHERE t.property_id = $1
      )
      UNION ALL
      (
        SELECT 'payment' AS type, p.paid_at AS ts,
               t.full_name AS title, ('₹' || p.amount) AS subtitle
        FROM payments p
        JOIN invoices i ON i.id = p.invoice_id
        JOIN tenancies t ON t.id = i.tenancy_id
        WHERE i.property_id = $1
      )
      ORDER BY ts DESC
      LIMIT 10`,
      [propertyId],
    );
    return rows;
  }
}