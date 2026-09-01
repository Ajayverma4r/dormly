// features/structure/presentation/rooms/floor_detail_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../tenancies/presentation/node_detail_screen.dart';
import 'add_room_bottom_sheet.dart';
import 'bulk_add_rooms_sheet.dart';
import 'room_grid.dart';
import 'rooms_tree_provider.dart';

class FloorDetailScreen extends ConsumerStatefulWidget {
  final String propertyId;
  final String floorId;
  final String floorName;
  final bool canManage;

  const FloorDetailScreen({
    super.key,
    required this.propertyId,
    required this.floorId,
    required this.floorName,
    required this.canManage,
  });

  @override
  ConsumerState<FloorDetailScreen> createState() => _FloorDetailScreenState();
}

class _FloorDetailScreenState extends ConsumerState<FloorDetailScreen> {
  Future<void> _openRoom(RoomsTreeNode room) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NodeDetailScreen(
          propertyId: widget.propertyId,
          nodeId: room.id,
          nodeName: room.name,
          levelName: room.level.displayName,
        ),
      ),
    );
    ref.invalidate(roomsTreeProvider(widget.propertyId));
  }

  Future<void> _openAddRoom() async {
    final ok = await showAddRoomBottomSheet(
      context: context,
      ref: ref,
      propertyId: widget.propertyId,
      lockedParentNodeId: widget.floorId,
      lockedParentLabel: widget.floorName,
    );
    if (ok && mounted) {
      ref.invalidate(roomsTreeProvider(widget.propertyId));
    }
  }

  Future<void> _openBulkAddRooms() async {
    final ok = await showBulkAddRoomsSheet(
      context: context,
      ref: ref,
      propertyId: widget.propertyId,
      lockedParentNodeId: widget.floorId,
      lockedParentLabel: widget.floorName,
    );
    if (ok && mounted) {
      ref.invalidate(roomsTreeProvider(widget.propertyId));
    }
  }

  Future<void> _showAddRoomMenu() async {
    if (!widget.canManage) return;

    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'Add rooms on ${widget.floorName}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: AppColors.ink,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.meeting_room_outlined),
              title: const Text('Add Single Room'),
              onTap: () => Navigator.pop(ctx, 'single'),
            ),
            ListTile(
              leading: const Icon(Icons.grid_on_outlined),
              title: const Text('Bulk Add Rooms'),
              onTap: () => Navigator.pop(ctx, 'bulk'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (choice == 'single') await _openAddRoom();
    if (choice == 'bulk') await _openBulkAddRooms();
  }

  @override
  Widget build(BuildContext context) {
    final treeAsync = ref.watch(roomsTreeProvider(widget.propertyId));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.floorName),
      ),
      body: treeAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Something went wrong: $err')),
        data: (tree) {
          final floorNode = findTreeNodeById(tree.roots, widget.floorId);
          final rooms = floorNode?.children ?? const <RoomsTreeNode>[];

          if (rooms.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.meeting_room_outlined,
                      size: 48,
                      color: AppColors.blueprint.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No rooms on ${widget.floorName} yet',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (widget.canManage) ...[
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _showAddRoomMenu,
                        icon: const Icon(Icons.add, size: 20),
                        label: const Text('Add Room'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.blueprint,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              Text(
                '${rooms.length} Room${rooms.length == 1 ? '' : 's'}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.slate,
                ),
              ),
              const SizedBox(height: 12),
              buildRoomGrid(context, rooms, _openRoom),
              if (widget.canManage) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: _showAddRoomMenu,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Room'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.blueprint,
                      alignment: Alignment.centerLeft,
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
