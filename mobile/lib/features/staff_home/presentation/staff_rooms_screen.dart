// features/staff_home/presentation/staff_rooms_screen.dart
//
// Read-only rooms & beds for staff: where each room is, how many beds it has
// and which are free. No editing, rent or deposit figures.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../structure/presentation/rooms/rooms_tree_provider.dart';
import '../domain/staff_rooms_summary.dart';
import 'staff_ui.dart';

enum _Occupancy { all, vacant, occupied }

class StaffRoomsScreen extends ConsumerStatefulWidget {
  final String propertyId;
  final bool asTab;

  const StaffRoomsScreen(
      {super.key, required this.propertyId, this.asTab = false});

  @override
  ConsumerState<StaffRoomsScreen> createState() => _StaffRoomsScreenState();
}

class _StaffRoomsScreenState extends ConsumerState<StaffRoomsScreen> {
  String? _building;
  _Occupancy _occupancy = _Occupancy.all;

  Future<void> _refresh() async {
    await ref
        .refresh(roomsTreeProvider(widget.propertyId).future)
        .then<void>((_) {}, onError: (_) {});
  }

  bool _matches(StaffRoom r) {
    if (_building != null && r.building != _building) return false;
    switch (_occupancy) {
      case _Occupancy.all:
        return true;
      case _Occupancy.vacant:
        return r.hasBeds ? r.vacantBeds > 0 : !r.occupied;
      case _Occupancy.occupied:
        return r.hasBeds ? r.occupiedBeds > 0 : r.occupied;
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(roomsTreeProvider(widget.propertyId));

    return Scaffold(
      backgroundColor: StaffColors.bg,
      appBar: StaffAppBar(
        title: 'Rooms & Beds',
        subtitle: 'View only',
        showBack: !widget.asTab,
      ),
      body: RefreshIndicator(
        color: StaffColors.brand,
        onRefresh: _refresh,
        child: async.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: StaffColors.brand)),
          error: (e, _) => StaffScrollableMessage(
            child: StaffErrorState(
              key: const Key('staff-rooms-error'),
              error: e,
              fallback: "Couldn't load rooms. Please try again.",
              onRetry: () =>
                  ref.invalidate(roomsTreeProvider(widget.propertyId)),
            ),
          ),
          data: (tree) {
            final summary = summarizeRooms(tree);
            if (summary.rooms.isEmpty) {
              return const StaffScrollableMessage(
                child: StaffMessage(
                  key: Key('staff-rooms-empty'),
                  icon: Icons.meeting_room_outlined,
                  title: 'No rooms set up yet',
                  subtitle:
                      'Rooms appear here once the owner or manager adds them.',
                ),
              );
            }
            final buildings = summary.buildings;
            if (_building != null && !buildings.contains(_building)) {
              _building = null;
            }
            final visible = summary.rooms.where(_matches).toList();
            final usesBeds = summary.usesBeds;

            return ListView(
              key: const Key('staff-rooms-list'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                _StatsRow(summary: summary),
                const SizedBox(height: 14),
                if (buildings.length > 1) ...[
                  _BuildingPicker(
                    buildings: buildings,
                    selected: _building,
                    onChanged: (b) => setState(() => _building = b),
                  ),
                  const SizedBox(height: 10),
                ],
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final o in _Occupancy.values) ...[
                        ChoiceChip(
                          key: Key('staff-rooms-filter-${o.name}'),
                          label: Text(switch (o) {
                            _Occupancy.all => 'All',
                            _Occupancy.vacant =>
                              usesBeds ? 'Has vacant beds' : 'Vacant',
                            _Occupancy.occupied => 'Occupied',
                          }),
                          selected: _occupancy == o,
                          onSelected: (_) => setState(() => _occupancy = o),
                          selectedColor: StaffColors.brand,
                          backgroundColor: Colors.white,
                          side: BorderSide(
                            color: _occupancy == o
                                ? StaffColors.brand
                                : StaffColors.border,
                          ),
                          showCheckmark: false,
                          labelStyle: TextStyle(
                            color: _occupancy == o
                                ? Colors.white
                                : StaffColors.ink,
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (visible.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: StaffMessage(
                      key: Key('staff-rooms-filter-empty'),
                      icon: Icons.filter_alt_off_outlined,
                      title: 'No rooms match this filter',
                    ),
                  )
                else
                  for (final r in visible) ...[
                    _RoomCard(room: r, onTap: () => _showBeds(context, r)),
                    const SizedBox(height: 10),
                  ],
              ],
            );
          },
        ),
      ),
    );
  }

  void _showBeds(BuildContext context, StaffRoom room) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _RoomSheet(room: room),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final StaffRoomsSummary summary;
  const _StatsRow({required this.summary});

  @override
  Widget build(BuildContext context) {
    final usesBeds = summary.usesBeds;
    final stats = usesBeds
        ? [
            ('Rooms', summary.totalRooms, StaffColors.brand),
            ('Beds', summary.totalBeds, const Color(0xFF2563EB)),
            ('Occupied', summary.occupiedBeds, StaffColors.warning),
            ('Vacant', summary.vacantBeds, StaffColors.success),
          ]
        : [
            ('Units', summary.totalRooms, StaffColors.brand),
            ('Occupied', summary.occupiedRooms, StaffColors.warning),
            (
              'Vacant',
              summary.totalRooms - summary.occupiedRooms,
              StaffColors.success
            ),
          ];
    return Container(
      key: const Key('staff-rooms-stats'),
      decoration: staffCardDecoration(),
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          for (final s in stats)
            Expanded(
              child: Column(
                children: [
                  Text(
                    '${s.$2}',
                    style: TextStyle(
                        color: s.$3, fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.$1,
                    style: const TextStyle(
                        color: StaffColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BuildingPicker extends StatelessWidget {
  final List<String> buildings;
  final String? selected;
  final ValueChanged<String?> onChanged;

  const _BuildingPicker(
      {required this.buildings,
      required this.selected,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: staffCardDecoration(radius: 12),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          key: const Key('staff-rooms-building'),
          value: selected,
          isExpanded: true,
          icon: const Icon(Icons.expand_more_rounded, color: StaffColors.muted),
          items: [
            const DropdownMenuItem<String?>(
                value: null, child: Text('All buildings')),
            for (final b in buildings)
              DropdownMenuItem<String?>(
                value: b,
                child: Text(b, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  final StaffRoom room;
  final VoidCallback onTap;

  const _RoomCard({required this.room, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final r = room;
    final (statusLabel, fg, bg) = _statusOf(r);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('staff-room-${r.id}'),
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          decoration: staffCardDecoration(),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: StaffColors.brandSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  r.hasBeds
                      ? Icons.bed_outlined
                      : Icons.door_front_door_outlined,
                  color: StaffColors.brand,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: StaffColors.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w700),
                    ),
                    if (r.section.isNotEmpty)
                      Text(
                        r.section,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: StaffColors.muted, fontSize: 12),
                      ),
                    if (r.hasBeds) ...[
                      const SizedBox(height: 8),
                      _BedDots(total: r.totalBeds, occupied: r.occupiedBeds),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  StaffPill(label: statusLabel, fg: fg, bg: bg),
                  if (r.hasBeds) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${r.occupiedBeds}/${r.totalBeds} beds',
                      style: const TextStyle(
                          color: StaffColors.muted,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

(String, Color, Color) _statusOf(StaffRoom r) {
  if (r.hasBeds) {
    if (r.occupiedBeds == 0) {
      return ('Vacant', StaffColors.success, StaffColors.successSoft);
    }
    if (r.vacantBeds == 0) {
      return ('Full', StaffColors.danger, StaffColors.dangerSoft);
    }
    return (
      '${r.vacantBeds} free',
      StaffColors.warning,
      StaffColors.warningSoft
    );
  }
  return r.occupied
      ? ('Occupied', StaffColors.danger, StaffColors.dangerSoft)
      : ('Vacant', StaffColors.success, StaffColors.successSoft);
}

class _BedDots extends StatelessWidget {
  final int total;
  final int occupied;
  const _BedDots({required this.total, required this.occupied});

  @override
  Widget build(BuildContext context) {
    const maxDots = 12;
    final shown = total.clamp(0, maxDots);
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (var i = 0; i < shown; i++)
          Icon(
            Icons.bed_rounded,
            size: 15,
            color: i < occupied ? StaffColors.brand : StaffColors.border,
          ),
        if (total > maxDots)
          Text('+${total - maxDots}',
              style: const TextStyle(color: StaffColors.muted, fontSize: 11)),
      ],
    );
  }
}

class _RoomSheet extends StatelessWidget {
  final StaffRoom room;
  const _RoomSheet({required this.room});

  @override
  Widget build(BuildContext context) {
    final r = room;
    final beds = r.beds;
    return SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: ListView(
          key: const Key('staff-room-sheet'),
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Text(
              r.name,
              style: const TextStyle(
                  color: StaffColors.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w800),
            ),
            if (r.section.isNotEmpty)
              Text(r.section,
                  style:
                      const TextStyle(color: StaffColors.muted, fontSize: 13)),
            const SizedBox(height: 14),
            if (beds.isEmpty)
              _SheetRow(
                icon: r.hasBeds
                    ? Icons.bed_outlined
                    : Icons.door_front_door_outlined,
                title: r.hasBeds
                    ? '${r.occupiedBeds} of ${r.totalBeds} beds occupied'
                    : (r.occupied ? 'Occupied' : 'Vacant'),
                subtitle: r.node.tenantDisplayName,
                occupied: r.occupied,
              )
            else
              for (final b in beds)
                _SheetRow(
                  icon: Icons.bed_outlined,
                  title: b.name,
                  subtitle: b.occupied
                      ? (b.tenantDisplayName ?? 'Occupied')
                      : 'Vacant',
                  occupied: b.occupied,
                ),
          ],
        ),
      ),
    );
  }
}

class _SheetRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool occupied;

  const _SheetRow(
      {required this.icon,
      required this.title,
      required this.occupied,
      this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: StaffColors.bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: occupied ? StaffColors.brand : StaffColors.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: StaffColors.ink, fontWeight: FontWeight.w700)),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(subtitle!,
                        style: const TextStyle(
                            color: StaffColors.muted, fontSize: 12)),
                ],
              ),
            ),
            StaffPill(
              label: occupied ? 'Occupied' : 'Vacant',
              fg: occupied ? StaffColors.brand : StaffColors.success,
              bg: occupied ? StaffColors.brandSoft : StaffColors.successSoft,
            ),
          ],
        ),
      ),
    );
  }
}
