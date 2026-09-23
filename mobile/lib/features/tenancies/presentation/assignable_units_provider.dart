// features/tenancies/presentation/assignable_units_provider.dart
//
// Loads every unit/bed/flat/shop that can receive a tenant for a property.
// Handles same-level nesting (e.g. rental Room under Floor on the unit level).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../structure/data/structure_repository.dart';
import '../../structure/domain/hierarchy_level.dart';
import '../../structure/presentation/dynamic_dashboard/dynamic_dashboard_screen.dart'
    show hierarchyLevelsProvider;
import '../data/tenancy_repository.dart';
import '../domain/assignable_unit.dart';

double? _readAmount(Map<String, dynamic> node, List<String> keys) {
  for (final key in keys) {
    final v = node[key];
    if (v is num) return v.toDouble();
    if (v is String) {
      final n = double.tryParse(v);
      if (n != null) return n;
    }
  }
  final meta = node['metadata'];
  if (meta is Map) {
    for (final key in keys) {
      final v = meta[key];
      if (v is num) return v.toDouble();
      if (v is String) {
        final n = double.tryParse(v);
        if (n != null) return n;
      }
    }
  }
  return null;
}

AssignableUnit _unitFromNode({
  required Map<String, dynamic> node,
  required String id,
  required String name,
  required String levelName,
  required String pathLabel,
  required Set<String> occupiedIds,
  required Map<String, String> tenantByNodeId,
}) {
  return AssignableUnit(
    nodeId: id,
    nodeName: name,
    levelName: levelName,
    pathLabel: pathLabel,
    occupied: occupiedIds.contains(id),
    monthlyRent: _readAmount(node, const ['monthlyRent', 'monthly_rent']),
    securityDeposit:
        _readAmount(node, const ['securityDeposit', 'security_deposit']),
    tenantName: tenantByNodeId[id],
  );
}

final assignableUnitsProvider =
    FutureProvider.autoDispose.family<List<AssignableUnit>, String>(
  (ref, propertyId) async {
    final structureRepo = ref.watch(structureRepositoryProvider);
    final tenancyRepo = ref.watch(tenancyRepositoryProvider);
    final levels = await ref.watch(hierarchyLevelsProvider(propertyId).future);
    final tenancies = await tenancyRepo.listByProperty(propertyId);

    final occupiedIds = <String>{};
    final tenantByNodeId = <String, String>{};
    for (final t in tenancies) {
      if (t['status']?.toString() == 'active') {
        final nid = t['node_id']?.toString() ?? t['nodeId']?.toString();
        if (nid != null && nid.isNotEmpty) {
          occupiedIds.add(nid);
          final name = (t['full_name'] ?? t['fullName'])?.toString().trim();
          if (name != null && name.isNotEmpty) {
            tenantByNodeId[nid] = name;
          }
        }
      }
    }

    final units = <AssignableUnit>[];
    final seen = <String>{};

    Future<List<Map<String, dynamic>>> nodesAt(
      String levelId,
      String? parentNodeId,
    ) {
      return structureRepo.listNodes(
        propertyId,
        levelId,
        parentNodeId: parentNodeId,
      );
    }

    Future<void> collectSameLevelTree({
      required HierarchyLevel level,
      required String parentNodeId,
      required List<String> pathParts,
    }) async {
      final children = await nodesAt(level.id, parentNodeId);
      for (final node in children) {
        final id = node['id']?.toString() ?? '';
        if (id.isEmpty || seen.contains(id)) continue;
        final name = node['name']?.toString() ?? 'Untitled';
        final path = [...pathParts, name];
        final nested = await nodesAt(level.id, id);
        final spaceType = (node['spaceType'] ??
                node['space_type'] ??
                node['metadata']?['space_type'])
            ?.toString();

        final isContainerFloor =
            (spaceType == 'floor' || spaceType == 'portion') &&
                nested.isNotEmpty;

        if (!isContainerFloor) {
          seen.add(id);
          units.add(_unitFromNode(
            node: node,
            id: id,
            name: name,
            levelName: level.displayName,
            pathLabel: path.join(' · '),
            occupiedIds: occupiedIds,
            tenantByNodeId: tenantByNodeId,
          ));
        }

        if (nested.isNotEmpty) {
          await collectSameLevelTree(
            level: level,
            parentNodeId: id,
            pathParts: path,
          );
        }
      }
    }

    Future<void> walk(
      HierarchyLevel level,
      String? parentNodeId,
      List<String> pathParts,
    ) async {
      final nodes = await nodesAt(level.id, parentNodeId);

      for (final node in nodes) {
        final name = node['name']?.toString() ?? 'Untitled';
        final id = node['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final path = [...pathParts, name];

        if (isAssignableLevel(level.id, levels)) {
          final nested = await nodesAt(level.id, id);
          final spaceType = (node['spaceType'] ??
                  node['space_type'] ??
                  node['metadata']?['space_type'])
              ?.toString();
          final isContainerFloor =
              (spaceType == 'floor' || spaceType == 'portion') &&
                  nested.isNotEmpty;

          if (!isContainerFloor && !seen.contains(id)) {
            seen.add(id);
            units.add(_unitFromNode(
              node: node,
              id: id,
              name: name,
              levelName: level.displayName,
              pathLabel: path.join(' · '),
              occupiedIds: occupiedIds,
              tenantByNodeId: tenantByNodeId,
            ));
          }

          if (nested.isNotEmpty) {
            await collectSameLevelTree(
              level: level,
              parentNodeId: id,
              pathParts: path,
            );
          }
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

    for (final level in levels) {
      if (!isAssignableLevel(level.id, levels)) continue;
      final orphans = await nodesAt(level.id, null);
      for (final node in orphans) {
        final id = node['id']?.toString() ?? '';
        if (id.isEmpty || seen.contains(id)) continue;
        final name = node['name']?.toString() ?? 'Untitled';
        seen.add(id);
        units.add(_unitFromNode(
          node: node,
          id: id,
          name: name,
          levelName: level.displayName,
          pathLabel: name,
          occupiedIds: occupiedIds,
          tenantByNodeId: tenantByNodeId,
        ));
        await collectSameLevelTree(
          level: level,
          parentNodeId: id,
          pathParts: [name],
        );
      }
    }

    units.sort((a, b) => a.pathLabel.compareTo(b.pathLabel));
    return units;
  },
);

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
