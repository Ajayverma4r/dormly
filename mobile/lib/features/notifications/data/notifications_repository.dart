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
    return list.map((e) {
      if (e is Map<String, dynamic>) return e;
      if (e is Map) return Map<String, dynamic>.from(e);
      return <String, dynamic>{};
    }).where((e) => e.isNotEmpty).toList();
  }
}
