// features/auth/data/auth_repository.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/network/api_client.dart';
import '../domain/user_profile.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(apiClientProvider));
});

const _androidOptions = AndroidOptions(encryptedSharedPreferences: true);

class AuthRepository {
  final ApiClient _client;
  final _storage = const FlutterSecureStorage(aOptions: _androidOptions);

  AuthRepository(this._client);

  Future<void> requestOtp(String phone) async {
    await _client.dio.post('/v1/auth/otp/request', data: {'phone': phone});
  }

  Future<UserProfile?> verifyOtp(String phone, String code) async {
    final res = await _client.dio.post('/v1/auth/otp/verify', data: {
      'phone': phone,
      'code': code,
    });
    final data = res.data['data'] as Map<String, dynamic>;
    await _storage.write(key: 'access_token', value: data['accessToken']);
    await _storage.write(key: 'refresh_token', value: data['refreshToken']);
    if (data['organizationId'] != null) {
      await _storage.write(
          key: 'organization_id', value: data['organizationId'] as String);
    }
    if (data['user'] is Map) {
      return UserProfile.fromJson(
          Map<String, dynamic>.from(data['user'] as Map));
    }
    return null;
  }

  Future<UserProfile> fetchMe() async {
    final res = await _client.dio.get('/v1/auth/me');
    return UserProfile.fromJson(
        Map<String, dynamic>.from(res.data['data'] as Map));
  }

  Future<UserProfile> updateProfile({
    String? name,
    String? email,
    String? avatarUrl,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (email != null) body['email'] = email.isEmpty ? null : email;
    if (avatarUrl != null) body['avatarUrl'] = avatarUrl;
    final res = await _client.dio.patch('/v1/auth/me', data: body);
    return UserProfile.fromJson(
        Map<String, dynamic>.from(res.data['data'] as Map));
  }

  Future<UserProfile> uploadAvatar(String filePath) async {
    final form = FormData.fromMap({
      'avatar': await MultipartFile.fromFile(filePath),
    });
    final res = await _client.dio.post('/v1/auth/me/avatar', data: form);
    return UserProfile.fromJson(
        Map<String, dynamic>.from(res.data['data'] as Map));
  }

  Future<List<Map<String, dynamic>>> listContexts() async {
    final res = await _client.dio.get('/v1/auth/contexts');
    return List<Map<String, dynamic>>.from(res.data['data']);
  }

  Future<Map<String, dynamic>> selectContext(
      String contextType, String contextId) async {
    final res = await _client.dio.post('/v1/auth/contexts/select', data: {
      'contextType': contextType,
      'contextId': contextId,
    });
    final data = res.data['data'];
    final context = data['context'];

    await _storage.write(key: 'access_token', value: data['accessToken']);
    await _storage.write(key: 'context_type', value: context['type']);
    await _storage.write(key: 'context_role', value: context['role']);

    if (context['role'] == 'owner' || context['role'] == 'admin') {
      await _storage.write(key: 'organization_id', value: context['id']);
    }
    if (context['propertyId'] != null) {
      await _storage.write(
          key: 'scoped_property_id', value: context['propertyId']);
    }
    return Map<String, dynamic>.from(context as Map);
  }

  Future<String?> getOrganizationId() => _storage.read(key: 'organization_id');
  Future<String?> getAccessToken() => _storage.read(key: 'access_token');
  Future<String?> getContextRole() => _storage.read(key: 'context_role');
  Future<String?> getScopedPropertyId() =>
      _storage.read(key: 'scoped_property_id');

  Future<void> logout() async {
    await _storage.deleteAll();
  }
}
