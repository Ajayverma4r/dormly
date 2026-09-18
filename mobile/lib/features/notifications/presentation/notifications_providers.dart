// features/notifications/presentation/notifications_providers.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/notifications_repository.dart';

/// Full notification list (includes read + unread).
final notificationsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return ref.watch(notificationsRepositoryProvider).list();
});

int countUnread(List<Map<String, dynamic>> items) =>
    items.where((n) => !NotificationsRepository.isRead(n)).length;

/// Bell badge — strictly unread count, with optimistic local updates.
final unreadNotificationsCountProvider =
    AsyncNotifierProvider.autoDispose<UnreadNotificationsCount, int>(
  UnreadNotificationsCount.new,
);

class UnreadNotificationsCount extends AutoDisposeAsyncNotifier<int> {
  Timer? _poll;

  @override
  Future<int> build() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) {
      refreshQuiet();
    });
    ref.onDispose(() => _poll?.cancel());
    return ref.read(notificationsRepositoryProvider).unreadCount();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = AsyncData(
      await ref.read(notificationsRepositoryProvider).unreadCount(),
    );
  }

  Future<void> refreshQuiet() async {
    try {
      final count =
          await ref.read(notificationsRepositoryProvider).unreadCount();
      state = AsyncData(count);
    } catch (_) {
      /* keep last known */
    }
  }

  void optimisticDecrement([int by = 1]) {
    final cur = state.valueOrNull ?? 0;
    state = AsyncData(math.max(0, cur - by));
  }

  void optimisticClear() {
    state = const AsyncData(0);
  }
}
