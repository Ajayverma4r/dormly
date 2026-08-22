// core/network/api_client.dart
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../storage/auth_storage.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

class ApiClient {
  late final Dio dio;
  late final Dio _bareDio;

  bool _refreshing = false;

  ApiClient() {
    final baseUrl = const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://dormly-backend.onrender.com',
    );

    final baseOptions = BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
    );

    dio = Dio(baseOptions);
    // Used for token refresh / context restore — no auth interceptor loop.
    _bareDio = Dio(baseOptions);

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        try {
          final token = await AuthStorage.accessToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
        } catch (e) {
          debugPrint('SecureStorage read failed (non-fatal): $e');
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode != 401) {
          handler.next(error);
          return;
        }
        if (error.requestOptions.extra['authRetried'] == true) {
          handler.next(error);
          return;
        }

        final recovered = await _recoverSession();
        if (!recovered) {
          handler.next(error);
          return;
        }

        try {
          error.requestOptions.extra['authRetried'] = true;
          final token = await AuthStorage.accessToken();
          if (token != null) {
            error.requestOptions.headers['Authorization'] = 'Bearer $token';
          }
          final response = await dio.fetch(error.requestOptions);
          handler.resolve(response);
        } catch (e) {
          if (e is DioException) {
            handler.next(e);
          } else {
            handler.next(error);
          }
        }
      },
    ));
  }

  /// Refresh the access token and re-select the last workspace context.
  Future<bool> _recoverSession() async {
    if (_refreshing) return false;
    _refreshing = true;
    try {
      final refresh = await AuthStorage.refreshToken();
      if (refresh == null || refresh.isEmpty) return false;

      final res = await _bareDio.post('/v1/auth/refresh', data: {
        'refreshToken': refresh,
      });
      final newAccess = res.data['data']['accessToken'] as String?;
      if (newAccess == null || newAccess.isEmpty) return false;
      await AuthStorage.writeAccessToken(newAccess);

      // Refresh tokens are user-scoped; re-apply workspace context claims.
      final ctxType = await AuthStorage.contextType();
      final ctxId =
          await AuthStorage.contextId() ?? await AuthStorage.organizationId();
      if (ctxType == null || ctxId == null) return true;

      final selectRes = await _bareDio.post(
        '/v1/auth/contexts/select',
        data: {'contextType': ctxType, 'contextId': ctxId},
        options: Options(headers: {'Authorization': 'Bearer $newAccess'}),
      );
      final data = selectRes.data['data'] as Map<String, dynamic>;
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
      return true;
    } catch (e) {
      debugPrint('Session recovery failed: $e');
      return false;
    } finally {
      _refreshing = false;
    }
  }
}
