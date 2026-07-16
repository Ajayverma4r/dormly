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
    return List<Map<String, dynamic>>.from(res.data['data']);
  }
}