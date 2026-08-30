// features/dashboard/data/dashboard_repository.dart

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../analytics/data/analytics_repository.dart';
import '../../complaints/data/complaints_repository.dart';
import '../domain/property_dashboard.dart';

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return DashboardRepository(
    ref.watch(apiClientProvider),
    ref.watch(analyticsRepositoryProvider),
    ref.watch(complaintsRepositoryProvider),
  );
});

class DashboardRepository {
  final ApiClient _client;
  final AnalyticsRepository _analytics;
  final ComplaintsRepository _complaints;

  DashboardRepository(this._client, this._analytics, this._complaints);

  Future<PropertyDashboard> getPropertyDashboard(String propertyId) async {
    try {
      final res = await _client.dio.get('/v1/properties/$propertyId/dashboard');
      final raw = res.data;
      if (raw is! Map || raw['data'] is! Map) {
        throw FormatException('Unexpected dashboard response shape: $raw');
      }
      return PropertyDashboard.fromJson(
        Map<String, dynamic>.from(raw['data'] as Map),
      );
    } on DioException catch (e) {
      debugPrint(
        '[dashboard] GET /dashboard failed '
        '(${e.response?.statusCode}): ${e.response?.data ?? e.message}',
      );
      return _fallbackFromLegacyApis(propertyId);
    } on FormatException catch (e) {
      debugPrint('[dashboard] parse error: $e');
      return _fallbackFromLegacyApis(propertyId);
    }
  }

  /// Keeps the dashboard usable when /dashboard is unavailable or returns bad JSON.
  Future<PropertyDashboard> _fallbackFromLegacyApis(String propertyId) async {
    try {
      final analytics = await _analytics.getAnalytics(propertyId);
      final complaints = await _complaints.listForProperty(propertyId);
      final openComplaints = complaints
          .where((c) => c['status'] == 'open' || c['status'] == 'in_progress')
          .length;

      final totalUnits = (analytics['totalUnits'] as num?)?.toInt() ?? 0;
      final occupiedUnits = (analytics['occupiedUnits'] as num?)?.toInt() ?? 0;
      final vacantUnits = (analytics['vacantUnits'] as num?)?.toInt() ??
          (totalUnits - occupiedUnits);
      final pendingRent =
          double.tryParse(analytics['pendingRent']?.toString() ?? '') ?? 0;
      final totalRevenue =
          double.tryParse(analytics['totalRevenue']?.toString() ?? '') ?? 0;

      return PropertyDashboard(
        heroStats: HeroStats(
          totalUnits: totalUnits,
          occupiedUnits: occupiedUnits,
          availableUnits: vacantUnits,
          expectedMonthlyRent: pendingRent + totalRevenue,
        ),
        overview: DashboardOverview(
          totalActiveTenants: occupiedUnits,
          openComplaints: openComplaints,
          totalExpenses: 0,
          rentReceived: totalRevenue,
          rentPending: pendingRent,
        ),
        actionableInsights: const ActionableInsights(
          defaulters: [],
          pendingKycCount: 0,
          upcomingVacancies: 0,
        ),
      );
    } catch (e) {
      debugPrint('[dashboard] legacy fallback also failed: $e');
      rethrow;
    }
  }
}
