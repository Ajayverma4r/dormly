// features/tenancies/presentation/node_detail_screen.dart
//
// Entry point for a hierarchy node (room, bed, flat…). Occupied units open the
// shared Tenant Details screen; containers list their beds; vacant units offer
// Add Tenant.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../billing/presentation/invoices_list_screen.dart' show invoicesProvider;
import '../../structure/data/structure_repository.dart';
import '../../structure/domain/hierarchy_level.dart';
import '../../structure/presentation/dynamic_dashboard/dynamic_dashboard_screen.dart'
    show hierarchyLevelsProvider;
import '../data/tenancy_repository.dart';
import '../domain/assignable_unit.dart';
import 'add_tenant_screen.dart';
import 'room_beds_view.dart';
import 'tenant_profile_screen.dart';

final tenanciesForNodeProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, (String propertyId, String nodeId)>(
        (ref, args) async {
  final repo = ref.watch(tenancyRepositoryProvider);
  return repo.listByNode(args.$1, args.$2);
});

/// The active tenancy on [nodeId], matched on the tenancy's own node id so a
/// bed/room id is never mistaken for a tenancy id.
Map<String, dynamic>? activeTenancyForNode(
  List<Map<String, dynamic>> tenancies,
  String nodeId,
) {
  final wanted = nodeId.toLowerCase();
  for (final t in tenancies) {
    if (t['status']?.toString() != 'active') continue;
    final tenancyId = t['id']?.toString() ?? '';
    if (tenancyId.isEmpty) continue;
    final nid = (t['node_id'] ?? t['nodeId'])?.toString().toLowerCase();
    if (nid != null && nid.isNotEmpty && nid != wanted) continue;
    return t;
  }
  return null;
}

class NodeDetailScreen extends ConsumerWidget {
  static const routeName = 'node-detail';

  final String propertyId;
  final String nodeId;
  final String nodeName;
  final String levelName;

  const NodeDetailScreen({
    super.key,
    required this.propertyId,
    required this.nodeId,
    required this.nodeName,
    required this.levelName,
  });

  static MaterialPageRoute<T> route<T>({
    required String propertyId,
    required String nodeId,
    required String nodeName,
    required String levelName,
  }) {
    return MaterialPageRoute<T>(
      settings: const RouteSettings(name: routeName),
      builder: (_) => NodeDetailScreen(
        propertyId: propertyId,
        nodeId: nodeId,
        nodeName: nodeName,
        levelName: levelName,
      ),
    );
  }

  HierarchyLevel? _findLevel(List<HierarchyLevel> levels) {
    final wanted = levelName.trim().toLowerCase();
    return levels
        .where((l) => l.displayName.trim().toLowerCase() == wanted)
        .firstOrNull;
  }

  Future<void> _renameNode(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: nodeName);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(context, controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty && context.mounted) {
      try {
        await ref
            .read(structureRepositoryProvider)
            .renameNode(propertyId, nodeId, newName);
        if (context.mounted) Navigator.of(context).pop(true);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not rename: $e')));
        }
      }
    }
  }

  Future<void> _deleteNode(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "$nodeName"?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      try {
        await ref
            .read(structureRepositoryProvider)
            .deleteNode(propertyId, nodeId);
        if (context.mounted) Navigator.of(context).pop(true);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not delete: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenanciesAsync =
        ref.watch(tenanciesForNodeProvider((propertyId, nodeId)));
    final levelsAsync = ref.watch(hierarchyLevelsProvider(propertyId));

    final tenancies = tenanciesAsync.valueOrNull;
    final active =
        tenancies == null ? null : activeTenancyForNode(tenancies, nodeId);
    if (active != null) {
      return TenantProfileScreen(
        propertyId: propertyId,
        tenancyId: active['id'].toString(),
        initialTenancy: active,
      );
    }

    final levels = levelsAsync.valueOrNull;
    final containerLevel = levels == null ? null : _findLevel(levels);
    if (levels != null &&
        tenancies != null &&
        containerLevel != null &&
        !isAssignableLevel(containerLevel.id, levels)) {
      return RoomBedsScreen(
        propertyId: propertyId,
        nodeId: nodeId,
        nodeName: nodeName,
        level: containerLevel,
        levels: levels,
        onRename: () => _renameNode(context, ref),
        onDelete: () => _deleteNode(context, ref),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(nodeName),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'rename') _renameNode(context, ref);
              if (value == 'delete') _deleteNode(context, ref);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      body: levelsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Something went wrong: $err')),
        data: (levels) {
          return tenanciesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) =>
                Center(child: Text('Something went wrong: $err')),
            data: (_) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.person_outline,
                          size: 56, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text('No tenant assigned to this $levelName',
                          textAlign: TextAlign.center,
                          style:
                              const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: () async {
                          await openAddTenantFlow(
                            context: context,
                            ref: ref,
                            propertyId: propertyId,
                            nodeId: nodeId,
                          );
                          ref.invalidate(
                              tenanciesForNodeProvider((propertyId, nodeId)));
                          ref.invalidate(invoicesProvider(propertyId));
                        },
                        icon: const Icon(Icons.person_add_outlined),
                        label: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text('Add Tenant'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
