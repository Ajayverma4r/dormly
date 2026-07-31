// features/reports/data/reports_repository.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../auth/data/auth_repository.dart';

final reportsRepositoryProvider = Provider<ReportsRepository>((ref) {
  return ReportsRepository(ref.watch(apiClientProvider), ref.watch(authRepositoryProvider));
});

class ReportsRepository {
  final ApiClient _client;
  final AuthRepository _authRepo;
  ReportsRepository(this._client, this._authRepo);

  Future<Uri> rentCollectionUrl(String propertyId, DateTime start, DateTime end, String format) async {
    final token = await _authRepo.getAccessToken();
    final base = _client.dio.options.baseUrl;
    return Uri.parse('$base/v1/properties/$propertyId/reports/rent-collection').replace(queryParameters: {
      'startDate': start.toIso8601String().split('T').first,
      'endDate': end.toIso8601String().split('T').first,
      'format': format,
      'token': token,
    });
  }

  Future<Uri> occupancyUrl(String propertyId, String format) async {
    final token = await _authRepo.getAccessToken();
    final base = _client.dio.options.baseUrl;
    return Uri.parse('$base/v1/properties/$propertyId/reports/occupancy').replace(queryParameters: {
      'format': format,
      'token': token,
    });
  }
}