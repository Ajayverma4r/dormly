// features/tenancies/domain/assignable_unit.dart
//
// A hierarchy node that can receive a tenant/resident assignment.

import '../../structure/domain/hierarchy_level.dart';

class AssignableUnit {
  final String nodeId;
  final String nodeName;
  final String levelName;
  final String pathLabel;
  final bool occupied;

  const AssignableUnit({
    required this.nodeId,
    required this.nodeName,
    required this.levelName,
    required this.pathLabel,
    required this.occupied,
  });
}

/// Whether tenants can be assigned directly to nodes at this hierarchy level.
bool isAssignableLevel(String levelId, List<HierarchyLevel> levels) {
  final level = levels.where((l) => l.id == levelId).firstOrNull;
  if (level == null) return false;
  if (level.supportsOccupancy) return true;
  return !_hasOccupancyDescendant(levelId, levels);
}

bool _hasOccupancyDescendant(String levelId, List<HierarchyLevel> levels) {
  for (final l in levels) {
    if (l.parentLevelId == levelId) {
      if (l.supportsOccupancy) return true;
      if (_hasOccupancyDescendant(l.id, levels)) return true;
    }
  }
  return false;
}

/// Human-readable hint when a node cannot receive a tenant.
String? nonAssignableReason(String levelId, List<HierarchyLevel> levels) {
  if (!_hasOccupancyDescendant(levelId, levels)) return null;
  final child = _firstOccupancyDescendant(levelId, levels);
  final level = levels.where((l) => l.id == levelId).firstOrNull;
  if (child != null && level != null) {
    return 'Assign tenants to a specific ${child.displayName} under this ${level.displayName}.';
  }
  return 'Assign tenants to a more specific unit under this section.';
}

HierarchyLevel? _firstOccupancyDescendant(
    String levelId, List<HierarchyLevel> levels) {
  for (final l in levels) {
    if (l.parentLevelId == levelId) {
      if (l.supportsOccupancy) return l;
      final deeper = _firstOccupancyDescendant(l.id, levels);
      if (deeper != null) return deeper;
    }
  }
  return null;
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
