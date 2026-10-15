// features/gate_passes/data/gate_passes_repository.dart
//
// Property-team side of gate passes. The backend allows owner, admin,
// manager and staff to list and decide; tenants use /tenant-portal.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

final gatePassesRepositoryProvider = Provider<GatePassesRepository>((ref) {
  return GatePassesRepository(ref.watch(apiClientProvider));
});

class GatePassesRepository {
  final ApiClient _client;
  GatePassesRepository(this._client);

  Future<List<Map<String, dynamic>>> listForProperty(String propertyId) async {
    final res = await _client.dio.get('/v1/properties/$propertyId/gate-passes');
    final raw = res.data['data'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// [status] is `approved` or `denied` — the only values the server accepts.
  Future<Map<String, dynamic>> decide(
    String propertyId,
    String gatePassId,
    String status,
  ) async {
    final res = await _client.dio.patch(
      '/v1/properties/$propertyId/gate-passes/$gatePassId',
      data: {'status': status},
    );
    return Map<String, dynamic>.from(res.data['data'] as Map);
  }
}
