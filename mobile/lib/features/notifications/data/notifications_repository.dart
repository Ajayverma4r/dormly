// features/notifications/data/notifications_repository.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

final notificationsRepositoryProvider = Provider<NotificationsRepository>((ref) {
  return NotificationsRepository(ref.watch(apiClientProvider));
});

class NotificationsRepository {
  final ApiClient _client;
  NotificationsRepository(this._client);

  Future<List<Map<String, dynamic>>> list() async {
    final res = await _client.dio.get('/v1/notifications');
    final raw = res.data;
    final list = raw is Map ? raw['data'] : null;
    if (list is! List) return const [];
    return list.map(_normalize).where((e) => e.isNotEmpty).toList();
  }

  Future<int> unreadCount() async {
    try {
      final res = await _client.dio.get('/v1/notifications/unread-count');
      final raw = res.data;
      if (raw is Map && raw['data'] is Map) {
        final n = (raw['data'] as Map)['count'];
        if (n is int) return n;
        return int.tryParse(n?.toString() ?? '') ?? 0;
      }
    } catch (_) {
      // Fallback: derive from full list
    }
    final items = await list();
    return items.where((n) => !_isRead(n)).length;
  }

  Future<Map<String, dynamic>> markRead(String id) async {
    final res = await _client.dio.patch('/v1/notifications/$id/read');
    final raw = res.data;
    if (raw is Map && raw['data'] is Map) {
      return _normalize(raw['data']);
    }
    return {'id': id, 'read_at': DateTime.now().toIso8601String(), 'is_read': true};
  }

  Future<int> markAllRead() async {
    final res = await _client.dio.post('/v1/notifications/read-all');
    final raw = res.data;
    if (raw is Map && raw['data'] is Map) {
      final n = (raw['data'] as Map)['updated'];
      if (n is int) return n;
      return int.tryParse(n?.toString() ?? '') ?? 0;
    }
    return 0;
  }

  static bool isRead(Map<String, dynamic> n) => _isRead(n);

  static bool _isRead(Map<String, dynamic> n) {
    if (n['is_read'] == true || n['isRead'] == true) return true;
    if (n['is_read'] == false || n['isRead'] == false) return false;
    final readAt = n['read_at'] ?? n['readAt'];
    return readAt != null && readAt.toString().trim().isNotEmpty;
  }

  Map<String, dynamic> _normalize(dynamic e) {
    if (e is! Map) return <String, dynamic>{};
    final m = Map<String, dynamic>.from(e);
    final read = _isRead(m);
    m['is_read'] = read;
    m['isRead'] = read;
    return m;
  }
}
