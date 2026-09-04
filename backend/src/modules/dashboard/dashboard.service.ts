// modules/dashboard/dashboard.service.ts
//
// Aggregates property-dashboard metrics in a small number of round-trips.
// Occupancy uses hierarchy_levels.supports_occupancy (same rule as analytics).
//
// Each section falls back to legacy queries when migration 013 columns/tables
// are not yet present on the database (e.g. production lagging behind dev).

import { query } from '@config/db';

export interface DashboardDefaulter {
  tenancy_id: string;
  name: string;
  room: string;
  unit_details: string;
  amount_due: number;
  invoice_id: string;
}

export interface PropertyDashboard {
  hero_stats: {
    total_units: number;
    occupied_units: number;
    available_units: number;
    expected_monthly_rent: number;
  };
  overview: {
    total_active_tenants: number;
    open_complaints: number;
    total_expenses: number;
    rent_received: number;
    rent_pending: number;
    billed_this_month: number;
    tenants_with_dues: number;
  };
  actionable_insights: {
    defaulters: DashboardDefaulter[];
    pending_kyc_count: number;
    upcoming_vacancies: number;
  };
}

export class DashboardService {
  async getPropertyDashboard(propertyId: string): Promise<PropertyDashboard> {
    const [hero_stats, overview, actionable_insights] = await Promise.all([
      this.getHeroStats(propertyId),
      this.getOverview(propertyId),
      this.getActionableInsights(propertyId),
    ]);

    return { hero_stats, overview, actionable_insights };
  }

  private async getHeroStats(propertyId: string) {
    try {
      return await this.getHeroStatsWithMonthlyRent(propertyId);
    } catch (err) {
      console.warn('[dashboard] hero_stats v2 failed, using legacy query:', err);
      return this.getHeroStatsLegacy(propertyId);
    }
  }

  private async getHeroStatsWithMonthlyRent(propertyId: string) {
    const [occupancy] = await query<{
      total_units: string;
      occupied_units: string;
      expected_monthly_rent: string;
    }>(
      `SELECT
         COUNT(DISTINCT n.id)::text AS total_units,
         COUNT(DISTINCT CASE WHEN t.id IS NOT NULL THEN n.id END)::text AS occupied_units,
         COALESCE((
           SELECT SUM(COALESCE(t2.monthly_rent, 0))
           FROM tenancies t2
           WHERE t2.property_id = $1 AND t2.status = 'active'
         ), 0)::text AS expected_monthly_rent
       FROM hierarchy_nodes n
       JOIN hierarchy_levels l ON l.id = n.level_id
       LEFT JOIN tenancies t ON t.node_id = n.id AND t.status = 'active'
       WHERE n.property_id = $1 AND n.is_active = true AND l.supports_occupancy = true`,
      [propertyId],
    );

    return this.formatHeroStats(occupancy);
  }

  private async getHeroStatsLegacy(propertyId: string) {
    const [occupancy] = await query<{
      total_units: string;
      occupied_units: string;
      expected_monthly_rent: string;
    }>(
      `SELECT
         COUNT(DISTINCT n.id)::text AS total_units,
         COUNT(DISTINCT CASE WHEN t.id IS NOT NULL THEN n.id END)::text AS occupied_units,
         COALESCE((
           SELECT SUM(i.total_amount)
           FROM invoices i
           WHERE i.property_id = $1
             AND i.period_start < (date_trunc('month', CURRENT_DATE) + interval '1 month')::date
             AND i.period_end >= date_trunc('month', CURRENT_DATE)::date
         ), 0)::text AS expected_monthly_rent
       FROM hierarchy_nodes n
       JOIN hierarchy_levels l ON l.id = n.level_id
       LEFT JOIN tenancies t ON t.node_id = n.id AND t.status = 'active'
       WHERE n.property_id = $1 AND n.is_active = true AND l.supports_occupancy = true`,
      [propertyId],
    );

    return this.formatHeroStats(occupancy);
  }

  private formatHeroStats(occupancy?: {
    total_units: string;
    occupied_units: string;
    expected_monthly_rent: string;
  }) {
    const totalUnits = Number(occupancy?.total_units ?? 0);
    const occupiedUnits = Number(occupancy?.occupied_units ?? 0);

    return {
      total_units: totalUnits,
      occupied_units: occupiedUnits,
      available_units: Math.max(0, totalUnits - occupiedUnits),
      expected_monthly_rent: Number(occupancy?.expected_monthly_rent ?? 0),
    };
  }

  private async getOverview(propertyId: string) {
    try {
      return await this.getOverviewWithExpenses(propertyId);
    } catch (err) {
      console.warn('[dashboard] overview v2 failed, using legacy query:', err);
      return this.getOverviewLegacy(propertyId);
    }
  }

  private async getOverviewWithExpenses(propertyId: string) {
    const [row] = await query<{
      total_active_tenants: string;
      open_complaints: string;
      total_expenses: string;
      rent_received: string;
      rent_pending: string;
      billed_this_month: string;
      tenants_with_dues: string;
    }>(
      `WITH month_bounds AS (
         SELECT
           date_trunc('month', CURRENT_DATE)::date AS month_start,
           (date_trunc('month', CURRENT_DATE) + interval '1 month')::date AS month_end
       ),
       open_balances AS (
         SELECT
           i.tenancy_id,
           i.total_amount - COALESCE((
             SELECT SUM(p.amount) FROM payments p WHERE p.invoice_id = i.id
           ), 0) AS balance
         FROM invoices i
         WHERE i.property_id = $1
           AND i.status <> 'paid'
       )
       SELECT
         (SELECT COUNT(*)::text FROM tenancies
          WHERE property_id = $1 AND status = 'active') AS total_active_tenants,
         (SELECT COUNT(*)::text FROM complaints
          WHERE property_id = $1 AND status IN ('open', 'in_progress')) AS open_complaints,
         (SELECT COALESCE(SUM(e.amount), 0)::text
          FROM expenses e, month_bounds mb
          WHERE e.property_id = $1
            AND e.expense_date >= mb.month_start
            AND e.expense_date < mb.month_end) AS total_expenses,
         (SELECT COALESCE(SUM(p.amount), 0)::text
          FROM payments p
          JOIN invoices i ON i.id = p.invoice_id, month_bounds mb
          WHERE i.property_id = $1
            AND p.paid_at >= mb.month_start::timestamptz
            AND p.paid_at < mb.month_end::timestamptz) AS rent_received,
         (SELECT COALESCE(SUM(balance), 0)::text
          FROM open_balances WHERE balance > 0) AS rent_pending,
         (SELECT COALESCE(SUM(i.total_amount), 0)::text
          FROM invoices i, month_bounds mb
          WHERE i.property_id = $1
            AND i.created_at >= mb.month_start::timestamptz
            AND i.created_at < mb.month_end::timestamptz) AS billed_this_month,
         (SELECT COUNT(DISTINCT tenancy_id)::text
          FROM open_balances WHERE balance > 0.009) AS tenants_with_dues`,
      [propertyId],
    );

    return this.formatOverview(row);
  }

  private async getOverviewLegacy(propertyId: string) {
    const [row] = await query<{
      total_active_tenants: string;
      open_complaints: string;
      rent_received: string;
      rent_pending: string;
      billed_this_month: string;
      tenants_with_dues: string;
    }>(
      `WITH month_bounds AS (
         SELECT
           date_trunc('month', CURRENT_DATE)::date AS month_start,
           (date_trunc('month', CURRENT_DATE) + interval '1 month')::date AS month_end
       ),
       open_balances AS (
         SELECT
           i.tenancy_id,
           i.total_amount - COALESCE((
             SELECT SUM(p.amount) FROM payments p WHERE p.invoice_id = i.id
           ), 0) AS balance
         FROM invoices i
         WHERE i.property_id = $1
           AND i.status <> 'paid'
       )
       SELECT
         (SELECT COUNT(*)::text FROM tenancies
          WHERE property_id = $1 AND status = 'active') AS total_active_tenants,
         (SELECT COUNT(*)::text FROM complaints
          WHERE property_id = $1 AND status IN ('open', 'in_progress')) AS open_complaints,
         (SELECT COALESCE(SUM(p.amount), 0)::text
          FROM payments p
          JOIN invoices i ON i.id = p.invoice_id, month_bounds mb
          WHERE i.property_id = $1
            AND p.paid_at >= mb.month_start::timestamptz
            AND p.paid_at < mb.month_end::timestamptz) AS rent_received,
         (SELECT COALESCE(SUM(balance), 0)::text
          FROM open_balances WHERE balance > 0) AS rent_pending,
         (SELECT COALESCE(SUM(i.total_amount), 0)::text
          FROM invoices i, month_bounds mb
          WHERE i.property_id = $1
            AND i.created_at >= mb.month_start::timestamptz
            AND i.created_at < mb.month_end::timestamptz) AS billed_this_month,
         (SELECT COUNT(DISTINCT tenancy_id)::text
          FROM open_balances WHERE balance > 0.009) AS tenants_with_dues`,
      [propertyId],
    );

    return {
      ...this.formatOverview(row),
      total_expenses: 0,
    };
  }

  private formatOverview(row?: {
    total_active_tenants: string;
    open_complaints: string;
    total_expenses?: string;
    rent_received: string;
    rent_pending: string;
    billed_this_month?: string;
    tenants_with_dues?: string;
  }) {
    return {
      total_active_tenants: Number(row?.total_active_tenants ?? 0),
      open_complaints: Number(row?.open_complaints ?? 0),
      total_expenses: Number(row?.total_expenses ?? 0),
      rent_received: Number(row?.rent_received ?? 0),
      rent_pending: Number(row?.rent_pending ?? 0),
      billed_this_month: Number(row?.billed_this_month ?? 0),
      tenants_with_dues: Number(row?.tenants_with_dues ?? 0),
    };
  }

  private async getActionableInsights(propertyId: string) {
    const [counts, defaulters] = await Promise.all([
      this.getInsightCounts(propertyId),
      this.getDefaulters(propertyId).catch((err) => {
        console.warn('[dashboard] defaulters query failed:', err);
        return [] as DashboardDefaulter[];
      }),
    ]);

    return {
      defaulters,
      pending_kyc_count: counts.pending_kyc_count,
      upcoming_vacancies: counts.upcoming_vacancies,
    };
  }

  private async getInsightCounts(propertyId: string) {
    try {
      return await this.getInsightCountsV2(propertyId);
    } catch (err) {
      console.warn('[dashboard] insights v2 failed, using legacy query:', err);
      return this.getInsightCountsLegacy(propertyId);
    }
  }

  private async getInsightCountsV2(propertyId: string) {
    const [row] = await query<{
      pending_kyc_count: string;
      upcoming_vacancies: string;
    }>(
      `SELECT
         (SELECT COUNT(*)::text FROM tenancies
          WHERE property_id = $1
            AND status = 'active'
            AND kyc_status IN ('pending', 'submitted')) AS pending_kyc_count,
         (SELECT COUNT(*)::text FROM tenancies
          WHERE property_id = $1
            AND status = 'active'
            AND planned_move_out_at IS NOT NULL
            AND planned_move_out_at >= now()
            AND planned_move_out_at <= now() + interval '30 days') AS upcoming_vacancies`,
      [propertyId],
    );

    return {
      pending_kyc_count: Number(row?.pending_kyc_count ?? 0),
      upcoming_vacancies: Number(row?.upcoming_vacancies ?? 0),
    };
  }

  /** Before kyc_status / planned_move_out_at columns exist. */
  private async getInsightCountsLegacy(propertyId: string) {
    const [row] = await query<{
      pending_kyc_count: string;
      upcoming_vacancies: string;
    }>(
      `SELECT
         (SELECT COUNT(*)::text FROM tenancies
          WHERE property_id = $1
            AND status = 'active'
            AND (
              aadhaar_number IS NULL
              OR TRIM(aadhaar_number) = ''
              OR profile_photo_url IS NULL
              OR TRIM(profile_photo_url) = ''
            )) AS pending_kyc_count,
         (SELECT COUNT(*)::text FROM tenancies
          WHERE property_id = $1
            AND status = 'active'
            AND move_out_at IS NOT NULL
            AND move_out_at >= now()
            AND move_out_at <= now() + interval '30 days') AS upcoming_vacancies`,
      [propertyId],
    );

    return {
      pending_kyc_count: Number(row?.pending_kyc_count ?? 0),
      upcoming_vacancies: Number(row?.upcoming_vacancies ?? 0),
    };
  }

  private async getDefaulters(propertyId: string): Promise<DashboardDefaulter[]> {
    const rows = await query<{
      tenancy_id: string;
      name: string;
      room: string;
      node_code: string | null;
      amount_due: string;
      invoice_id: string;
    }>(
      `WITH overdue_invoices AS (
         SELECT
           i.id AS invoice_id,
           i.tenancy_id,
           i.due_date,
           i.total_amount - COALESCE((
             SELECT SUM(p.amount) FROM payments p WHERE p.invoice_id = i.id
           ), 0) AS balance
         FROM invoices i
         WHERE i.property_id = $1
           AND i.status IN ('overdue', 'pending', 'partial')
           AND i.due_date < CURRENT_DATE
       ),
       tenant_balances AS (
         SELECT
           oi.tenancy_id,
           SUM(oi.balance) AS amount_due,
           (array_agg(oi.invoice_id ORDER BY oi.due_date ASC, oi.balance DESC))[1] AS invoice_id
         FROM overdue_invoices oi
         WHERE oi.balance > 0
         GROUP BY oi.tenancy_id
       )
       SELECT
         t.id AS tenancy_id,
         t.full_name AS name,
         n.name AS room,
         n.code AS node_code,
         tb.amount_due::text,
         tb.invoice_id::text
       FROM tenant_balances tb
       JOIN tenancies t ON t.id = tb.tenancy_id
       JOIN hierarchy_nodes n ON n.id = t.node_id
       ORDER BY tb.amount_due DESC
       LIMIT 10`,
      [propertyId],
    );

    return rows.map((r) => ({
      tenancy_id: r.tenancy_id,
      name: r.name,
      room: r.room,
      unit_details: r.node_code ? `${r.node_code} · ${r.room}` : r.room,
      amount_due: Number(r.amount_due),
      invoice_id: r.invoice_id,
    }));
  }
}
