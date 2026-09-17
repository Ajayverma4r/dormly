// core/storage/app_prefs.dart
//
// Lightweight SharedPreferences helpers for non-secret app flags.

import 'package:shared_preferences/shared_preferences.dart';

const _isFirstTimeKey = 'isFirstTime';

class AppPrefs {
  AppPrefs._();

  /// `true` until the user skips or finishes onboarding (default on first install).
  static Future<bool> isFirstTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isFirstTimeKey) ?? true;
  }

  static Future<void> setFirstTimeCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isFirstTimeKey, false);
  }
}
