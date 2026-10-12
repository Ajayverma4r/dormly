// features/structure/presentation/rooms/room_list_filter.dart
//
// Shared by the Rooms tab list and the Dashboard occupancy stats so both
// count the same rooms / flats from roomsTreeProvider.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'room_grid.dart';
import 'rooms_structure_config.dart';
import 'rooms_tree_provider.dart';

enum RoomListFilter { all, occupied, vacant }

/// Selected filter on the Rooms tab. The Dashboard writes it before
/// switching tabs so the list opens pre-filtered.
final roomListFilterProvider =
    StateProvider.autoDispose.family<RoomListFilter, String>(
  (ref, propertyId) => RoomListFilter.all,
);

class RoomListEntry {
  final RoomsTreeNode room;
  final String blockName;

  const RoomListEntry({required this.room, required this.blockName});

  bool get isOccupied => !RoomOccupancySummary.fromNode(room).isFullyVacant;
}

class RoomListCounts {
  final int total;
  final int occupied;

  const RoomListCounts({required this.total, required this.occupied});

  int get vacant => total - occupied;
}

/// Rooms (hostel) or flats (apartment) — never buildings, floors, or beds.
List<RoomListEntry> collectRoomListEntries(RoomsTree tree) {
  final out = <RoomListEntry>[];

  void walk(RoomsTreeNode node, String? blockHint) {
    if (isRoomParentFloorNode(node.level, tree.levels)) {
      for (final room in node.children) {
        final key = room.level.internalKey.toLowerCase();
        if (key.contains('bed')) continue;
        out.add(RoomListEntry(room: room, blockName: node.name));
      }
      return;
    }

    final key = node.level.internalKey.toLowerCase();
    final looksLikeRoom = node.hasBedChildren ||
        key == 'room' ||
        (node.isAssignable && !key.contains('bed'));

    if (looksLikeRoom &&
        !isBuildingContainerLevel(node.level) &&
        !isFloorLevel(node.level)) {
      out.add(RoomListEntry(room: node, blockName: blockHint ?? 'Rooms'));
      return;
    }

    final nextHint = isBuildingContainerLevel(node.level)
        ? node.name
        : (isFloorLevel(node.level) ? node.name : blockHint);
    for (final child in node.children) {
      walk(child, nextHint ?? node.name);
    }
  }

  for (final root in tree.roots) {
    walk(root, null);
  }

  if (out.isEmpty) {
    for (final root in tree.roots) {
      if (root.isAssignable || root.hasBedChildren) {
        out.add(RoomListEntry(room: root, blockName: 'Rooms'));
      } else {
        for (final child in root.children) {
          if (child.isAssignable || child.hasBedChildren) {
            out.add(RoomListEntry(room: child, blockName: root.name));
          }
        }
      }
    }
  }

  return out;
}

RoomListCounts countRoomListEntries(List<RoomListEntry> entries) {
  return RoomListCounts(
    total: entries.length,
    occupied: entries.where((e) => e.isOccupied).length,
  );
}

bool roomListEntryMatches(RoomListEntry entry, RoomListFilter filter) {
  switch (filter) {
    case RoomListFilter.all:
      return true;
    case RoomListFilter.occupied:
      return entry.isOccupied;
    case RoomListFilter.vacant:
      return !entry.isOccupied;
  }
}
