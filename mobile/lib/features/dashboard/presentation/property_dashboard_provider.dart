// features/dashboard/presentation/property_dashboard_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/dashboard_repository.dart';
import '../domain/dashboard_financials.dart';
import '../domain/property_dashboard.dart';

final propertyDashboardProvider =
    FutureProvider.autoDispose.family<PropertyDashboard, String>(
  (ref, propertyId) =>
      ref.watch(dashboardRepositoryProvider).getPropertyDashboard(propertyId),
);

/// Period chosen in the dashboard's Financial Overview, per property.
final financialPeriodProvider =
    StateProvider.family<FinancialPeriod, String>(
  (ref, propertyId) => FinancialPeriod.thisMonth,
);

final dashboardFinancialsProvider = FutureProvider.autoDispose
    .family<DashboardFinancials, (String, FinancialPeriod)>((ref, args) {
  // Reloads whenever the dashboard is refreshed (pull-to-refresh, new payment).
  ref.watch(
    propertyDashboardProvider(args.$1).select((d) => d.valueOrNull),
  );
  return ref
      .watch(dashboardRepositoryProvider)
      .getFinancials(args.$1, args.$2);
});
