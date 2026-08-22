// features/tenancies/presentation/assignable_units_provider.dart
//
// Loads every unit/bed/flat/shop that can receive a tenant for a property.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../structure/data/structure_repository.dart';
import '../../structure/domain/hierarchy_level.dart';
import '../../structure/presentation/dynamic_dashboard/dynamic_dashboard_screen.dart'
    show hierarchyLevelsProvider;
import '../data/tenancy_repository.dart';
import '../domain/assignable_unit.dart';

final assignableUnitsProvider =
    FutureProvider.autoDispose.family<List<AssignableUnit>, String>(
  (ref, propertyId) async {
    final structureRepo = ref.watch(structureRepositoryProvider);
    final tenancyRepo = ref.watch(tenancyRepositoryProvider);
    final levels = await ref.watch(hierarchyLevelsProvider(propertyId).future);
    final tenancies = await tenancyRepo.listByProperty(propertyId);

    final occupiedIds = <String>{};
    for (final t in tenancies) {
      if (t['status']?.toString() == 'active') {
        final nid = t['node_id']?.toString() ?? t['nodeId']?.toString();
        if (nid != null && nid.isNotEmpty) occupiedIds.add(nid);
      }
    }

    final units = <AssignableUnit>[];

    Future<void> walk(
      HierarchyLevel level,
      String? parentNodeId,
      List<String> pathParts,
    ) async {
      final nodes = await structureRepo.listNodes(
        propertyId,
        level.id,
        parentNodeId: parentNodeId,
      );

      for (final node in nodes) {
        final name = node['name']?.toString() ?? 'Untitled';
        final id = node['id']?.toString() ?? '';
        final path = [...pathParts, name];

        if (isAssignableLevel(level.id, levels)) {
          units.add(AssignableUnit(
            nodeId: id,
            nodeName: name,
            levelName: level.displayName,
            pathLabel: path.join(' · '),
            occupied: occupiedIds.contains(id),
          ));
        } else {
          final childLevels = levels
              .where((l) => l.parentLevelId == level.id)
              .toList()
            ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
          for (final childLevel in childLevels) {
            await walk(childLevel, id, path);
          }
        }
      }
    }

    final rootLevels = levels.where((l) => l.parentLevelId == null).toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

    for (final root in rootLevels) {
      await walk(root, null, []);
    }

    units.sort((a, b) => a.pathLabel.compareTo(b.pathLabel));
    return units;
  },
);

/// Cascading picker state — one selected node id per hierarchy step.
class UnitSelectionPath {
  final List<({HierarchyLevel level, Map<String, dynamic> node})> steps;

  const UnitSelectionPath(this.steps);

  String? get selectedNodeId =>
      steps.isEmpty ? null : steps.last.node['id']?.toString();

  String get pathLabel =>
      steps.map((s) => s.node['name']?.toString() ?? '').join(' · ');
}

final unitSelectionLevelsProvider =
    FutureProvider.autoDispose.family<List<HierarchyLevel>, String>(
  (ref, propertyId) => ref.watch(hierarchyLevelsProvider(propertyId).future),
);
