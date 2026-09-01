// features/structure/presentation/rooms/rooms_tree_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/structure_repository.dart';
import '../../domain/hierarchy_level.dart';
import '../../../tenancies/data/tenancy_repository.dart';
import '../../../tenancies/domain/assignable_unit.dart';
import '../dynamic_dashboard/dynamic_dashboard_screen.dart'
    show hierarchyLevelsProvider;

class RoomsTreeNode {
  final Map<String, dynamic> node;
  final HierarchyLevel level;
  final List<RoomsTreeNode> children;
  final bool occupied;
  final bool isAssignable;
  /// Active tenant on this assignable leaf (room/flat/bed), when applicable.
  final String? tenantDisplayName;
  /// Bed capacity stats for hostel rooms (survives tree pruning).
  final int totalBeds;
  final int occupiedBeds;

  const RoomsTreeNode({
    required this.node,
    required this.level,
    required this.children,
    required this.occupied,
    required this.isAssignable,
    this.tenantDisplayName,
    this.totalBeds = 0,
    this.occupiedBeds = 0,
  });

  String get id => node['id']?.toString() ?? '';
  String get name => node['name']?.toString() ?? 'Untitled';

  bool get isLeaf => children.isEmpty;

  bool get hasBedChildren =>
      totalBeds > 0 || _bedChildren(children).isNotEmpty;
}

class RoomsTree {
  final List<RoomsTreeNode> roots;
  final List<HierarchyLevel> levels;

  const RoomsTree({required this.roots, required this.levels});

  bool get isFlatLeafForest =>
      roots.isNotEmpty && roots.every((r) => r.isAssignable);

  int get assignableUnitCount => _countAssignableUnits(roots);
}

int _countAssignableUnits(List<RoomsTreeNode> nodes) {
  var count = 0;
  for (final n in nodes) {
    if (n.isAssignable) count++;
    count += _countAssignableUnits(n.children);
  }
  return count;
}

List<RoomsTreeNode> pruneEmptyBranches(List<RoomsTreeNode> nodes) {
  final out = <RoomsTreeNode>[];
  for (final n in nodes) {
    final kids = pruneEmptyBranches(n.children);
    if (kids.isEmpty && !n.isLeaf) continue;
    if (n.children.isEmpty) {
      out.add(n);
    } else if (kids.isNotEmpty) {
      out.add(RoomsTreeNode(
        node: n.node,
        level: n.level,
        children: kids,
        occupied: n.occupied,
        isAssignable: n.isAssignable,
        tenantDisplayName: n.tenantDisplayName,
        totalBeds: n.totalBeds,
        occupiedBeds: n.occupiedBeds,
      ));
    }
  }
  return out;
}

String _normalizeNodeId(String? id) => id?.toLowerCase().trim() ?? '';

String? _tenancyNodeId(Map<String, dynamic> tenancy) {
  final raw = tenancy['node_id'] ?? tenancy['nodeId'];
  if (raw == null) return null;
  final id = raw.toString().trim();
  return id.isEmpty ? null : _normalizeNodeId(id);
}

String? _tenancyTenantName(Map<String, dynamic> tenancy) {
  for (final key in [
    'full_name',
    'fullName',
    'user_name',
    'userName',
    'name',
  ]) {
    final value = tenancy[key]?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
  }
  final user = tenancy['user'];
  if (user is Map) {
    for (final key in ['name', 'full_name', 'fullName']) {
      final value = user[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
  }
  return null;
}

bool _isBedLevel(HierarchyLevel level) {
  final key = level.internalKey.toLowerCase();
  if (key == 'bed' || key.startsWith('bed_')) return true;
  return level.supportsOccupancy &&
      level.displayName.toLowerCase().contains('bed');
}

/// Bed leaf nodes under a room (hostel dorms).
List<RoomsTreeNode> _bedChildren(List<RoomsTreeNode> children) {
  return children.where((c) => _isBedLevel(c.level)).toList();
}

int _metadataBedCapacity(Map<String, dynamic> node) {
  final meta = node['metadata'];
  if (meta is! Map) return 0;
  final cap = meta['bed_capacity'] ?? meta['bedCapacity'];
  if (cap is int) return cap;
  if (cap is num) return cap.toInt();
  return int.tryParse(cap?.toString() ?? '') ?? 0;
}

Map<String, Map<String, dynamic>> _activeTenanciesByNodeId(
  List<Map<String, dynamic>> tenancies,
) {
  final byNode = <String, Map<String, dynamic>>{};
  for (final raw in tenancies) {
    final t = Map<String, dynamic>.from(raw);
    if (t['status']?.toString() != 'active') continue;
    final nodeId = _tenancyNodeId(t);
    if (nodeId == null || nodeId.isEmpty) continue;
    byNode.putIfAbsent(nodeId, () => t);
  }
  return byNode;
}

String? _tenantNameForNode(
  String nodeId,
  Map<String, Map<String, dynamic>> tenanciesByNodeId,
) {
  final tenancy = tenanciesByNodeId[_normalizeNodeId(nodeId)];
  return tenancy == null ? null : _tenancyTenantName(tenancy);
}

/// Tenant label for a container node: direct tenancy, or single-bed rollup.
String? _resolveNodeTenantDisplay({
  required String nodeId,
  required List<RoomsTreeNode> children,
  required Map<String, Map<String, dynamic>> tenanciesByNodeId,
}) {
  final direct = _tenantNameForNode(nodeId, tenanciesByNodeId);
  if (direct != null) return direct;

  final beds = _bedChildren(children);
  if (beds.length != 1) return null;

  return _tenantNameForNode(beds.first.id, tenanciesByNodeId);
}

bool _nodeIsOccupied(
  String nodeId,
  List<RoomsTreeNode> children,
  Set<String> occupiedIds,
) {
  if (occupiedIds.contains(_normalizeNodeId(nodeId))) return true;
  return children.any((c) => c.occupied);
}

(int total, int occupied) _bedStats(
  Map<String, dynamic> node, {
  required List<RoomsTreeNode> children,
}) {
  final beds = _bedChildren(children);
  if (beds.isNotEmpty) {
    var occupied = 0;
    for (final bed in beds) {
      if (bed.occupied) occupied++;
    }
    return (beds.length, occupied);
  }

  final capacity = _metadataBedCapacity(node);
  if (capacity <= 0) return (0, 0);

  var occupied = 0;
  for (final child in children) {
    if (child.occupied) occupied++;
  }
  return (capacity, occupied);
}

RoomsTreeNode _buildTreeNode({
  required Map<String, dynamic> node,
  required HierarchyLevel level,
  required List<RoomsTreeNode> kids,
  required bool isAssignable,
  required Set<String> occupiedIds,
  required Map<String, Map<String, dynamic>> tenanciesByNodeId,
}) {
  final id = node['id']?.toString() ?? '';
  final (totalBeds, occupiedBeds) = _bedStats(node, children: kids);

  return RoomsTreeNode(
    node: node,
    level: level,
    children: kids,
    occupied: _nodeIsOccupied(id, kids, occupiedIds),
    isAssignable: isAssignable,
    tenantDisplayName: _resolveNodeTenantDisplay(
      nodeId: id,
      children: kids,
      tenanciesByNodeId: tenanciesByNodeId,
    ),
    totalBeds: totalBeds,
    occupiedBeds: occupiedBeds,
  );
}

final roomsTreeProvider =
    FutureProvider.autoDispose.family<RoomsTree, String>((ref, propertyId) async {
  final structureRepo = ref.watch(structureRepositoryProvider);
  final tenancyRepo = ref.watch(tenancyRepositoryProvider);

  final levels = await ref.watch(hierarchyLevelsProvider(propertyId).future);
  final tenancies = await tenancyRepo.listByProperty(propertyId);

  final tenanciesByNodeId = _activeTenanciesByNodeId(tenancies);
  final occupiedIds = tenanciesByNodeId.keys.toSet();

  Future<List<RoomsTreeNode>> loadUnder(
    HierarchyLevel parentLevel,
    String parentNodeId,
  ) async {
    final childLevels =
        levels.where((l) => l.parentLevelId == parentLevel.id).toList();
    if (childLevels.isEmpty) return const [];

    final out = <RoomsTreeNode>[];
    for (final childLevel in childLevels) {
      final nodes = await structureRepo.listNodes(
        propertyId,
        childLevel.id,
        parentNodeId: parentNodeId,
      );
      for (final n in nodes) {
        final id = n['id']?.toString() ?? '';
        final kids = await loadUnder(childLevel, id);
        final isAssignable = isAssignableLevel(childLevel.id, levels);
        out.add(_buildTreeNode(
          node: n,
          level: childLevel,
          kids: kids,
          isAssignable: isAssignable,
          occupiedIds: occupiedIds,
          tenanciesByNodeId: tenanciesByNodeId,
        ));
      }
    }
    return out;
  }

  final rootLevels = levels.where((l) => l.parentLevelId == null).toList();
  final roots = <RoomsTreeNode>[];

  for (final rootLevel in rootLevels) {
    final nodes = await structureRepo.listNodes(propertyId, rootLevel.id);
    for (final n in nodes) {
      final id = n['id']?.toString() ?? '';
      final kids = await loadUnder(rootLevel, id);
      final isAssignable = isAssignableLevel(rootLevel.id, levels);
      roots.add(_buildTreeNode(
        node: n,
        level: rootLevel,
        kids: kids,
        isAssignable: isAssignable,
        occupiedIds: occupiedIds,
        tenanciesByNodeId: tenanciesByNodeId,
      ));
    }
  }

  return RoomsTree(
    roots: pruneEmptyBranches(roots),
    levels: levels,
  );
});
