// features/structure/presentation/property_structure_tab_screen.dart
//
// Dynamic Rooms explorer — mirrors whatever hierarchy the property actually
// has (Villa units, Hostel Building→Floor→Room→Bed, Rental Shop/Flat, etc.).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
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

const _occupiedGreen = Color(0xFF22C55E);

enum _RoomsVacancyFilter { all, vacant, occupied }

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
  final _searchController = TextEditingController();
  bool _didAutoExpand = false;
  bool _showSearch = false;
  String _searchQuery = '';
  _RoomsVacancyFilter _vacancyFilter = _RoomsVacancyFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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
      NodeDetailScreen.route(
        propertyId: widget.propertyId,
        nodeId: leaf.id,
        nodeName: leaf.name,
        levelName: leaf.level.displayName,
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

  void _toggleExpandAll(List<RoomsTreeNode> buildings) {
    final ids = buildings.map((b) => b.id).toSet();
    final allOpen = ids.every(_expanded.contains);
    setState(() {
      if (allOpen) {
        _expanded.removeAll(ids);
      } else {
        _expanded.addAll(ids);
      }
    });
  }

  Future<void> _pickVacancyFilter() async {
    final picked = await showModalBottomSheet<_RoomsVacancyFilter>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Filter buildings',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ),
              ListTile(
                title: const Text('All buildings'),
                trailing: _vacancyFilter == _RoomsVacancyFilter.all
                    ? const Icon(Icons.check, color: AppColors.blueprint)
                    : null,
                onTap: () => Navigator.pop(ctx, _RoomsVacancyFilter.all),
              ),
              ListTile(
                title: const Text('Has vacant rooms'),
                trailing: _vacancyFilter == _RoomsVacancyFilter.vacant
                    ? const Icon(Icons.check, color: AppColors.blueprint)
                    : null,
                onTap: () => Navigator.pop(ctx, _RoomsVacancyFilter.vacant),
              ),
              ListTile(
                title: const Text('Fully occupied'),
                trailing: _vacancyFilter == _RoomsVacancyFilter.occupied
                    ? const Icon(Icons.check, color: AppColors.blueprint)
                    : null,
                onTap: () => Navigator.pop(ctx, _RoomsVacancyFilter.occupied),
              ),
              if (widget.canManage)
                ListTile(
                  leading: const Icon(Icons.tune, color: AppColors.slate),
                  title: const Text('Structure settings'),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.push('/dashboard/${widget.propertyId}/structure');
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (picked != null) {
      setState(() => _vacancyFilter = picked);
    }
  }

  List<RoomsTreeNode> _visibleBuildings(List<RoomsTreeNode> buildings) {
    final q = _searchQuery.trim().toLowerCase();
    return buildings.where((b) {
      if (q.isNotEmpty) {
        final inName = b.name.toLowerCase().contains(q);
        final inFloor = b.children.any(
          (c) => c.name.toLowerCase().contains(q),
        );
        if (!inName && !inFloor) return false;
      }
      final occ = RoomOccupancySummary.fromNode(b);
      switch (_vacancyFilter) {
        case _RoomsVacancyFilter.all:
          return true;
        case _RoomsVacancyFilter.vacant:
          return occ.available > 0;
        case _RoomsVacancyFilter.occupied:
          return occ.total > 0 && occ.available == 0;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final treeAsync = ref.watch(roomsTreeProvider(widget.propertyId));

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: treeAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('Something went wrong: $err')),
          data: (tree) {
            final hasUnits = tree.assignableUnitCount > 0;

            if (!hasUnits) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _RoomsHeader(
                    showSearch: _showSearch,
                    searchController: _searchController,
                    onSearchChanged: (v) =>
                        setState(() => _searchQuery = v),
                    onToggleSearch: () => setState(() {
                      _showSearch = !_showSearch;
                      if (!_showSearch) {
                        _searchController.clear();
                        _searchQuery = '';
                      }
                    }),
                    onFilter: _pickVacancyFilter,
                  ),
                  Expanded(
                    child: _PremiumRoomsEmptyState(
                      canManage: widget.canManage,
                      onAddFirstRoom: _openAddRoom,
                    ),
                  ),
                ],
              );
            }

            _maybeAutoExpand(tree.roots);

            final overall = _aggregateOccupancy(tree.roots);
            final buildings = tree.roots.where((n) => !n.isAssignable).toList();
            final visible = _visibleBuildings(buildings);
            final allExpanded = visible.isNotEmpty &&
                visible.every((b) => _expanded.contains(b.id));

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _RoomsHeader(
                  showSearch: _showSearch,
                  searchController: _searchController,
                  onSearchChanged: (v) => setState(() => _searchQuery = v),
                  onToggleSearch: () => setState(() {
                    _showSearch = !_showSearch;
                    if (!_showSearch) {
                      _searchController.clear();
                      _searchQuery = '';
                    }
                  }),
                  onFilter: _pickVacancyFilter,
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      _RoomsSummaryCard(summary: overall),
                      const SizedBox(height: 16),
                      if (tree.isFlatLeafForest)
                        buildRoomGrid(context, tree.roots, _openLeaf)
                      else ...[
                        _BuildingsListHeader(
                          count: visible.length,
                          allExpanded: allExpanded,
                          onToggleExpandAll: visible.isEmpty
                              ? null
                              : () => _toggleExpandAll(visible),
                        ),
                        const SizedBox(height: 10),
                        if (visible.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 32),
                            child: Center(
                              child: Text(
                                'No buildings match your search.',
                                style: TextStyle(color: AppColors.slate),
                              ),
                            ),
                          )
                        else
                          _HierarchyBranch(
                            nodes: visible,
                            levels: tree.levels,
                            expanded: _expanded,
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
                            findRootBuildingLevel(tree.levels) != null) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: _addBuilding,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.blueprint,
                                side: const BorderSide(
                                  color: AppColors.blueprint,
                                  width: 1.4,
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: const StadiumBorder(),
                              ),
                              child: const Text(
                                '+ Add New Building',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

RoomOccupancySummary _aggregateOccupancy(List<RoomsTreeNode> nodes) {
  var total = 0;
  var occupied = 0;
  for (final n in nodes) {
    final s = RoomOccupancySummary.fromNode(n);
    total += s.total;
    occupied += s.occupied;
  }
  return RoomOccupancySummary(total: total, occupied: occupied);
}

int _occupancyPercent(RoomOccupancySummary s) {
  if (s.total <= 0) return 0;
  return ((s.occupied / s.total) * 100).round();
}

String _floorCountLabel(RoomsTreeNode building) {
  final floors = building.children.length;
  return '$floors Floor${floors == 1 ? '' : 's'}';
}

class _RoomsHeader extends StatelessWidget {
  final bool showSearch;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onToggleSearch;
  final VoidCallback onFilter;

  const _RoomsHeader({
    required this.showSearch,
    required this.searchController,
    required this.onSearchChanged,
    required this.onToggleSearch,
    required this.onFilter,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Rooms',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                        height: 1.1,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Manage your buildings, floors and rooms',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.slate,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Search',
                onPressed: onToggleSearch,
                icon: Icon(
                  showSearch ? Icons.close : Icons.search,
                  color: AppColors.ink,
                ),
              ),
              IconButton(
                tooltip: 'Filter',
                onPressed: onFilter,
                icon: const Icon(Icons.tune, color: AppColors.ink),
              ),
            ],
          ),
          if (showSearch) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextField(
                controller: searchController,
                onChanged: onSearchChanged,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search buildings or floors...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  filled: true,
                  fillColor: AppColors.canvas,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RoomsSummaryCard extends StatelessWidget {
  final RoomOccupancySummary summary;

  const _RoomsSummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final pct = _occupancyPercent(summary);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: _SummarySegment(
                leading: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.bed_outlined,
                    size: 18,
                    color: AppColors.blueprint,
                  ),
                ),
                value: '${summary.total}',
                label: 'Total Rooms',
              ),
            ),
            VerticalDivider(color: Colors.grey.shade300, width: 16, thickness: 1),
            Expanded(
              child: _SummarySegment(
                leading: const _StatusDot(color: _occupiedGreen),
                value: '${summary.occupied}',
                label: 'Occupied',
              ),
            ),
            VerticalDivider(color: Colors.grey.shade300, width: 16, thickness: 1),
            Expanded(
              child: _SummarySegment(
                leading: _StatusDot(color: Colors.grey.shade400),
                value: '${summary.available}',
                label: 'Vacant',
              ),
            ),
            VerticalDivider(color: Colors.grey.shade300, width: 16, thickness: 1),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$pct%',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Occupancy',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: AppColors.slate),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: summary.total == 0 ? 0 : summary.occupied / summary.total,
                      minHeight: 4,
                      color: _occupiedGreen,
                      backgroundColor: Colors.grey.shade200,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummarySegment extends StatelessWidget {
  final Widget leading;
  final String value;
  final String label;

  const _SummarySegment({
    required this.leading,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        leading,
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: AppColors.slate),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusDot extends StatelessWidget {
  final Color color;
  const _StatusDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _BuildingsListHeader extends StatelessWidget {
  final int count;
  final bool allExpanded;
  final VoidCallback? onToggleExpandAll;

  const _BuildingsListHeader({
    required this.count,
    required this.allExpanded,
    required this.onToggleExpandAll,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'Buildings ($count)',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
        const Spacer(),
        TextButton(
          onPressed: onToggleExpandAll,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.blueprint,
            visualDensity: VisualDensity.compact,
          ),
          child: Text(
            allExpanded ? 'Collapse All' : 'Expand All',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ),
      ],
    );
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
    required this.canManage,
    required this.onToggle,
    required this.onOpenLeaf,
    required this.onRename,
    required this.onAddFloor,
    required this.onOpenFloor,
  });

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

    final units = nodes.where((n) => n.isAssignable).toList();
    final containers = nodes.where((n) => !n.isAssignable).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (units.isNotEmpty) ...[
          buildRoomGrid(context, units, onOpenLeaf),
          if (containers.isNotEmpty) const SizedBox(height: 10),
        ],
        ...containers.map((node) {
          if (isRoomParentFloorNode(node.level, levels)) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _FloorNavCard(
                floorNode: node,
                onTap: () => onOpenFloor(node),
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _BuildingCard(
              node: node,
              levels: levels,
              expanded: expanded.contains(node.id),
              canManage: canManage,
              onToggle: () => onToggle(node.id),
              onRename: () => onRename(node),
              onAddFloor: () => onAddFloor(node),
              onOpenFloor: onOpenFloor,
              onOpenLeaf: onOpenLeaf,
            ),
          );
        }),
      ],
    );
  }
}

class _BuildingCard extends StatelessWidget {
  final RoomsTreeNode node;
  final List<HierarchyLevel> levels;
  final bool expanded;
  final bool canManage;
  final VoidCallback onToggle;
  final VoidCallback onRename;
  final VoidCallback onAddFloor;
  final Future<void> Function(RoomsTreeNode) onOpenFloor;
  final Future<void> Function(RoomsTreeNode) onOpenLeaf;

  const _BuildingCard({
    required this.node,
    required this.levels,
    required this.expanded,
    required this.canManage,
    required this.onToggle,
    required this.onRename,
    required this.onAddFloor,
    required this.onOpenFloor,
    required this.onOpenLeaf,
  });

  @override
  Widget build(BuildContext context) {
    final occ = RoomOccupancySummary.fromNode(node);
    final pct = _occupancyPercent(occ);
    final subtitle = '${_floorCountLabel(node)} • ${occ.total} Room${occ.total == 1 ? '' : 's'}';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.hairline),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 4, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.business,
                        size: 22,
                        color: AppColors.blueprint,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            node.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.slate,
                            ),
                          ),
                          if (!expanded) ...[
                            const SizedBox(height: 6),
                            Text(
                              '● ${occ.occupied} Occupied  •  ${occ.available} Vacant  •  $pct% Occupancy',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.slate,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (canManage)
                      PopupMenuButton<String>(
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          Icons.more_vert,
                          color: Colors.grey.shade600,
                          size: 20,
                        ),
                        onSelected: (v) {
                          if (v == 'rename') onRename();
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'rename',
                            child: Text('Rename'),
                          ),
                        ],
                      ),
                    IconButton(
                      onPressed: onToggle,
                      icon: Icon(
                        expanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (expanded) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: _BuildingStatusRow(summary: occ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Column(
                  children: [
                    for (final child in node.children)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: isRoomParentFloorNode(child.level, levels)
                            ? _FloorNavCard(
                                floorNode: child,
                                onTap: () => onOpenFloor(child),
                              )
                            : child.isAssignable
                                ? Material(
                                    color: Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () => onOpenLeaf(child),
                                      child: ListTile(
                                        dense: true,
                                        title: Text(child.name),
                                        trailing: const Icon(
                                          Icons.chevron_right,
                                          size: 18,
                                        ),
                                      ),
                                    ),
                                  )
                                : _FloorNavCard(
                                    floorNode: child,
                                    onTap: () => onOpenFloor(child),
                                  ),
                      ),
                    if (canManage && canAddFloorUnderNode(node.level, levels))
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: onAddFloor,
                          style: TextButton.styleFrom(
                            backgroundColor: AppColors.primarySoft,
                            foregroundColor: AppColors.blueprint,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            '+ Add Floor',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BuildingStatusRow extends StatelessWidget {
  final RoomOccupancySummary summary;

  const _BuildingStatusRow({required this.summary});

  @override
  Widget build(BuildContext context) {
    final pct = _occupancyPercent(summary);
    return Row(
      children: [
        const _StatusDot(color: _occupiedGreen),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            '${summary.occupied} Occupied',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppColors.slate),
          ),
        ),
        Container(
          width: 1,
          height: 12,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          color: Colors.grey.shade300,
        ),
        _StatusDot(color: Colors.grey.shade400),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            '${summary.available} Vacant',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppColors.slate),
          ),
        ),
        Container(
          width: 1,
          height: 12,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          color: Colors.grey.shade300,
        ),
        Text(
          '$pct% Occupancy',
          style: const TextStyle(fontSize: 12, color: AppColors.slate),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 48,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: summary.total == 0 ? 0 : summary.occupied / summary.total,
              minHeight: 4,
              color: _occupiedGreen,
              backgroundColor: Colors.grey.shade200,
            ),
          ),
        ),
      ],
    );
  }
}

class _FloorNavCard extends StatelessWidget {
  final RoomsTreeNode floorNode;
  final VoidCallback onTap;

  const _FloorNavCard({
    required this.floorNode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final occ = RoomOccupancySummary.fromNode(floorNode);
    final roomCount = countRoomsOnFloor(floorNode);
    final subtitle = roomCount == 0
        ? 'No rooms yet'
        : '$roomCount Room${roomCount == 1 ? '' : 's'} • ${occ.occupied} Occupied • ${occ.available} Vacant';

    return Material(
      color: Colors.grey.shade50,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            children: [
              const Icon(Icons.layers, size: 22, color: AppColors.blueprint),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      floorNode.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.slate,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade500, size: 20),
            ],
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
