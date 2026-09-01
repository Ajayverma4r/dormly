// features/structure/presentation/property_structure_tab_screen.dart
//
// Dynamic Rooms explorer — mirrors whatever hierarchy the property actually
// has (Villa units, Hostel Building→Floor→Room→Bed, Rental Shop/Flat, etc.).
// No hardcoded Building/Floor/Flat path; empty branches are pruned.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/dynamic_icon.dart';
import '../../tenancies/presentation/node_detail_screen.dart';
import '../data/structure_repository.dart';
import '../domain/hierarchy_level.dart';
import 'rooms/add_room_bottom_sheet.dart';
import 'rooms/floor_detail_screen.dart';
import 'rooms/room_grid.dart';
import 'rooms/rooms_structure_config.dart';
import 'rooms/rooms_tree_provider.dart';
import 'dynamic_dashboard/dynamic_dashboard_screen.dart'
    show hierarchyLevelsProvider;

String _childCountLabel(List<RoomsTreeNode> children) {
  if (children.isEmpty) return '';
  final counts = <String, int>{};
  for (final c in children) {
    final key = c.level.displayName;
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return counts.entries
      .map((e) => '${e.value} ${e.key}${e.value == 1 ? '' : 's'}')
      .join(' · ');
}

class PropertyStructureTabScreen extends ConsumerStatefulWidget {
  final String propertyId;
  final bool canManage;

  const PropertyStructureTabScreen({
    super.key,
    required this.propertyId,
    required this.canManage,
  });

  @override
  ConsumerState<PropertyStructureTabScreen> createState() =>
      _PropertyStructureTabScreenState();
}

class _PropertyStructureTabScreenState
    extends ConsumerState<PropertyStructureTabScreen> {
  final Set<String> _expanded = {};
  bool _didAutoExpand = false;

  /// Expand solitary paths so users land on useful content immediately
  /// (1 building → floors; 1 floor → rooms/beds; etc.).
  void _maybeAutoExpand(List<RoomsTreeNode> roots) {
    if (_didAutoExpand) return;
    _didAutoExpand = true;

    void expandChain(RoomsTreeNode node) {
      if (node.isAssignable) return;
      _expanded.add(node.id);
      if (node.children.length == 1) {
        expandChain(node.children.first);
      }
    }

    if (roots.length == 1) {
      expandChain(roots.first);
    }
  }

  Future<void> _openLeaf(RoomsTreeNode leaf) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NodeDetailScreen(
          propertyId: widget.propertyId,
          nodeId: leaf.id,
          nodeName: leaf.name,
          levelName: leaf.level.displayName,
        ),
      ),
    );
    ref.invalidate(roomsTreeProvider(widget.propertyId));
    _didAutoExpand = false;
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
    if (ok) {
      _didAutoExpand = false;
    }
  }

  Future<void> _openFloor(RoomsTreeNode floorNode) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FloorDetailScreen(
          propertyId: widget.propertyId,
          floorId: floorNode.id,
          floorName: floorNode.name,
          canManage: widget.canManage,
        ),
      ),
    );
    ref.invalidate(roomsTreeProvider(widget.propertyId));
  }

  Future<bool?> _showAddContainerDialog({
    required String title,
    required String label,
    String? initialValue,
    required Future<void> Function(String name) createNode,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => _AddContainerDialog(
        title: title,
        label: label,
        initialValue: initialValue,
        createNode: createNode,
        errorMessenger: ScaffoldMessenger.of(context),
      ),
    );
  }

  Future<void> _addFloorUnderBuilding(RoomsTreeNode buildingNode) async {
    final tree = ref.read(roomsTreeProvider(widget.propertyId)).valueOrNull;
    final levels = tree != null
        ? tree.levels
        : await ref.read(hierarchyLevelsProvider(widget.propertyId).future);
    final floorLevel = findFloorChildLevel(buildingNode.level, levels);
    if (floorLevel == null) return;

    final didSave = await _showAddContainerDialog(
      title: 'Add ${floorLevel.displayName}',
      label: '${floorLevel.displayName} name',
      initialValue: defaultNameForLevel(floorLevel),
      createNode: (name) => ref.read(structureRepositoryProvider).createNode(
            widget.propertyId,
            levelId: floorLevel.id,
            parentNodeId: buildingNode.id,
            name: name,
          ),
    );

    if (!mounted) return;

    if (didSave == true) {
      ref.invalidate(roomsTreeProvider(widget.propertyId));
      setState(() => _expanded.add(buildingNode.id));
    }
  }

  Future<void> _addBuilding() async {
    final tree = ref.read(roomsTreeProvider(widget.propertyId)).valueOrNull;
    final levels = tree != null
        ? tree.levels
        : await ref.read(hierarchyLevelsProvider(widget.propertyId).future);
    final buildingLevel = findRootBuildingLevel(levels);
    if (buildingLevel == null) return;

    final didSave = await _showAddContainerDialog(
      title: 'Add ${buildingLevel.displayName}',
      label: '${buildingLevel.displayName} name',
      initialValue: defaultNameForLevel(buildingLevel),
      createNode: (name) => ref.read(structureRepositoryProvider).createNode(
            widget.propertyId,
            levelId: buildingLevel.id,
            name: name,
          ),
    );

    if (!mounted) return;

    if (didSave == true) {
      ref.invalidate(roomsTreeProvider(widget.propertyId));
      _didAutoExpand = false;
    }
  }

  Future<void> _renameContainer(RoomsTreeNode node) async {
    final controller = TextEditingController(text: node.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Rename ${node.level.displayName}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: '${node.level.displayName} name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == node.name) return;

    try {
      await ref.read(structureRepositoryProvider).renameNode(
            widget.propertyId,
            node.id,
            newName,
          );
      ref.invalidate(roomsTreeProvider(widget.propertyId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not rename: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final treeAsync = ref.watch(roomsTreeProvider(widget.propertyId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rooms'),
        actions: [
          if (widget.canManage)
            IconButton(
              icon: const Icon(Icons.tune, size: 20),
              tooltip: 'Structure settings',
              onPressed: () =>
                  context.push('/dashboard/${widget.propertyId}/structure'),
            ),
        ],
      ),
      body: treeAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Something went wrong: $err')),
        data: (tree) {
          final hasUnits = tree.assignableUnitCount > 0;

          if (!hasUnits) {
            return _PremiumRoomsEmptyState(
              canManage: widget.canManage,
              onAddFirstRoom: _openAddRoom,
            );
          }

          _maybeAutoExpand(tree.roots);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _legend(),
              const SizedBox(height: 12),
              if (tree.isFlatLeafForest)
                _roomList(tree.roots)
              else
                _HierarchyBranch(
                  nodes: tree.roots,
                  levels: tree.levels,
                  expanded: _expanded,
                  depth: 0,
                  canManage: widget.canManage,
                  onToggle: (id) {
                    setState(() {
                      if (_expanded.contains(id)) {
                        _expanded.remove(id);
                      } else {
                        _expanded.add(id);
                      }
                    });
                  },
                  onOpenLeaf: _openLeaf,
                  onRename: _renameContainer,
                  onAddFloor: _addFloorUnderBuilding,
                  onOpenFloor: _openFloor,
                ),
              if (widget.canManage &&
                  findRootBuildingLevel(tree.levels) != null &&
                  !tree.isFlatLeafForest) ...[
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: _addBuilding,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.blueprint,
                    side: const BorderSide(color: AppColors.blueprint),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('+ Add New Building'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _legend() {
    return Row(
      children: [
        _statusDot(AppColors.positive),
        const SizedBox(width: 6),
        const Text('Occupied',
            style: TextStyle(fontSize: 12, color: AppColors.slate)),
        const SizedBox(width: 16),
        _statusDot(Colors.grey.shade400),
        const SizedBox(width: 6),
        const Text('Vacant',
            style: TextStyle(fontSize: 12, color: AppColors.slate)),
      ],
    );
  }

  Widget _statusDot(Color color) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _roomList(List<RoomsTreeNode> rooms) {
    return buildRoomGrid(context, rooms, _openLeaf);
  }
}

class _PremiumRoomsEmptyState extends StatelessWidget {
  final bool canManage;
  final VoidCallback onAddFirstRoom;

  const _PremiumRoomsEmptyState({
    required this.canManage,
    required this.onAddFirstRoom,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.blueprint.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.meeting_room_outlined,
                size: 40,
                color: AppColors.blueprint,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No units added yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Start building your property layout.',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.slate,
                height: 1.45,
              ),
              textAlign: TextAlign.center,
            ),
            if (canManage) ...[
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: onAddFirstRoom,
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Add First Room'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.blueprint,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Hierarchical Rooms explorer — Buildings expand to Floor drill-down cards.
class _HierarchyBranch extends StatelessWidget {
  final List<RoomsTreeNode> nodes;
  final List<HierarchyLevel> levels;
  final Set<String> expanded;
  final int depth;
  final bool canManage;
  final ValueChanged<String> onToggle;
  final Future<void> Function(RoomsTreeNode) onOpenLeaf;
  final Future<void> Function(RoomsTreeNode) onRename;
  final Future<void> Function(RoomsTreeNode) onAddFloor;
  final Future<void> Function(RoomsTreeNode) onOpenFloor;

  const _HierarchyBranch({
    required this.nodes,
    required this.levels,
    required this.expanded,
    required this.depth,
    required this.canManage,
    required this.onToggle,
    required this.onOpenLeaf,
    required this.onRename,
    required this.onAddFloor,
    required this.onOpenFloor,
  });

  Widget _roomList(BuildContext context, List<RoomsTreeNode> rooms) {
    return buildRoomGrid(context, rooms, onOpenLeaf);
  }

  Widget _buildContainerChild(BuildContext context, RoomsTreeNode node) {
    if (isRoomParentFloorNode(node.level, levels)) {
      return _FloorNavCard(
        floorNode: node,
        canManage: canManage,
        onTap: () => onOpenFloor(node),
        onRename: () => onRename(node),
      );
    }

    return _HierarchyBranch(
      nodes: [node],
      levels: levels,
      expanded: expanded,
      depth: depth + 1,
      canManage: canManage,
      onToggle: onToggle,
      onOpenLeaf: onOpenLeaf,
      onRename: onRename,
      onAddFloor: onAddFloor,
      onOpenFloor: onOpenFloor,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (nodes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          'Nothing added under this section yet.',
          style: TextStyle(color: AppColors.slate, fontSize: 13),
        ),
      );
    }

    if (nodes.every((n) => n.isAssignable)) {
      return _roomList(context, nodes);
    }

    final units = nodes.where((n) => n.isAssignable).toList();
    final containers = nodes.where((n) => !n.isAssignable).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (units.isNotEmpty) ...[
          _roomList(context, units),
          if (containers.isNotEmpty) const SizedBox(height: 10),
        ],
        ...containers.map((node) {
          if (isRoomParentFloorNode(node.level, levels)) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _FloorNavCard(
                floorNode: node,
                canManage: canManage,
                onTap: () => onOpenFloor(node),
                onRename: () => onRename(node),
              ),
            );
          }

          final open = expanded.contains(node.id);
          final isTop = depth == 0;
          final radius = isTop ? 16.0 : 12.0;

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: isTop ? AppColors.surface : AppColors.canvas,
              elevation: isTop ? 0 : 0,
              borderRadius: BorderRadius.circular(radius),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(
                    color: isTop ? AppColors.hairline : AppColors.hairline,
                  ),
                  boxShadow: isTop
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Theme(
                  data: Theme.of(context).copyWith(
                    dividerColor: Colors.transparent,
                    splashColor: AppColors.blueprint.withValues(alpha: 0.08),
                  ),
                  child: ExpansionTile(
                    key: ValueKey('rooms-exp-${node.id}-$open'),
                    initiallyExpanded: open,
                    onExpansionChanged: (v) => onToggle(node.id),
                    tilePadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    childrenPadding:
                        const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(radius),
                    ),
                    collapsedShape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(radius),
                    ),
                    leading: DynamicIcon(
                      name: node.level.icon,
                      colorHex: node.level.color,
                      size: isTop ? 26 : 22,
                    ),
                    title: Text(
                      node.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: isTop ? 16 : 14,
                        color: AppColors.ink,
                      ),
                    ),
                    subtitle: Text(
                      '${node.level.displayName} · ${_childCountLabel(node.children)}',
                      style: const TextStyle(fontSize: 12, color: AppColors.slate),
                    ),
                    trailing: canManage
                        ? IconButton(
                            icon: Icon(
                              Icons.edit,
                              size: 20,
                              color: Colors.grey.shade600,
                            ),
                            tooltip: 'Rename ${node.level.displayName}',
                            onPressed: () => onRename(node),
                          )
                        : null,
                    children: [
                      for (final child in node.children)
                        _buildContainerChild(context, child),
                      if (canManage && canAddFloorUnderNode(node.level, levels))
                        Padding(
                          padding: const EdgeInsets.only(
                            left: 16,
                            top: 8,
                            bottom: 8,
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () => onAddFloor(node),
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Add Floor'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.blueprint,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _FloorNavCard extends StatelessWidget {
  final RoomsTreeNode floorNode;
  final bool canManage;
  final VoidCallback onTap;
  final VoidCallback onRename;

  const _FloorNavCard({
    required this.floorNode,
    required this.canManage,
    required this.onTap,
    required this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    final roomCount = countRoomsOnFloor(floorNode);
    final roomLabel = '$roomCount Room${roomCount == 1 ? '' : 's'}';

    return Material(
      color: AppColors.canvas,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.hairline),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            leading: DynamicIcon(
              name: floorNode.level.icon,
              colorHex: floorNode.level.color,
              size: 22,
            ),
            title: Text(
              floorNode.name,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: AppColors.ink,
              ),
            ),
            subtitle: Text(
              roomLabel,
              style: const TextStyle(fontSize: 12, color: AppColors.slate),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (canManage)
                  IconButton(
                    icon: Icon(
                      Icons.edit,
                      size: 20,
                      color: Colors.grey.shade600,
                    ),
                    tooltip: 'Rename ${floorNode.level.displayName}',
                    onPressed: onRename,
                  ),
                Icon(
                  Icons.chevron_right,
                  color: Colors.grey.shade500,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Isolated dialog widget so [TextEditingController] lifecycle is tied to the
/// route — disposing it from the caller caused `'_dependents.isEmpty'` on Cancel.
class _AddContainerDialog extends StatefulWidget {
  final String title;
  final String label;
  final String? initialValue;
  final Future<void> Function(String name) createNode;
  final ScaffoldMessengerState errorMessenger;

  const _AddContainerDialog({
    required this.title,
    required this.label,
    required this.initialValue,
    required this.createNode,
    required this.errorMessenger,
  });

  @override
  State<_AddContainerDialog> createState() => _AddContainerDialogState();
}

class _AddContainerDialogState extends State<_AddContainerDialog> {
  late final TextEditingController _controller;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final name = _controller.text.trim();
    if (name.isEmpty || _saving) return;

    setState(() => _saving = true);
    try {
      await widget.createNode(name);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
      }
      widget.errorMessenger.showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
    }
  }

  void _handleCancel() {
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        enabled: !_saving,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(labelText: widget.label),
        onSubmitted: (_) => _handleSave(),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : _handleCancel,
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _handleSave,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
