// features/tenancies/presentation/room_beds_view.dart
//
// Room detail for container nodes (e.g. a hostel Room whose tenants live on
// child Beds). Lists the room's real beds from roomsTreeProvider.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../structure/data/structure_repository.dart';
import '../../structure/domain/hierarchy_level.dart';
import '../../structure/presentation/dynamic_dashboard/dynamic_dashboard_screen.dart'
    show contextRoleProvider;
import '../../structure/presentation/rooms/room_grid.dart';
import '../../structure/presentation/rooms/rooms_tree_provider.dart';
import 'add_tenant_screen.dart' show openAddTenantFlow;
import 'node_detail_screen.dart';

class _R {
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
  static const iconWell = Color(0xFF1E2A40);
}

final _canManageRoomProvider = FutureProvider.autoDispose<bool>((ref) async {
  final role = await ref.watch(contextRoleProvider.future);
  return role == 'owner' || role == 'admin' || role == 'manager';
});

class RoomBedsScreen extends ConsumerWidget {
  final String propertyId;
  final String nodeId;
  final String nodeName;
  final HierarchyLevel level;
  final List<HierarchyLevel> levels;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const RoomBedsScreen({
    super.key,
    required this.propertyId,
    required this.nodeId,
    required this.nodeName,
    required this.level,
    required this.levels,
    required this.onRename,
    required this.onDelete,
  });

  HierarchyLevel? get _bedLevel => levels
      .where((l) => l.parentLevelId == level.id && l.supportsOccupancy)
      .firstOrNull;

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(roomsTreeProvider(propertyId));
    await ref.read(roomsTreeProvider(propertyId).future);
  }

  Future<void> _openBed(
      BuildContext context, WidgetRef ref, RoomsTreeNode bed) async {
    await Navigator.of(context).push(
      NodeDetailScreen.route(
        propertyId: propertyId,
        nodeId: bed.id,
        nodeName: bed.name,
        levelName: bed.level.displayName,
      ),
    );
    ref.invalidate(roomsTreeProvider(propertyId));
  }

  Future<void> _assignTenant(
      BuildContext context, WidgetRef ref, RoomsTreeNode bed) async {
    await openAddTenantFlow(
      context: context,
      ref: ref,
      propertyId: propertyId,
      nodeId: bed.id,
    );
    ref.invalidate(roomsTreeProvider(propertyId));
  }

  Future<void> _renameBed(
      BuildContext context, WidgetRef ref, RoomsTreeNode bed) async {
    final controller = TextEditingController(text: bed.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == bed.name) return;
    try {
      await ref
          .read(structureRepositoryProvider)
          .renameNode(propertyId, bed.id, name);
      ref.invalidate(roomsTreeProvider(propertyId));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not rename: $e')));
      }
    }
  }

  Future<void> _deleteBed(
      BuildContext context, WidgetRef ref, RoomsTreeNode bed) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${bed.name}"?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(structureRepositoryProvider).deleteNode(propertyId, bed.id);
      ref.invalidate(roomsTreeProvider(propertyId));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not delete: $e')));
      }
    }
  }

  Future<void> _addBed(BuildContext context, WidgetRef ref) async {
    final bedLevel = _bedLevel;
    if (bedLevel == null) return;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add ${bedLevel.displayName}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: '${bedLevel.displayName} name',
            hintText: 'e.g. A, 1',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Add')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;

    try {
      await ref.read(structureRepositoryProvider).createNode(
            propertyId,
            levelId: bedLevel.id,
            parentNodeId: nodeId,
            name: name,
          );
      ref.invalidate(roomsTreeProvider(propertyId));
    } catch (e) {
      if (!context.mounted) return;
      final data = e is DioException ? e.response?.data : null;
      final msg = data is Map && data['error'] != null ? data['error'] : e;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not add: $msg')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final treeAsync = ref.watch(roomsTreeProvider(propertyId));
    final canManage =
        ref.watch(_canManageRoomProvider).valueOrNull ?? false;
    final bedNoun = _bedLevel?.displayName ?? 'Bed';

    return Scaffold(
      backgroundColor: _R.bg,
      appBar: AppBar(
        backgroundColor: _R.bg,
        foregroundColor: _R.textPrimary,
        surfaceTintColor: Colors.transparent,
        title: Text(nodeName),
        actions: [
          if (canManage)
            PopupMenuButton<String>(
              color: _R.cardElevated,
              onSelected: (value) {
                if (value == 'rename') onRename();
                if (value == 'delete') onDelete();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                    value: 'rename',
                    child: Text('Rename',
                        style: TextStyle(color: _R.textPrimary))),
                PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete', style: TextStyle(color: _R.red))),
              ],
            ),
        ],
      ),
      body: treeAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: _R.purple)),
        error: (err, _) => _Message(
          icon: Icons.error_outline,
          title: 'Could not load this ${level.displayName.toLowerCase()}',
          subtitle: '$err',
          actionLabel: 'Retry',
          onAction: () => _refresh(ref),
        ),
        data: (tree) {
          final room = findTreeNodeById(tree.roots, nodeId);
          final beds = room == null
              ? const <RoomsTreeNode>[]
              : (room.children.where((c) => c.isAssignable).toList()
                ..sort((a, b) => a.name
                    .toLowerCase()
                    .compareTo(b.name.toLowerCase())));
          final summary = room == null
              ? const RoomOccupancySummary(total: 0, occupied: 0)
              : RoomOccupancySummary.fromNode(room);

          return RefreshIndicator(
            color: _R.purple,
            backgroundColor: _R.card,
            onRefresh: () => _refresh(ref),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _SummaryCard(
                  name: nodeName,
                  levelName: level.displayName,
                  bedNoun: bedNoun,
                  summary: summary,
                ),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${bedNoun}s',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _R.textSecondary,
                          ),
                        ),
                      ),
                      if (canManage && _bedLevel != null && beds.isNotEmpty)
                        TextButton.icon(
                          onPressed: () => _addBed(context, ref),
                          style: TextButton.styleFrom(
                              foregroundColor: _R.purple),
                          icon: const Icon(Icons.add, size: 18),
                          label: Text('Add $bedNoun'),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                if (beds.isEmpty)
                  _Message(
                    icon: Icons.bed_outlined,
                    title: 'No ${bedNoun.toLowerCase()}s in this '
                        '${level.displayName.toLowerCase()} yet',
                    subtitle: canManage
                        ? 'Add a ${bedNoun.toLowerCase()} to start assigning tenants.'
                        : 'Ask the property owner to add ${bedNoun.toLowerCase()}s.',
                    actionLabel: canManage && _bedLevel != null
                        ? 'Add $bedNoun'
                        : null,
                    onAction: () => _addBed(context, ref),
                  )
                else
                  for (var i = 0; i < beds.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    _BedCard(
                      bed: beds[i],
                      bedNoun: bedNoun,
                      onTap: () => _openBed(context, ref, beds[i]),
                      onAssign: canManage && !beds[i].occupied
                          ? () => _assignTenant(context, ref, beds[i])
                          : null,
                      onRename: canManage
                          ? () => _renameBed(context, ref, beds[i])
                          : null,
                      onDelete: canManage
                          ? () => _deleteBed(context, ref, beds[i])
                          : null,
                    ),
                  ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String name;
  final String levelName;
  final String bedNoun;
  final RoomOccupancySummary summary;

  const _SummaryCard({
    required this.name,
    required this.levelName,
    required this.bedNoun,
    required this.summary,
  });

  @override
  Widget build(BuildContext context) {
    final vacant = summary.isFullyVacant;
    final full = summary.isFullyOccupied;
    final statusLabel = summary.total == 0
        ? 'No ${bedNoun.toLowerCase()}s'
        : vacant
            ? 'Vacant'
            : 'Occupied ${summary.occupied}/${summary.total}';
    final statusBg = vacant ? _R.greenBg : (full ? _R.redBg : _R.orangeBg);
    final statusFg = vacant ? _R.green : (full ? _R.red : _R.orange);
    final title = name.toLowerCase().contains(levelName.toLowerCase())
        ? name
        : '$levelName $name';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _R.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _R.iconWell,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.bed_outlined,
                color: vacant ? _R.green : _R.purple, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _R.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${summary.occupied}/${summary.total} '
                  '${bedNoun.toLowerCase()}s occupied',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: _R.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
        ],
      ),
    );
  }
}

class _BedCard extends StatelessWidget {
  final RoomsTreeNode bed;
  final String bedNoun;
  final VoidCallback onTap;
  final VoidCallback? onAssign;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  const _BedCard({
    required this.bed,
    required this.bedNoun,
    required this.onTap,
    this.onAssign,
    this.onRename,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final occupied = bed.occupied;
    final tenant = bed.tenantDisplayName?.trim();
    final title = bed.name.toLowerCase().contains(bedNoun.toLowerCase())
        ? bed.name
        : '$bedNoun ${bed.name}';
    final subtitle = occupied
        ? (tenant != null && tenant.isNotEmpty ? tenant : 'Tenant assigned')
        : 'No tenant assigned';

    return Material(
      color: _R.card,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _R.iconWell,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      occupied ? Icons.person_outline : Icons.bed_outlined,
                      color: occupied ? _R.purple : _R.green,
                      size: 20,
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
                            color: _R.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                occupied ? FontWeight.w600 : FontWeight.w500,
                            color: occupied
                                ? _R.textPrimary.withValues(alpha: 0.85)
                                : _R.textSecondary,
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
                      color: occupied ? _R.redBg : _R.greenBg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      occupied ? 'Occupied' : 'Vacant',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: occupied ? _R.red : _R.green,
                      ),
                    ),
                  ),
                  if (onRename != null || onDelete != null)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert,
                          color: _R.textSecondary, size: 20),
                      color: _R.cardElevated,
                      onSelected: (v) {
                        if (v == 'rename') onRename?.call();
                        if (v == 'delete') onDelete?.call();
                      },
                      itemBuilder: (_) => [
                        if (onRename != null)
                          PopupMenuItem(
                            value: 'rename',
                            child: Text('Rename $bedNoun',
                                style:
                                    const TextStyle(color: _R.textPrimary)),
                          ),
                        if (onDelete != null)
                          PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete $bedNoun',
                                style: const TextStyle(color: _R.red)),
                          ),
                      ],
                    )
                  else
                    const Icon(Icons.chevron_right,
                        color: _R.textSecondary, size: 20),
                ],
              ),
              if (onAssign != null) ...[
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: onAssign,
                  style: FilledButton.styleFrom(
                    backgroundColor: _R.purpleBright,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                  label: const Text('Assign Tenant'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _Message({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: _R.textSecondary.withValues(alpha: 0.7)),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _R.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _R.textSecondary, fontSize: 13),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAction,
              style: FilledButton.styleFrom(
                backgroundColor: _R.purpleBright,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.add, size: 18),
              label: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}
