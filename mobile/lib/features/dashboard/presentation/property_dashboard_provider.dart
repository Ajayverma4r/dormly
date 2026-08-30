// features/dashboard/presentation/property_dashboard_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/dashboard_repository.dart';
import '../domain/property_dashboard.dart';

final propertyDashboardProvider =
    FutureProvider.autoDispose.family<PropertyDashboard, String>(
  (ref, propertyId) =>
      ref.watch(dashboardRepositoryProvider).getPropertyDashboard(propertyId),
);
