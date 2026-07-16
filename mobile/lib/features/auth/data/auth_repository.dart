// features/auth/data/auth_repository.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/network/api_client.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(apiClientProvider));
});

class AuthRepository {
  final ApiClient _client;
  final _storage = const FlutterSecureStorage();

  AuthRepository(this._client);

  Future<void> requestOtp(String phone) async {
    await _client.dio.post('/v1/auth/otp/request', data: {'phone': phone});
  }

  Future<void> verifyOtp(String phone, String code) async {
    final res = await _client.dio.post('/v1/auth/otp/verify', data: {
      'phone': phone,
      'code': code,
    });
    final data = res.data['data'];
   await _storage.write(key: 'access_token', value: data['accessToken']);
    await _storage.write(key: 'refresh_token', value: data['refreshToken']);
    if (data['organizationId'] != null) {
      await _storage.write(key: 'organization_id', value: data['organizationId']);
    }
  }

  Future<List<Map<String, dynamic>>> listContexts() async {
    final res = await _client.dio.get('/v1/auth/contexts');
    return List<Map<String, dynamic>>.from(res.data['data']);
  }

  Future<Map<String, dynamic>> selectContext(String contextType, String contextId) async {
    final res = await _client.dio.post('/v1/auth/contexts/select', data: {
      'contextType': contextType,
      'contextId': contextId,
    });
    final data = res.data['data'];
    final context = data['context'];

    // Overwrites the earlier "unscoped" token from verifyOtp with a proper
    // scoped one that carries the context info the backend now requires.
    await _storage.write(key: 'access_token', value: data['accessToken']);
    await _storage.write(key: 'context_type', value: context['type']);
    await _storage.write(key: 'context_role', value: context['role']);

    if (context['role'] == 'owner' || context['role'] == 'admin') {
      await _storage.write(key: 'organization_id', value: context['id']);
    }
    if (context['propertyId'] != null) {
      await _storage.write(key: 'scoped_property_id', value: context['propertyId']);
    }
    return context;
  }

  Future<String?> getOrganizationId() => _storage.read(key: 'organization_id');
  Future<String?> getAccessToken() => _storage.read(key: 'access_token');
  Future<String?> getContextRole() => _storage.read(key: 'context_role');
  Future<String?> getScopedPropertyId() => _storage.read(key: 'scoped_property_id');
  Future<void> logout() async {
    await _storage.deleteAll();
  }

}