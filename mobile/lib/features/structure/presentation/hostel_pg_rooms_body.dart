// features/structure/presentation/hostel_pg_rooms_body.dart
// Screen 4 — Hostel / PG Rooms (dark). Apartment keeps property_structure_tab_screen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../tenancies/presentation/node_detail_screen.dart';
import 'property_shell_screen.dart' show propertyDetailProvider;
import 'rooms/add_room_bottom_sheet.dart';
import 'rooms/room_grid.dart';
import 'rooms/rooms_structure_config.dart';
import 'rooms/rooms_tree_provider.dart';

class _H {
  static const bg = Color(0xFF0D1623);
  static const card = Color(0xFF151F30);
  static const cardElevated = Color(0xFF1A2438);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF94A3B8);
  static const purple = Color(0xFF8B5CF6);
  static const purpleBright = Color(0xFF7C3AED);
  static const green = Color(0xFF22C55E);
  static const greenBg = Color(0xFF14352A);
  static const orange = Color(0xFFF2835F);
  static const orangeBg = Color(0xFF3E2A22);
  static const red = Color(0xFFF87171);
  static const redBg = Color(0xFF3A1F28);
  static const border = Color(0xFF243044);
  static const iconWell = Color(0xFF1E2A40);
}

enum _RoomFilter { all, occupied, vacant }

class _RoomEntry {
  final RoomsTreeNode room;
  final String blockName;

  const _RoomEntry({required this.room, required this.blockName});
}

class HostelPgRoomsBody extends ConsumerStatefulWidget {
  final String propertyId;
  final bool canManage;

  const HostelPgRoomsBody({
    super.key,
    required this.propertyId,
    required this.canManage,
  });

  /// True for every property type — dark Rooms Screen 4 is the default.
  static bool isHostelPg(Map<String, dynamic>? property) => true;

  @override
  ConsumerState<HostelPgRoomsBody> createState() => _HostelPgRoomsBodyState();
}

class _HostelPgRoomsBodyState extends ConsumerState<HostelPgRoomsBody> {
  _RoomFilter _filter = _RoomFilter.all;

  Future<void> _refresh() async {
    ref.invalidate(roomsTreeProvider(widget.propertyId));
    await ref.read(roomsTreeProvider(widget.propertyId).future);
  }

  Future<void> _openRoom(RoomsTreeNode room) async {
    await Navigator.of(context).push(
      NodeDetailScreen.route(
        propertyId: widget.propertyId,
        nodeId: room.id,
        nodeName: room.name,
        levelName: room.level.displayName,
      ),
    );
    ref.invalidate(roomsTreeProvider(widget.propertyId));
  }

  Future<void> _openAddRoom({
    String? lockedParentNodeId,
    String? lockedParentLabel,
  }) async {
    if (!widget.canManage) return;
    final ok = await showAddRoomBottomSheet(
      context: context,
      ref: ref,
      propertyId: widget.propertyId,
      lockedParentNodeId: lockedParentNodeId,
      lockedParentLabel: lockedParentLabel,
    );
    if (ok) await _refresh();
  }

  List<_RoomEntry> _collectRooms(RoomsTree tree) {
    final out = <_RoomEntry>[];

    void walk(RoomsTreeNode node, String? blockHint) {
      if (isRoomParentFloorNode(node.level, tree.levels)) {
        for (final room in node.children) {
          final key = room.level.internalKey.toLowerCase();
          if (key.contains('bed')) continue;
          out.add(_RoomEntry(room: room, blockName: node.name));
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
        out.add(_RoomEntry(room: node, blockName: blockHint ?? 'Rooms'));
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
          out.add(_RoomEntry(room: root, blockName: 'Rooms'));
        } else {
          for (final child in root.children) {
            if (child.isAssignable || child.hasBedChildren) {
              out.add(_RoomEntry(room: child, blockName: root.name));
            }
          }
        }
      }
    }

    return out;
  }

  @override
  Widget build(BuildContext context) {
    final treeAsync = ref.watch(roomsTreeProvider(widget.propertyId));

    return ColoredBox(
      color: _H.bg,
      child: treeAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: _H.purple),
        ),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Something went wrong: $err',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _H.textSecondary),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _refresh,
                  style: TextButton.styleFrom(foregroundColor: _H.purple),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (tree) {
          final rooms = _collectRooms(tree);
          final occupiedCount = rooms
              .where((e) => !RoomOccupancySummary.fromNode(e.room).isFullyVacant)
              .length;
          final vacantCount = rooms.length - occupiedCount;

          final visible = rooms.where((e) {
            final occ = RoomOccupancySummary.fromNode(e.room);
            switch (_filter) {
              case _RoomFilter.all:
                return true;
              case _RoomFilter.occupied:
                return !occ.isFullyVacant;
              case _RoomFilter.vacant:
                return occ.isFullyVacant;
            }
          }).toList();

          final grouped = <String, List<_RoomEntry>>{};
          for (final e in visible) {
            grouped.putIfAbsent(e.blockName, () => []).add(e);
          }
          final blockNames = grouped.keys.toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: _Header(
                  count: rooms.length,
                  canManage: widget.canManage,
                  onAdd: () => _openAddRoom(),
                ),
              ),
              const SizedBox(height: 14),
              _FilterChips(
                allCount: rooms.length,
                occupiedCount: occupiedCount,
                vacantCount: vacantCount,
                selected: _filter,
                onSelected: (f) => setState(() => _filter = f),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: RefreshIndicator(
                  color: _H.purple,
                  backgroundColor: _H.card,
                  onRefresh: _refresh,
                  child: rooms.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: 280,
                              child: _EmptyState(
                                canManage: widget.canManage,
                                onAdd: () => _openAddRoom(),
                              ),
                            ),
                          ],
                        )
                      : visible.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: const [
                                SizedBox(
                                  height: 220,
                                  child: Center(
                                    child: Text(
                                      'No rooms match this filter.',
                                      style: TextStyle(color: _H.textSecondary),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                              itemCount: blockNames.length,
                              itemBuilder: (context, bi) {
                                final block = blockNames[bi];
                                final blockRooms = grouped[block]!;
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    if (bi > 0) const SizedBox(height: 8),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        4,
                                        8,
                                        4,
                                        10,
                                      ),
                                      child: Text(
                                        block,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: _H.textSecondary,
                                        ),
                                      ),
                                    ),
                                    for (var i = 0;
                                        i < blockRooms.length;
                                        i++) ...[
                                      if (i > 0) const SizedBox(height: 10),
                                      _RoomCard(
                                        entry: blockRooms[i],
                                        onTap: () =>
                                            _openRoom(blockRooms[i].room),
                                      ),
                                    ],
                                  ],
                                );
                              },
                            ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final int count;
  final bool canManage;
  final VoidCallback onAdd;

  const _Header({
    required this.count,
    required this.canManage,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Rooms',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: _H.textPrimary,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$count Rooms',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _H.textSecondary,
                ),
              ),
            ],
          ),
        ),
        if (canManage) ...[
          const SizedBox(width: 12),
          Material(
            color: _H.purpleBright,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: onAdd,
              borderRadius: BorderRadius.circular(12),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 18, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'Add Room',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _FilterChips extends StatelessWidget {
  final int allCount;
  final int occupiedCount;
  final int vacantCount;
  final _RoomFilter selected;
  final ValueChanged<_RoomFilter> onSelected;

  const _FilterChips({
    required this.allCount,
    required this.occupiedCount,
    required this.vacantCount,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _Chip(
            label: 'All ($allCount)',
            selected: selected == _RoomFilter.all,
            onTap: () => onSelected(_RoomFilter.all),
          ),
          const SizedBox(width: 8),
          _Chip(
            label: 'Occupied ($occupiedCount)',
            selected: selected == _RoomFilter.occupied,
            onTap: () => onSelected(_RoomFilter.occupied),
          ),
          const SizedBox(width: 8),
          _Chip(
            label: 'Vacant ($vacantCount)',
            selected: selected == _RoomFilter.vacant,
            onTap: () => onSelected(_RoomFilter.vacant),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _H.purple : _H.card,
      shape: StadiumBorder(
        side: BorderSide(color: selected ? _H.purple : _H.border),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : _H.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  final _RoomEntry entry;
  final VoidCallback onTap;

  const _RoomCard({
    required this.entry,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final room = entry.room;
    final occ = RoomOccupancySummary.fromNode(room);
    final vacant = occ.isFullyVacant;
    final full = occ.isFullyOccupied;
    final statusLabel = vacant
        ? 'Vacant'
        : 'Occupied ${occ.occupied}/${occ.total}';
    final statusBg = vacant
        ? _H.greenBg
        : full
            ? _H.redBg
            : _H.orangeBg;
    final statusFg = vacant
        ? _H.green
        : full
            ? _H.red
            : _H.orange;

    final title = room.name.toLowerCase().contains('room')
        ? room.name
        : 'Room ${room.name}';

    return Material(
      color: _H.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _H.iconWell,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.bed_outlined,
                  color: vacant ? _H.green : _H.purple,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _H.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      occ.total > 1
                          ? '${occ.occupied}/${occ.total} beds'
                          : (vacant ? 'Available' : '1 bed occupied'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: _H.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: statusFg,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_vert,
                  color: _H.textSecondary,
                  size: 20,
                ),
                color: _H.cardElevated,
                onSelected: (v) {
                  if (v == 'view') onTap();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'view',
                    child: Text(
                      'View room',
                      style: TextStyle(color: _H.textPrimary),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool canManage;
  final VoidCallback onAdd;

  const _EmptyState({required this.canManage, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.meeting_room_outlined,
              size: 48,
              color: _H.textSecondary.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 12),
            const Text(
              'No rooms yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _H.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add your first room to start assigning beds.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _H.textSecondary, fontSize: 13),
            ),
            if (canManage) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: onAdd,
                style: TextButton.styleFrom(foregroundColor: _H.purple),
                child: const Text('+ Add Room'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

bool hostelPgRoomsEnabled(WidgetRef ref, String propertyId) {
  final property =
      ref.watch(propertyDetailProvider(propertyId)).asData?.value;
  return HostelPgRoomsBody.isHostelPg(property);
}
