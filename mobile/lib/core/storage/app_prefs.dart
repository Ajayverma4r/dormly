// core/storage/app_prefs.dart
//
// Lightweight SharedPreferences helpers for non-secret app flags.

import 'package:shared_preferences/shared_preferences.dart';

const _isFirstTimeKey = 'isFirstTime';
const _darkThemeKey = 'darkTheme';
const _lastWorkspacePrefix = 'lastWorkspace:';

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

  /// `false` (light theme) until the user picks dark.
  static Future<bool> isDarkTheme() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_darkThemeKey) ?? false;
  }

  static Future<void> setDarkTheme(bool dark) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_darkThemeKey, dark);
  }

  /// Last workspace this user opened, as `type:id`. Kept across logout so the
  /// next login can reopen it; only ever a hint, the server list decides.
  static Future<String?> lastWorkspace(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_lastWorkspacePrefix$userId');
  }

  static Future<void> setLastWorkspace(
    String userId,
    String type,
    String id,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_lastWorkspacePrefix$userId', '$type:$id');
  }
}
