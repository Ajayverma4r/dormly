// features/structure/presentation/structure_editor/structure_editor_screen.dart
//
// Lets an owner Enable/Disable, Rename, Delete, Reorder existing levels and
// Add a Custom Level — exactly the "MOST IMPORTANT FEATURE" from the spec.
// Renaming never touches internal_key, so nothing downstream breaks.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/hierarchy_level.dart';
import '../../data/structure_repository.dart';
import '../../../../core/widgets/dynamic_icon.dart';

class StructureEditorScreen extends ConsumerStatefulWidget {
  final String propertyId;
  const StructureEditorScreen({super.key, required this.propertyId});

  @override
  ConsumerState<StructureEditorScreen> createState() => _StructureEditorScreenState();
}

class _StructureEditorScreenState extends ConsumerState<StructureEditorScreen> {
  List<HierarchyLevel>? _levels;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final levels = await ref.read(structureRepositoryProvider).listLevels(widget.propertyId);
      levels.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      setState(() { _levels = levels; _error = null; });
    } catch (e) {
      setState(() => _error = 'Failed to load structure: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleEnabled(HierarchyLevel level, bool value) async {
    setState(() => level.isEnabled == value); // no-op, real update below
    try {
      final repo = ref.read(structureRepositoryProvider);
      final updated = await repo.setEnabled(widget.propertyId, level.id, value);
      setState(() {
        final i = _levels!.indexWhere((l) => l.id == level.id);
        _levels![i] = updated;
      });
    } catch (e) {
      _showError('Could not update: $e');
    }
  }

  Future<void> _rename(HierarchyLevel level) async {
    final controller = TextEditingController(text: level.displayName);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename level'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Display name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == level.displayName) return;

    try {
      final updated = await ref.read(structureRepositoryProvider)
          .renameLevel(widget.propertyId, level.id, newName);
      setState(() {
        final i = _levels!.indexWhere((l) => l.id == level.id);
        _levels![i] = updated;
      });
    } catch (e) {
      _showError('Could not rename: $e');
    }
  }

  Future<void> _delete(HierarchyLevel level) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${level.displayName}"?'),
        content: const Text(
          'If this level already has entries under it, deletion will be refused — '
          'disable it instead, or confirm cascade delete on the next prompt.',
        ),
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
    if (confirmed != true) return;

    try {
      await ref.read(structureRepositoryProvider).deleteLevel(widget.propertyId, level.id);
      setState(() => _levels!.removeWhere((l) => l.id == level.id));
    } catch (e) {
      _offerForceDelete(level, e);
    }
  }

  Future<void> _offerForceDelete(HierarchyLevel level, Object error) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('This level has existing entries'),
        content: Text('$error\n\nDelete anyway and remove everything under it?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(structureRepositoryProvider)
          .deleteLevel(widget.propertyId, level.id, force: true);
      setState(() => _levels!.removeWhere((l) => l.id == level.id));
    } catch (e) {
      _showError('Still could not delete: $e');
    }
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _levels!.removeAt(oldIndex);
      _levels!.insert(newIndex, item);
    });
    try {
      await ref.read(structureRepositoryProvider)
          .reorder(widget.propertyId, _levels!.map((l) => l.id).toList());
    } catch (e) {
      _showError('Could not save order: $e');
      _load();
    }
  }

  Future<void> _addCustomLevel() async {
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add custom level'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Display name', hintText: 'e.g. Wing'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, nameController.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;

    final internalKey = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final parentId = _levels != null && _levels!.isNotEmpty ? _levels!.last.id : null;

    try {
      final created = await ref.read(structureRepositoryProvider).createLevel(
            widget.propertyId,
            displayName: name,
            internalKey: '${internalKey}_${DateTime.now().millisecondsSinceEpoch}',
            parentLevelId: parentId,
          );
      setState(() => _levels!.add(created));
    } catch (e) {
      _showError('Could not add level: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Structure')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Enable, disable, rename, delete, or drag to reorder. '
                        'Renaming never breaks existing data.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    Expanded(
                      child: ReorderableListView.builder(
                        itemCount: _levels!.length,
                        onReorder: _reorder,
                        itemBuilder: (context, index) {
                          final level = _levels![index];
                          return Card(
                            key: ValueKey(level.id),
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            child: ListTile(
                              leading: DynamicIcon(name: level.icon, colorHex: level.color),
                              title: Text(level.displayName,
                                  style: TextStyle(
                                    decoration: level.isEnabled ? null : TextDecoration.lineThrough,
                                  )),
                              subtitle: Text(level.internalKey, style: Theme.of(context).textTheme.bodySmall),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Switch(value: level.isEnabled, onChanged: (v) => _toggleEnabled(level, v)),
                                  IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _rename(level)),
                                  IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(level)),
                                  const Icon(Icons.drag_handle),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addCustomLevel,
        icon: const Icon(Icons.add),
        label: const Text('Add Custom Level'),
      ),
    );
  }
}