// features/structure/presentation/dynamic_dashboard/dynamic_dashboard_screen.dart
//
// Thin role router into PropertyShellScreen (the ONLY owner/manager bottom nav).
// Old inline dashboard UI was removed — do not reintroduce it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/hierarchy_level.dart';
import '../../data/structure_repository.dart';
import '../../../analytics/data/analytics_repository.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../complaints/presentation/complaints_list_screen.dart';
import '../property_shell_screen.dart';

final hierarchyLevelsProvider =
    FutureProvider.family<List<HierarchyLevel>, String>((ref, propertyId) async {
  final repo = ref.watch(structureRepositoryProvider);
  final levels = await repo.listLevels(propertyId);
  return levels.where((l) => l.isEnabled).toList()
    ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
});

final nodeCountProvider =
    FutureProvider.family<int, (String propertyId, String levelId)>(
        (ref, args) async {
  final repo = ref.watch(structureRepositoryProvider);
  return repo.countNodes(args.$1, args.$2);
});

final activityProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, propertyId) =>
      ref.watch(analyticsRepositoryProvider).getActivity(propertyId),
);

final contextRoleProvider = FutureProvider.autoDispose<String?>(
  (ref) => ref.watch(authRepositoryProvider).getContextRole(),
);

/// Entry for `/property/:id` — staff → complaints; everyone else → new 5-tab shell.
class DynamicDashboardScreen extends ConsumerWidget {
  final String propertyId;
  final String propertyName;

  const DynamicDashboardScreen({
    super.key,
    required this.propertyId,
    required this.propertyName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roleAsync = ref.watch(contextRoleProvider);

    return roleAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (err, _) =>
          Scaffold(body: Center(child: Text('Something went wrong: $err'))),
      data: (role) {
        if (role == 'staff') {
          return ComplaintsListScreen(propertyId: propertyId, isRoot: true);
        }
        // Force a fresh shell instance so hot-reload cannot keep old tab state.
        return PropertyShellScreen(
          key: ValueKey('shell-v2-$propertyId'),
          propertyId: propertyId,
          propertyName: propertyName,
        );
      },
    );
  }
}
