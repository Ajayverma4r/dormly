// features/structure/presentation/hostel_pg_rooms_body.dart
// Screen 4 — Hostel / PG Rooms (dark). Apartment keeps property_structure_tab_screen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/theme_mode.dart';

import '../../properties/domain/property_archetype.dart';
import '../../tenancies/presentation/add_tenant_screen.dart'
    show openAddTenantFlow;
import '../../tenancies/presentation/node_detail_screen.dart';
import 'property_shell_screen.dart' show propertyDetailProvider;
import 'rooms/add_room_bottom_sheet.dart';
import 'rooms/room_grid.dart';
import 'rooms/room_list_filter.dart';
import 'rooms/rooms_tree_provider.dart';

class _H {
  static Color get bg =>
      themed(const Color(0xFF0D1623), const Color(0xFFF6F7FB));
  static Color get card =>
      themed(const Color(0xFF151F30), const Color(0xFFFFFFFF));
  static Color get cardElevated =>
      themed(const Color(0xFF1A2438), const Color(0xFFFFFFFF));
  static Color get textPrimary =>
      themed(const Color(0xFFFFFFFF), const Color(0xFF111827));
  static Color get textSecondary =>
      themed(const Color(0xFF94A3B8), const Color(0xFF6B7280));
  static Color get purple =>
      themed(const Color(0xFF8B5CF6), const Color(0xFF7C3AED));
  static Color get purpleBright =>
      themed(const Color(0xFF7C3AED), const Color(0xFF7C3AED));
  static Color get green =>
      themed(const Color(0xFF22C55E), const Color(0xFF16A34A));
  static Color get greenBg =>
      themed(const Color(0xFF14352A), const Color(0xFFDCFCE7));
  static Color get orange =>
      themed(const Color(0xFFF2835F), const Color(0xFFEA580C));
  static Color get orangeBg =>
      themed(const Color(0xFF3E2A22), const Color(0xFFFFEDD5));
  static Color get red =>
      themed(const Color(0xFFF87171), const Color(0xFFDC2626));
  static Color get redBg =>
      themed(const Color(0xFF3A1F28), const Color(0xFFFEE2E2));
  static Color get border =>
      themed(const Color(0xFF243044), const Color(0xFFE5E7EB));
  static Color get iconWell =>
      themed(const Color(0xFF1E2A40), const Color(0xFFF1F0FB));
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

  Future<void> _addTenant(RoomsTreeNode unit) async {
    await openAddTenantFlow(
      context: context,
      ref: ref,
      propertyId: widget.propertyId,
      nodeId: unit.id,
    );
    if (mounted) ref.invalidate(roomsTreeProvider(widget.propertyId));
  }

  @override
  Widget build(BuildContext context) {
    final treeAsync = ref.watch(roomsTreeProvider(widget.propertyId));
    final filter = ref.watch(roomListFilterProvider(widget.propertyId));
    final property =
        ref.watch(propertyDetailProvider(widget.propertyId)).valueOrNull;
    final isFlat = propertyArchetypeFromProperty(property) ==
        PropertyArchetype.gatedCommunity;
    final noun = isFlat ? 'Flat' : 'Room';

    return ColoredBox(
      color: _H.bg,
      child: treeAsync.when(
        loading: () => Center(
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
                  style: TextStyle(color: _H.textSecondary),
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
          final rooms = collectRoomListEntries(tree);
          final counts = countRoomListEntries(rooms);

          final visible =
              rooms.where((e) => roomListEntryMatches(e, filter)).toList();

          final grouped = <String, List<RoomListEntry>>{};
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
                  count: counts.total,
                  noun: noun,
                  canManage: widget.canManage,
                  onAdd: () => _openAddRoom(),
                ),
              ),
              const SizedBox(height: 14),
              _FilterChips(
                allCount: counts.total,
                occupiedCount: counts.occupied,
                vacantCount: counts.vacant,
                selected: filter,
                onSelected: (f) => ref
                    .read(roomListFilterProvider(widget.propertyId).notifier)
                    .state = f,
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
                                noun: noun,
                                canManage: widget.canManage,
                                onAdd: () => _openAddRoom(),
                              ),
                            ),
                          ],
                        )
                      : visible.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                SizedBox(
                                  height: 220,
                                  child: Center(
                                    child: Text(
                                      _emptyFilterMessage(filter, noun),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: _H.textSecondary,
                                      ),
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
                                        style: TextStyle(
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
                                        isFlat: isFlat,
                                        onTap: () =>
                                            _openRoom(blockRooms[i].room),
                                        onAddTenant: isFlat &&
                                                widget.canManage &&
                                                !blockRooms[i].isOccupied
                                            ? () =>
                                                _addTenant(blockRooms[i].room)
                                            : null,
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

  static String _emptyFilterMessage(RoomListFilter filter, String noun) {
    final plural = '${noun.toLowerCase()}s';
    switch (filter) {
      case RoomListFilter.occupied:
        return 'No occupied $plural yet.';
      case RoomListFilter.vacant:
        return 'No vacant $plural — everything is occupied.';
      case RoomListFilter.all:
        return 'No $plural match this filter.';
    }
  }
}

class _Header extends StatelessWidget {
  final int count;
  final String noun;
  final bool canManage;
  final VoidCallback onAdd;

  const _Header({
    required this.count,
    required this.noun,
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
              Text(
                '${noun}s',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: _H.textPrimary,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$count ${noun}s',
                style: TextStyle(
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
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add, size: 18, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(
                      'Add $noun',
                      style: const TextStyle(
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
  final RoomListFilter selected;
  final ValueChanged<RoomListFilter> onSelected;

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
            selected: selected == RoomListFilter.all,
            onTap: () => onSelected(RoomListFilter.all),
          ),
          const SizedBox(width: 8),
          _Chip(
            label: 'Occupied ($occupiedCount)',
            selected: selected == RoomListFilter.occupied,
            onTap: () => onSelected(RoomListFilter.occupied),
          ),
          const SizedBox(width: 8),
          _Chip(
            label: 'Vacant ($vacantCount)',
            selected: selected == RoomListFilter.vacant,
            onTap: () => onSelected(RoomListFilter.vacant),
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
  final RoomListEntry entry;
  final bool isFlat;
  final VoidCallback onTap;
  final VoidCallback? onAddTenant;

  const _RoomCard({
    required this.entry,
    required this.isFlat,
    required this.onTap,
    this.onAddTenant,
  });

  @override
  Widget build(BuildContext context) {
    final room = entry.room;
    final occ = RoomOccupancySummary.fromNode(room);
    final vacant = occ.isFullyVacant;
    final full = occ.isFullyOccupied;
    final statusLabel = vacant
        ? 'Vacant'
        : (isFlat ? 'Occupied' : 'Occupied ${occ.occupied}/${occ.total}');
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

    final noun = isFlat ? 'Flat' : 'Room';
    final title = room.name.toLowerCase().contains(noun.toLowerCase())
        ? room.name
        : '$noun ${room.name}';
    final subtitle = isFlat
        ? (vacant
            ? 'No tenant assigned'
            : (room.tenantDisplayName ?? 'Occupied'))
        : (occ.total > 1
            ? '${occ.occupied}/${occ.total} beds'
            : (vacant ? 'Available' : '1 bed occupied'));

    final card = Material(
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
                  isFlat ? Icons.apartment_outlined : Icons.bed_outlined,
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
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _H.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
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
                icon: Icon(
                  Icons.more_vert,
                  color: _H.textSecondary,
                  size: 20,
                ),
                color: _H.cardElevated,
                onSelected: (v) {
                  if (v == 'view') onTap();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'view',
                    child: Text(
                      'View ${noun.toLowerCase()}',
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

    if (onAddTenant == null) return card;

    return Material(
      color: _H.card,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          card,
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onAddTenant,
                    style: FilledButton.styleFrom(
                      backgroundColor: _H.purpleBright,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Tenant'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onTap,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _H.textPrimary,
                      side: BorderSide(color: _H.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.description_outlined, size: 18),
                    label: const Text('View Details'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String noun;
  final bool canManage;
  final VoidCallback onAdd;

  const _EmptyState({
    required this.noun,
    required this.canManage,
    required this.onAdd,
  });

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
            Text(
              'No ${noun.toLowerCase()}s yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _H.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              noun == 'Flat'
                  ? 'Add your first flat to start assigning tenants.'
                  : 'Add your first room to start assigning beds.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _H.textSecondary, fontSize: 13),
            ),
            if (canManage) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: onAdd,
                style: TextButton.styleFrom(foregroundColor: _H.purple),
                child: Text('+ Add $noun'),
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
