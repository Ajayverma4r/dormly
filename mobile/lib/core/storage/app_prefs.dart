// core/storage/app_prefs.dart
//
// Lightweight SharedPreferences helpers for non-secret app flags.

import 'package:shared_preferences/shared_preferences.dart';

const _isFirstTimeKey = 'isFirstTime';

class AppPrefs {
  AppPrefs._();

  /// `true` until historically marked complete (legacy flag).
  ///
  /// Startup routing no longer uses this — unauthenticated users always see
  /// the app intro. Kept so existing installs / other code do not break.
  static Future<bool> isFirstTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isFirstTimeKey) ?? true;
  }

  static Future<void> setFirstTimeCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isFirstTimeKey, false);
  }
}
