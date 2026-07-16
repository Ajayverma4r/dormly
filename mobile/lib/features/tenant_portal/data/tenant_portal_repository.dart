// features/tenant_portal/data/tenant_portal_repository.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

final tenantPortalRepositoryProvider = Provider<TenantPortalRepository>((ref) {
  return TenantPortalRepository(ref.watch(apiClientProvider));
});

class TenantPortalRepository {
  final ApiClient _client;
  TenantPortalRepository(this._client);

  Future<Map<String, dynamic>> getMyTenancy() async {
    final res = await _client.dio.get('/v1/tenant-portal/me');
    return Map<String, dynamic>.from(res.data['data']);
  }
  Future<List<Map<String, dynamic>>> listMyInvoices() async {
    final res = await _client.dio.get('/v1/tenant-portal/invoices');
    return List<Map<String, dynamic>>.from(res.data['data']);
  }
  String get baseUrl => _client.dio.options.baseUrl;
}