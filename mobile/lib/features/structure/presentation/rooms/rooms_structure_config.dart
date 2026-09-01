// features/structure/presentation/rooms/rooms_structure_config.dart
//
// Derives which hierarchy pickers the Add Room form should show from enabled levels.

import '../../../tenancies/domain/assignable_unit.dart';
import '../../data/structure_repository.dart';
import '../../domain/hierarchy_level.dart';
import '../../../properties/domain/property_monetization.dart';

class RoomFormConfig {
  /// Non-assignable ancestors of the room level (Building, Floor, …).
  final List<HierarchyLevel> hierarchyPickers;
  final HierarchyLevel roomLevel;
  final HierarchyLevel? bedLevel;

  const RoomFormConfig({
    required this.hierarchyPickers,
    required this.roomLevel,
    this.bedLevel,
  });

  bool get showBedCapacity => bedLevel != null;

  static RoomFormConfig? fromLevels(List<HierarchyLevel> levels) {
    if (levels.isEmpty) return null;

    final roomLevel = _resolveRoomLevel(levels);
    if (roomLevel == null) return null;

    final bedLevel = levels
        .where((l) =>
            l.isEnabled &&
            l.parentLevelId == roomLevel.id &&
            l.internalKey == 'bed')
        .firstOrNull;

    final pickers = _parentChainToRoot(roomLevel, levels)
        .where((l) => l.isEnabled && !isAssignableLevel(l.id, levels))
        .toList();

    return RoomFormConfig(
      hierarchyPickers: pickers,
      roomLevel: roomLevel,
      bedLevel: bedLevel,
    );
  }
}

HierarchyLevel? _resolveRoomLevel(List<HierarchyLevel> levels) {
  final enabled = levels.where((l) => l.isEnabled).toList();

  final room = enabled.where((l) => l.internalKey == 'room').firstOrNull;
  if (room != null) return room;

  final flat = enabled.where((l) => l.internalKey == 'flat').firstOrNull;
  if (flat != null) return flat;

  final shop = enabled.where((l) => l.internalKey == 'shop').firstOrNull;
  if (shop != null) return shop;

  // Single assignable level (villa unit, etc.) — treat as the “room” target.
  final assignable = enabled.where((l) => isAssignableLevel(l.id, levels)).toList();
  if (assignable.length == 1) return assignable.first;

  // Room is non-assignable when beds exist underneath (hostel).
  final roomParentOfBed = enabled
      .where((l) =>
          l.internalKey == 'room' ||
          enabled.any((c) => c.parentLevelId == l.id && c.internalKey == 'bed'))
      .firstOrNull;
  if (roomParentOfBed != null && !isAssignableLevel(roomParentOfBed.id, levels)) {
    return roomParentOfBed;
  }

  return assignable.firstOrNull;
}

List<HierarchyLevel> _parentChainToRoot(
  HierarchyLevel target,
  List<HierarchyLevel> levels,
) {
  final chain = <HierarchyLevel>[];
  var walk = target;
  while (walk.parentLevelId != null) {
    final parent =
        levels.where((l) => l.id == walk.parentLevelId).firstOrNull;
    if (parent == null) break;
    chain.insert(0, parent);
    walk = parent;
  }
  return chain;
}

String defaultNameForLevel(HierarchyLevel level) {
  final key = level.internalKey.toLowerCase();
  if (key.contains('floor')) return 'Ground Floor';
  if (PropertyMonetization.isBuildingLevel(level.internalKey)) {
    return 'Main ${level.displayName}';
  }
  if (key.contains('room')) return 'Room 1';
  if (key.contains('bed')) return 'Bed 1';
  if (key.contains('flat')) return 'Flat 1';
  if (key.contains('shop')) return 'Shop 1';
  return level.displayName;
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}

/// Sentinel value for "+ Add new …" dropdown rows.
const kAddNewPickerValue = '__add_new__';

/// A selectable parent container for rooms (e.g. Floor, with optional Building prefix).
class RoomParentOption {
  final String nodeId;
  final String label;

  const RoomParentOption({required this.nodeId, required this.label});
}

/// Direct parent level of the room (typically Floor).
HierarchyLevel? resolveRoomParentLevel(
  List<HierarchyLevel> levels,
  HierarchyLevel roomLevel,
) {
  if (roomLevel.parentLevelId == null) return null;
  return levels.where((l) => l.id == roomLevel.parentLevelId).firstOrNull;
}

/// Loads every existing room-parent node (e.g. all Floors across Buildings).
Future<List<RoomParentOption>> loadAllRoomParentOptions({
  required StructureRepository repo,
  required String propertyId,
  required RoomFormConfig config,
  required List<HierarchyLevel> levels,
}) async {
  final parentLevel = resolveRoomParentLevel(levels, config.roomLevel);
  if (parentLevel == null || !parentLevel.isEnabled) return [];

  final ancestors = _parentChainToRoot(parentLevel, levels)
      .where((l) => l.isEnabled)
      .toList();

  Future<List<RoomParentOption>> walk(
    int ancestorIndex,
    String? parentNodeId,
    String prefix,
  ) async {
    if (ancestorIndex < ancestors.length) {
      final level = ancestors[ancestorIndex];
      final nodes = await repo.listNodes(
        propertyId,
        level.id,
        parentNodeId: parentNodeId,
      );
      final out = <RoomParentOption>[];
      for (final n in nodes) {
        final id = n['id']?.toString() ?? '';
        final name = n['name']?.toString() ?? '';
        final nextPrefix = prefix.isEmpty ? name : '$prefix · $name';
        out.addAll(await walk(ancestorIndex + 1, id, nextPrefix));
      }
      return out;
    }

    final nodes = await repo.listNodes(
      propertyId,
      parentLevel.id,
      parentNodeId: parentNodeId,
    );
    return nodes.map((n) {
      final name = n['name']?.toString() ?? '';
      final id = n['id']?.toString() ?? '';
      return RoomParentOption(
        nodeId: id,
        label: prefix.isEmpty ? name : '$prefix · $name',
      );
    }).toList();
  }

  return walk(0, null, '');
}

bool isFloorLevel(HierarchyLevel level) =>
    level.internalKey.toLowerCase().contains('floor');

bool isBuildingContainerLevel(HierarchyLevel level) =>
    PropertyMonetization.isBuildingLevel(level.internalKey);

/// Enabled floor level directly under a building (or similar container).
HierarchyLevel? findFloorChildLevel(
  HierarchyLevel containerLevel,
  List<HierarchyLevel> levels,
) {
  return levels
      .where((l) =>
          l.isEnabled &&
          l.parentLevelId == containerLevel.id &&
          isFloorLevel(l))
      .firstOrNull;
}

/// Root-level building tier when configured.
HierarchyLevel? findRootBuildingLevel(List<HierarchyLevel> levels) {
  return levels
      .where((l) =>
          l.isEnabled &&
          l.parentLevelId == null &&
          isBuildingContainerLevel(l))
      .firstOrNull;
}

bool isRoomParentFloorNode(
  HierarchyLevel nodeLevel,
  List<HierarchyLevel> levels,
) {
  final config = RoomFormConfig.fromLevels(levels);
  if (config == null) return isFloorLevel(nodeLevel);
  final parentLevel = resolveRoomParentLevel(levels, config.roomLevel);
  return parentLevel != null && parentLevel.id == nodeLevel.id;
}

bool canAddFloorUnderNode(
  HierarchyLevel nodeLevel,
  List<HierarchyLevel> levels,
) {
  return findFloorChildLevel(nodeLevel, levels) != null;
}
