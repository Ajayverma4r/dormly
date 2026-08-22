// features/auth/data/auth_repository.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/auth_storage.dart';
import '../domain/user_profile.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(apiClientProvider));
});

class AuthRepository {
  final ApiClient _client;

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
    await AuthStorage.writeAccessToken(data['accessToken'] as String);
    await AuthStorage.writeRefreshToken(data['refreshToken'] as String);
    if (data['userId'] != null) {
      await AuthStorage.writeUserId(data['userId'] as String);
    }
    if (data['organizationId'] != null) {
      await AuthStorage.write(AuthStorage.organizationIdKey,
          data['organizationId'] as String);
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
    final data = res.data['data'] as Map<String, dynamic>;
    final context = Map<String, dynamic>.from(data['context'] as Map);

    await AuthStorage.writeAccessToken(data['accessToken'] as String);
    await AuthStorage.writeContext(
      type: context['type'] as String,
      id: context['id'] as String,
      role: context['role'] as String,
      organizationId: context['role'] == 'owner' || context['role'] == 'admin'
          ? context['id'] as String
          : null,
      scopedPropertyId: context['propertyId'] as String?,
    );
    return context;
  }

  Future<String?> getOrganizationId() => AuthStorage.organizationId();
  Future<String?> getAccessToken() => AuthStorage.accessToken();
  Future<String?> getRefreshToken() => AuthStorage.refreshToken();
  Future<String?> getContextRole() => AuthStorage.contextRole();
  Future<String?> getScopedPropertyId() => AuthStorage.scopedPropertyId();
  Future<String?> getContextType() => AuthStorage.contextType();
  Future<String?> getContextId() async {
    final id = await AuthStorage.contextId();
    return id ?? await AuthStorage.organizationId();
  }

  Future<bool> hasPersistedSession() => AuthStorage.hasPersistedSession();

  Future<bool> hasStoredContext() async {
    final type = await AuthStorage.contextType();
    final id = await getContextId();
    return type != null && id != null;
  }

  /// Validates the current access token; refreshes via refresh_token when expired.
  Future<bool> ensureValidSession() async {
    if (!await hasPersistedSession()) return false;

    try {
      await _client.dio.get('/v1/auth/me');
      return true;
    } on DioException catch (e) {
      if (e.response?.statusCode != 401) rethrow;
    }

    final refresh = await getRefreshToken();
    if (refresh == null || refresh.isEmpty) return false;

    try {
      final res = await _client.dio.post('/v1/auth/refresh', data: {
        'refreshToken': refresh,
      });
      final newAccess = res.data['data']['accessToken'] as String?;
      if (newAccess == null || newAccess.isEmpty) return false;
      await AuthStorage.writeAccessToken(newAccess);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Re-selects the last workspace so the JWT includes ctxType/ctxRole claims.
  Future<bool> restoreContextIfNeeded() async {
    final type = await AuthStorage.contextType();
    final id = await getContextId();
    if (type == null || id == null) return false;

    try {
      await selectContext(type, id);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> logout() async {
    await AuthStorage.clearAll();
  }
}
