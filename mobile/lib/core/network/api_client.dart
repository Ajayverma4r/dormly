// core/network/api_client.dart
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

// Use EncryptedSharedPreferences on Android — the default Keystore-only backend
// throws on many physical devices (especially Samsung/Xiaomi in release mode).
const _androidOptions = AndroidOptions(encryptedSharedPreferences: true);

class ApiClient {
  late final Dio dio;
  final _storage = const FlutterSecureStorage(aOptions: _androidOptions);

  ApiClient() {
    dio = Dio(BaseOptions(
      baseUrl: const String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: 'https://dormly-backend.onrender.com',
      ),
      // Render free tier can take 30-60 s to cold-start. Without these limits
      // the app just hangs forever showing a spinner; with them it fails fast
      // so the UI can show a retry message.
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
    ));

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        try {
          final token = await _storage.read(key: 'access_token');
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
        } catch (e) {
          // Storage read failure is non-fatal — request proceeds unauthenticated.
          // A 401 from the server will redirect to login cleanly.
          debugPrint('SecureStorage read failed (non-fatal): $e');
        }
        handler.next(options);
      },
    ));
  }
}
