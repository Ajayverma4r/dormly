// features/structure/presentation/property_structure_tab_screen.dart
//
// Dynamic Rooms explorer — mirrors whatever hierarchy the property actually
// has (Villa units, Hostel Building→Floor→Room→Bed, Rental Shop/Flat, etc.).
// No hardcoded Building/Floor/Flat path; empty branches are pruned.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/dormly_empty_state.dart';
import '../../../core/widgets/dynamic_icon.dart';
import '../../tenancies/data/tenancy_repository.dart';
import '../../tenancies/domain/assignable_unit.dart';
import '../../tenancies/presentation/node_detail_screen.dart';
import '../data/structure_repository.dart';
import '../domain/hierarchy_level.dart';
import 'dynamic_dashboard/dynamic_dashboard_screen.dart'
    show hierarchyLevelsProvider;

class _TreeNode {
  final Map<String, dynamic> node;
  final HierarchyLevel level;
  final List<_TreeNode> children;
  final bool occupied;
  final bool isAssignable;

  const _TreeNode({
    required this.node,
    required this.level,
    required this.children,
    required this.occupied,
    required this.isAssignable,
  });

  String get id => node['id']?.toString() ?? '';
  String get name => node['name']?.toString() ?? 'Untitled';

  bool get isLeaf => children.isEmpty;
}

class _RoomsTree {
  final List<_TreeNode> roots;
  final List<HierarchyLevel> levels;

  const _RoomsTree({required this.roots, required this.levels});

  /// True when the property has no nesting — only terminal assignable units.
  bool get isFlatLeafForest =>
      roots.isNotEmpty && roots.every((r) => r.isAssignable);
}

/// Drop empty intermediate nodes (e.g. a Floor with no Rooms/Beds under it)
/// so the accordion never shows hollow headers.
List<_TreeNode> _pruneEmptyBranches(List<_TreeNode> nodes) {
  final out = <_TreeNode>[];
  for (final n in nodes) {
    final kids = _pruneEmptyBranches(n.children);
    if (kids.isEmpty && !n.isLeaf) {
      // Was an intermediate with only empty descendants — skip entirely.
      // (After prune, original non-leaf with empty kids stays skipped.)
      continue;
    }
    // Re-classify: a node that had children pruned away becomes a leaf only if
    // it originally had no child *slots* filled. If it had children and all
    // were empty intermediates, we skip it above. If prune emptied kids of a
    // node that still should show… only keep if original was leaf OR kids remain.
    if (n.children.isEmpty) {
      out.add(n);
    } else if (kids.isNotEmpty) {
      out.add(_TreeNode(
        node: n.node,
        level: n.level,
        children: kids,
        occupied: n.occupied,
        isAssignable: n.isAssignable,
      ));
    }
  }
  return out;
}

String _childCountLabel(List<_TreeNode> children) {
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

final roomsTreeProvider =
    FutureProvider.autoDispose.family<_RoomsTree, String>((ref, propertyId) async {
  final structureRepo = ref.watch(structureRepositoryProvider);
  final tenancyRepo = ref.watch(tenancyRepositoryProvider);

  final levels = await ref.watch(hierarchyLevelsProvider(propertyId).future);
  final tenancies = await tenancyRepo.listByProperty(propertyId);

  final occupiedIds = <String>{};
  for (final t in tenancies) {
    if (t['status']?.toString() == 'active') {
      final nid = t['node_id']?.toString() ?? t['nodeId']?.toString();
      if (nid != null && nid.isNotEmpty) occupiedIds.add(nid);
    }
  }

  Future<List<_TreeNode>> loadUnder(
    HierarchyLevel parentLevel,
    String parentNodeId,
  ) async {
    final childLevels =
        levels.where((l) => l.parentLevelId == parentLevel.id).toList();
    if (childLevels.isEmpty) return const [];

    final out = <_TreeNode>[];
    for (final childLevel in childLevels) {
      final nodes = await structureRepo.listNodes(
        propertyId,
        childLevel.id,
        parentNodeId: parentNodeId,
      );
      for (final n in nodes) {
        final id = n['id']?.toString() ?? '';
        final kids = await loadUnder(childLevel, id);
        out.add(_TreeNode(
          node: n,
          level: childLevel,
          children: kids,
          occupied: occupiedIds.contains(id),
          isAssignable: isAssignableLevel(childLevel.id, levels),
        ));
      }
    }
    return out;
  }

  // Any enabled root level(s) — not assumed to be "Building".
  final rootLevels = levels.where((l) => l.parentLevelId == null).toList();
  final roots = <_TreeNode>[];

  for (final rootLevel in rootLevels) {
    final nodes = await structureRepo.listNodes(propertyId, rootLevel.id);
    for (final n in nodes) {
      final id = n['id']?.toString() ?? '';
      roots.add(_TreeNode(
        node: n,
        level: rootLevel,
        children: await loadUnder(rootLevel, id),
        occupied: occupiedIds.contains(id),
        isAssignable: isAssignableLevel(rootLevel.id, levels),
      ));
    }
  }

  return _RoomsTree(
    roots: _pruneEmptyBranches(roots),
    levels: levels,
  );
});

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
  void _maybeAutoExpand(List<_TreeNode> roots) {
    if (_didAutoExpand) return;
    _didAutoExpand = true;

    void expandChain(_TreeNode node) {
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

  Future<void> _openLeaf(_TreeNode leaf) async {
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
          if (tree.levels.isEmpty) {
            return DormlyEmptyState(
              title: 'No structure configured yet',
              subtitle: widget.canManage
                  ? 'Tap the settings icon above to define levels for this property.'
                  : 'Ask the property owner to configure the structure.',
              action: widget.canManage
                  ? FilledButton(
                      onPressed: () => context
                          .push('/dashboard/${widget.propertyId}/structure'),
                      child: const Text('Open Structure Settings'),
                    )
                  : null,
            );
          }

          if (tree.roots.isEmpty) {
            return DormlyEmptyState(
              title: 'Nothing to show yet',
              subtitle: widget.canManage
                  ? 'Open Structure Settings to add units for this property.'
                  : 'Nothing has been added to this property yet.',
              action: widget.canManage
                  ? FilledButton(
                      onPressed: () => context
                          .push('/dashboard/${widget.propertyId}/structure'),
                      child: const Text('Structure Settings'),
                    )
                  : null,
            );
          }

          _maybeAutoExpand(tree.roots);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _legend(),
              const SizedBox(height: 12),
              // Villa / single-level: no accordion chrome — just unit cards.
              if (tree.isFlatLeafForest)
                _leafGrid(tree.roots)
              else
                _HierarchyBranch(
                  nodes: tree.roots,
                  expanded: _expanded,
                  depth: 0,
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
                  leafGridBuilder: _leafGrid,
                ),
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

  Widget _leafGrid(List<_TreeNode> leaves) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: leaves.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.55,
      ),
      itemBuilder: (context, i) {
        final leaf = leaves[i];
        return _UnitCard(
          name: leaf.name,
          levelName: leaf.level.displayName,
          occupied: leaf.occupied,
          onTap: () => _openLeaf(leaf),
        );
      },
    );
  }
}

/// Recursively renders containers as expanders and terminals as a card grid.
/// Depth is unlimited (Building → Floor → Room → Bed, Suite → Room, etc.).
class _HierarchyBranch extends StatelessWidget {
  final List<_TreeNode> nodes;
  final Set<String> expanded;
  final int depth;
  final ValueChanged<String> onToggle;
  final Future<void> Function(_TreeNode) onOpenLeaf;
  final Widget Function(List<_TreeNode>) leafGridBuilder;

  const _HierarchyBranch({
    required this.nodes,
    required this.expanded,
    required this.depth,
    required this.onToggle,
    required this.onOpenLeaf,
    required this.leafGridBuilder,
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

    // All assignable units at this layer → grid (Beds, Flats, Shops…).
    if (nodes.every((n) => n.isAssignable)) {
      return leafGridBuilder(nodes);
    }

    final units = nodes.where((n) => n.isAssignable).toList();
    final containers = nodes.where((n) => !n.isAssignable).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (units.isNotEmpty) ...[
          leafGridBuilder(units),
          if (containers.isNotEmpty) const SizedBox(height: 10),
        ],
        ...containers.map((node) {
          final open = expanded.contains(node.id);
          final isTop = depth == 0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: isTop ? AppColors.surface : AppColors.canvas,
              borderRadius: BorderRadius.circular(isTop ? 16 : 12),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(isTop ? 16 : 12),
                  border: isTop
                      ? null
                      : Border.all(color: AppColors.hairline),
                ),
                child: Column(
                  children: [
                    _ExpanderHeader(
                      title: node.name,
                      subtitle:
                          '${node.level.displayName} · ${_childCountLabel(node.children)}',
                      icon: node.level.icon,
                      colorHex: node.level.color,
                      expanded: open,
                      dense: !isTop,
                      onToggle: () => onToggle(node.id),
                    ),
                    if (open) ...[
                      const Divider(height: 1),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          isTop ? 12 : 10,
                          8,
                          isTop ? 12 : 10,
                          isTop ? 12 : 10,
                        ),
                        child: _HierarchyBranch(
                          nodes: node.children,
                          expanded: expanded,
                          depth: depth + 1,
                          onToggle: onToggle,
                          onOpenLeaf: onOpenLeaf,
                          leafGridBuilder: leafGridBuilder,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _ExpanderHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? icon;
  final String? colorHex;
  final bool expanded;
  final bool dense;
  final VoidCallback onToggle;

  const _ExpanderHeader({
    required this.title,
    required this.subtitle,
    required this.expanded,
    required this.onToggle,
    this.icon,
    this.colorHex,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(dense ? 12 : 16),
      onTap: onToggle,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: dense ? 10 : 14,
        ),
        child: Row(
          children: [
            DynamicIcon(name: icon, colorHex: colorHex, size: dense ? 22 : 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: dense ? 14 : 16,
                      color: AppColors.ink,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.slate,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              expanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              color: AppColors.slate,
            ),
          ],
        ),
      ),
    );
  }
}

class _UnitCard extends StatelessWidget {
  final String name;
  final String levelName;
  final bool occupied;
  final VoidCallback onTap;

  const _UnitCard({
    required this.name,
    required this.levelName,
    required this.occupied,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: occupied
                          ? AppColors.positive
                          : Colors.grey.shade400,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                occupied ? 'Occupied' : 'Vacant',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: occupied ? AppColors.positive : AppColors.slate,
                ),
              ),
              Text(
                levelName,
                style: const TextStyle(fontSize: 11, color: AppColors.slate),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
