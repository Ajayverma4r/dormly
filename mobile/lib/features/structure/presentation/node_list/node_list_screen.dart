// features/structure/presentation/node_list/node_list_screen.dart
//
// Generic node browser: shows the instances of ONE hierarchy level (e.g. every
// "Building" node, or every "Room" node under a specific Floor). Works for
// every property type unchanged — it never hardcodes level names.
//
// Drill-down rule: if the tapped level has exactly one child level, tapping a
// node pushes another instance of this same screen scoped to that child level
// and this node as parent. If it has multiple child levels (e.g. Rental's
// Floor -> {Shop, Flat}), the user picks which child type to view. If it has
// no child level, tapping a node opens a simple detail/rename/delete sheet
// (this is also where tenant-assignment will attach later).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/hierarchy_level.dart';
import '../../data/structure_repository.dart';
import '../../../../core/widgets/dynamic_icon.dart';
import '../../../../core/widgets/dormly_empty_state.dart';
import '../../../tenancies/presentation/node_detail_screen.dart';
final nodeListProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, (String propertyId, String levelId, String? parentNodeId)>(
  (ref, args) async {
    final repo = ref.watch(structureRepositoryProvider);
    return repo.listNodes(args.$1, args.$2, parentNodeId: args.$3);
  },
);

class NodeListScreen extends ConsumerWidget {
  final String propertyId;
  final HierarchyLevel level;
  final String? parentNodeId;
  final List<HierarchyLevel> allLevels; // every enabled level for this property

  const NodeListScreen({
    super.key,
    required this.propertyId,
    required this.level,
    required this.allLevels,
    this.parentNodeId,
  });

  List<HierarchyLevel> get _childLevels =>
      allLevels.where((l) => l.parentLevelId == level.id).toList();

  Future<void> _addNode(BuildContext context, WidgetRef ref) async {
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add ${level.displayName}'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: InputDecoration(labelText: '${level.displayName} name', hintText: 'e.g. A, 101, 1'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, nameController.text.trim()), child: const Text('Add')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;

    try {
      await ref.read(structureRepositoryProvider).createNode(
            propertyId,
            levelId: level.id,
            parentNodeId: parentNodeId,
            name: name,
          );
      ref.invalidate(nodeListProvider((propertyId, level.id, parentNodeId)));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not add: $e')));
      }
    }
  }

  Future<void> _openNodeActions(BuildContext context, WidgetRef ref, Map<String, dynamic> node) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename'),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );

    if (action == 'rename') {
      final controller = TextEditingController(text: node['name']);
      final newName = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Rename'),
          content: TextField(controller: controller, autofocus: true),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save')),
          ],
        ),
      );
      if (newName != null && newName.isNotEmpty) {
        try {
          await ref.read(structureRepositoryProvider).renameNode(propertyId, node['id'], newName);
          ref.invalidate(nodeListProvider((propertyId, level.id, parentNodeId)));
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not rename: $e')));
          }
        }
      }
    } else if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Delete "${node['name']}"?'),
          content: const Text('If this has children under it, deletion will be refused — remove those first.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        try {
          await ref.read(structureRepositoryProvider).deleteNode(propertyId, node['id']);
          ref.invalidate(nodeListProvider((propertyId, level.id, parentNodeId)));
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not delete: $e')));
          }
        }
      }
    }
  }

  Future<void> _onNodeTap(BuildContext context, WidgetRef ref, Map<String, dynamic> node) async {
    final children = _childLevels;
if (children.isEmpty) {
      final refreshed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (context) => NodeDetailScreen(
            propertyId: propertyId,
            nodeId: node['id'],
            nodeName: node['name'],
            levelName: level.displayName.toLowerCase(),
          ),
        ),
      );
      if (refreshed == true) {
        ref.invalidate(nodeListProvider((propertyId, level.id, parentNodeId)));
      }
      return;
    }

    HierarchyLevel targetLevel;
    if (children.length == 1) {
      targetLevel = children.first;
    } else {
      final chosen = await showModalBottomSheet<HierarchyLevel>(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: children
                .map((child) => ListTile(
                      leading: DynamicIcon(name: child.icon),
                      title: Text(child.displayName),
                      onTap: () => Navigator.pop(context, child),
                    ))
                .toList(),
          ),
        ),
      );
      if (chosen == null) return;
      targetLevel = chosen;
    }

    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => NodeListScreen(
          propertyId: propertyId,
          level: targetLevel,
          allLevels: allLevels,
          parentNodeId: node['id'],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nodesAsync = ref.watch(nodeListProvider((propertyId, level.id, parentNodeId)));

    return Scaffold(
      appBar: AppBar(title: Text(level.displayName)),
      body: nodesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Something went wrong: $err')),
        data: (nodes) {
          if (nodes.isEmpty) {
            return DormlyEmptyState(
              title: 'No ${level.displayName.toLowerCase()} yet',
              subtitle: 'Tap the + button to add your first one.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: nodes.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final node = nodes[index];
              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: Theme.of(context).dividerColor),
                ),
                child: ListTile(
                  leading: DynamicIcon(name: level.icon, colorHex: level.color),
                  title: Text(node['name'] ?? ''),
                  trailing: _childLevels.isEmpty
                      ? IconButton(
                          icon: const Icon(Icons.more_vert),
                          onPressed: () => _openNodeActions(context, ref, node),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: () => _onNodeTap(context, ref, node),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addNode(context, ref),
        icon: const Icon(Icons.add),
        label: Text('Add ${level.displayName}'),
      ),
    );
  }
}