// features/staff_home/domain/staff_rooms_summary.dart
//
// Read-only room/bed figures for the staff app, derived from the same
// RoomsTree the owner Rooms tab uses.

import '../../structure/presentation/rooms/rooms_tree_provider.dart';

class StaffRoom {
  final RoomsTreeNode node;

  /// Ancestor names, e.g. ['Block A', 'Floor 1'].
  final List<String> path;
  final List<RoomsTreeNode> beds;
  final int totalBeds;
  final int occupiedBeds;

  const StaffRoom({
    required this.node,
    required this.path,
    required this.beds,
    required this.totalBeds,
    required this.occupiedBeds,
  });

  String get id => node.id;
  String get name => node.name;
  String get section => path.join(' · ');
  String? get building => path.isEmpty ? null : path.first;
  bool get hasBeds => totalBeds > 0;
  int get vacantBeds => (totalBeds - occupiedBeds).clamp(0, totalBeds);

  /// A room without beds (flat, unit) is occupied when it has an active tenancy.
  bool get occupied => hasBeds ? occupiedBeds >= totalBeds : node.occupied;
}

class StaffRoomsSummary {
  final List<StaffRoom> rooms;

  const StaffRoomsSummary(this.rooms);

  int get totalRooms => rooms.length;
  int get totalBeds => rooms.fold(0, (s, r) => s + r.totalBeds);
  int get occupiedBeds => rooms.fold(0, (s, r) => s + r.occupiedBeds);
  int get vacantBeds => rooms.fold(0, (s, r) => s + r.vacantBeds);
  int get occupiedRooms => rooms.where((r) => r.occupied).length;

  /// Hostels count beds; flats and rental units count whole units.
  bool get usesBeds => totalBeds > 0;

  List<String> get buildings {
    final out = <String>[];
    for (final r in rooms) {
      final b = r.building;
      if (b != null && !out.contains(b)) out.add(b);
    }
    return out;
  }
}

StaffRoomsSummary summarizeRooms(RoomsTree tree) {
  final rooms = <StaffRoom>[];

  void walk(List<RoomsTreeNode> nodes, List<String> path) {
    for (final n in nodes) {
      final bedLevel = isBedLevel(n.level);
      if (n.totalBeds > 0) {
        rooms.add(StaffRoom(
          node: n,
          path: path,
          beds: n.children.where((c) => isBedLevel(c.level)).toList(),
          totalBeds: n.totalBeds,
          occupiedBeds: n.occupiedBeds,
        ));
      } else if (n.isAssignable && bedLevel) {
        // A bed without a room above it counts as a one-bed room.
        rooms.add(StaffRoom(
          node: n,
          path: path,
          beds: [n],
          totalBeds: 1,
          occupiedBeds: n.occupied ? 1 : 0,
        ));
      } else if (n.isAssignable) {
        rooms.add(StaffRoom(
          node: n,
          path: path,
          beds: const [],
          totalBeds: 0,
          occupiedBeds: 0,
        ));
      } else {
        walk(n.children, [...path, n.name]);
      }
    }
  }

  walk(tree.roots, const []);
  return StaffRoomsSummary(rooms);
}
