// core/storage/auth_storage.dart
//
// Single source of truth for persisted auth/session keys. Both ApiClient and
// AuthRepository read/write through here so tokens survive app restarts.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _androidOptions = AndroidOptions(encryptedSharedPreferences: true);

/// Shared secure storage instance — do not create additional FlutterSecureStorage
/// elsewhere or reads/writes may diverge on some Android builds.
class AuthStorage {
  AuthStorage._();

  static const _storage = FlutterSecureStorage(aOptions: _androidOptions);

  static const accessTokenKey = 'access_token';
  static const refreshTokenKey = 'refresh_token';
  static const userIdKey = 'user_id';
  static const organizationIdKey = 'organization_id';
  static const contextTypeKey = 'context_type';
  static const contextIdKey = 'context_id';
  static const contextRoleKey = 'context_role';
  static const scopedPropertyIdKey = 'scoped_property_id';

  static Future<String?> read(String key) => _storage.read(key: key);

  static Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  static Future<void> delete(String key) => _storage.delete(key: key);

  static Future<void> clearAll() => _storage.deleteAll();

  static Future<String?> accessToken() => read(accessTokenKey);
  static Future<String?> refreshToken() => read(refreshTokenKey);
  static Future<String?> userId() => read(userIdKey);
  static Future<String?> organizationId() => read(organizationIdKey);
  static Future<String?> contextType() => read(contextTypeKey);
  static Future<String?> contextId() => read(contextIdKey);
  static Future<String?> contextRole() => read(contextRoleKey);
  static Future<String?> scopedPropertyId() => read(scopedPropertyIdKey);

  static Future<void> writeAccessToken(String value) =>
      write(accessTokenKey, value);

  static Future<void> writeRefreshToken(String value) =>
      write(refreshTokenKey, value);

  static Future<void> writeUserId(String value) => write(userIdKey, value);

  static Future<void> writeContext({
    required String type,
    required String id,
    required String role,
    String? organizationId,
    String? scopedPropertyId,
  }) async {
    await write(contextTypeKey, type);
    await write(contextIdKey, id);
    await write(contextRoleKey, role);
    if (organizationId != null) {
      await write(organizationIdKey, organizationId);
    } else {
      await delete(organizationIdKey);
    }
    if (scopedPropertyId != null) {
      await write(scopedPropertyIdKey, scopedPropertyId);
    } else {
      await delete(scopedPropertyIdKey);
    }
  }

  /// True when we have enough persisted state to attempt a silent restore.
  static Future<bool> hasPersistedSession() async {
    final refresh = await refreshToken();
    final access = await accessToken();
    return (refresh != null && refresh.isNotEmpty) ||
        (access != null && access.isNotEmpty);
  }
}
