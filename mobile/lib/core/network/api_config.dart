// core/network/api_config.dart
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Resolves the API base URL for the current build.
///
/// Debug builds default to the **local** backend so notification inserts and
/// dashboard changes are visible without deploying to Render.
/// Override anytime with:
///   flutter run --dart-define=API_BASE_URL=https://...
String resolveApiBaseUrl() {
  const fromEnv = String.fromEnvironment('API_BASE_URL');
  if (fromEnv.isNotEmpty) return fromEnv;

  if (kDebugMode) {
    // Android emulator → host machine loopback
    if (!kIsWeb && Platform.isAndroid) {
      return 'http://10.0.2.2:4000';
    }
    // iOS simulator / desktop
    return 'http://127.0.0.1:4000';
  }

  return 'https://dormly-backend.onrender.com';
}
