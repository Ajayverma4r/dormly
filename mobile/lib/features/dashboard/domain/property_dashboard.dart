// features/dashboard/domain/property_dashboard.dart

class PropertyDashboard {
  final HeroStats heroStats;
  final DashboardOverview overview;
  final ActionableInsights actionableInsights;

  const PropertyDashboard({
    required this.heroStats,
    required this.overview,
    required this.actionableInsights,
  });

  factory PropertyDashboard.fromJson(Map<String, dynamic> json) {
    return PropertyDashboard(
      heroStats: HeroStats.fromJson(_section(json, 'hero_stats', 'heroStats')),
      overview: DashboardOverview.fromJson(
        _section(json, 'overview', 'overview'),
      ),
      actionableInsights: ActionableInsights.fromJson(
        _section(json, 'actionable_insights', 'actionableInsights'),
      ),
    );
  }
}

Map<String, dynamic> _section(
  Map<String, dynamic> json,
  String snake,
  String camel,
) {
  final value = json[snake] ?? json[camel];
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return {};
}

class HeroStats {
  final int totalUnits;
  final int occupiedUnits;
  final int availableUnits;
  final double expectedMonthlyRent;

  const HeroStats({
    required this.totalUnits,
    required this.occupiedUnits,
    required this.availableUnits,
    required this.expectedMonthlyRent,
  });

  factory HeroStats.fromJson(Map<String, dynamic> json) {
    return HeroStats(
      totalUnits: _asInt(json['total_units'] ?? json['totalUnits']),
      occupiedUnits: _asInt(json['occupied_units'] ?? json['occupiedUnits']),
      availableUnits: _asInt(json['available_units'] ?? json['availableUnits']),
      expectedMonthlyRent:
          _asDouble(json['expected_monthly_rent'] ?? json['expectedMonthlyRent']),
    );
  }
}

class DashboardOverview {
  final int totalActiveTenants;
  final int openComplaints;
  final double totalExpenses;
  final double rentReceived;
  final double rentPending;

  const DashboardOverview({
    required this.totalActiveTenants,
    required this.openComplaints,
    required this.totalExpenses,
    required this.rentReceived,
    required this.rentPending,
  });

  factory DashboardOverview.fromJson(Map<String, dynamic> json) {
    return DashboardOverview(
      totalActiveTenants:
          _asInt(json['total_active_tenants'] ?? json['totalActiveTenants']),
      openComplaints: _asInt(json['open_complaints'] ?? json['openComplaints']),
      totalExpenses: _asDouble(json['total_expenses'] ?? json['totalExpenses']),
      rentReceived: _asDouble(json['rent_received'] ?? json['rentReceived']),
      rentPending: _asDouble(json['rent_pending'] ?? json['rentPending']),
    );
  }
}

class ActionableInsights {
  final List<DashboardDefaulter> defaulters;
  final int pendingKycCount;
  final int upcomingVacancies;

  const ActionableInsights({
    required this.defaulters,
    required this.pendingKycCount,
    required this.upcomingVacancies,
  });

  factory ActionableInsights.fromJson(Map<String, dynamic> json) {
    final raw = json['defaulters'];
    return ActionableInsights(
      defaulters: raw is List
          ? raw
              .map((e) => DashboardDefaulter.fromJson(
                    Map<String, dynamic>.from(e as Map),
                  ))
              .toList()
          : const [],
      pendingKycCount:
          _asInt(json['pending_kyc_count'] ?? json['pendingKycCount']),
      upcomingVacancies:
          _asInt(json['upcoming_vacancies'] ?? json['upcomingVacancies']),
    );
  }
}

class DashboardDefaulter {
  final String tenancyId;
  final String name;
  final String room;
  final String unitDetails;
  final double amountDue;
  final String invoiceId;

  const DashboardDefaulter({
    required this.tenancyId,
    required this.name,
    required this.room,
    required this.unitDetails,
    required this.amountDue,
    required this.invoiceId,
  });

  factory DashboardDefaulter.fromJson(Map<String, dynamic> json) {
    return DashboardDefaulter(
      tenancyId: json['tenancy_id']?.toString() ?? json['tenancyId']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      room: json['room']?.toString() ?? '',
      unitDetails: json['unit_details']?.toString() ??
          json['unitDetails']?.toString() ??
          json['room']?.toString() ??
          '',
      amountDue: _asDouble(json['amount_due'] ?? json['amountDue']),
      invoiceId: json['invoice_id']?.toString() ?? json['invoiceId']?.toString() ?? '',
    );
  }
}

int _asInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}

double _asDouble(dynamic value) {
  if (value == null) return 0;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}
