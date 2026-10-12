// features/search/data/recent_searches.dart
//
// Recent global-search queries, stored on the device per property.

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/global_search.dart';

class RecentSearches {
  RecentSearches._();

  static String _key(String propertyId) => 'globalSearchRecent:$propertyId';

  static Future<List<String>> load(String propertyId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key(propertyId)) ?? const [];
  }

  static Future<List<String>> add(String propertyId, String query) async {
    final prefs = await SharedPreferences.getInstance();
    final next = pushRecentSearch(
      prefs.getStringList(_key(propertyId)) ?? const [],
      query,
    );
    await prefs.setStringList(_key(propertyId), next);
    return next;
  }

  static Future<void> clear(String propertyId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(propertyId));
  }
}
