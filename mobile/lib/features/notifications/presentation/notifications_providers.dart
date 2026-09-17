// features/notifications/presentation/notifications_providers.dart
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
  @override
  Future<int> build() {
    return ref.read(notificationsRepositoryProvider).unreadCount();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = AsyncData(
      await ref.read(notificationsRepositoryProvider).unreadCount(),
    );
  }

  void optimisticDecrement([int by = 1]) {
    final cur = state.valueOrNull ?? 0;
    state = AsyncData(math.max(0, cur - by));
  }

  void optimisticClear() {
    state = const AsyncData(0);
  }
}
