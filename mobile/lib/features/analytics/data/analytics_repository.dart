// features/analytics/data/analytics_repository.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

final analyticsRepositoryProvider = Provider<AnalyticsRepository>((ref) {
  return AnalyticsRepository(ref.watch(apiClientProvider));
});

class AnalyticsRepository {
  final ApiClient _client;
  AnalyticsRepository(this._client);

  Future<Map<String, dynamic>> getAnalytics(String propertyId) async {
    final res = await _client.dio.get('/v1/properties/$propertyId/analytics');
    return Map<String, dynamic>.from(res.data['data']);
  }

  Future<Map<String, dynamic>> getOrganizationAnalytics(String organizationId) async {
    final res = await _client.dio.get('/v1/organizations/$organizationId/analytics');
    return Map<String, dynamic>.from(res.data['data']);
  }
  
  Future<List<Map<String, dynamic>>> getActivity(String propertyId) async {
    final res = await _client.dio.get('/v1/properties/$propertyId/analytics/activity');
    return List<Map<String, dynamic>>.from(res.data['data']);
  }
}