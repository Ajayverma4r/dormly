// features/structure/presentation/rename_node_dialog.dart
//
// One rename dialog for every room / flat / bed / floor. It stays open while
// saving so a duplicate-name refusal from the server is shown inline and the
// user can just edit the name and try again.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/network_error.dart';
import '../data/structure_repository.dart';
import '../domain/node_names.dart';

export '../domain/node_names.dart';

/// Shows the rename dialog and returns the saved name, or null when the user
/// cancelled or left the name unchanged.
Future<String?> showRenameNodeDialog({
  required BuildContext context,
  required String currentName,
  required Future<void> Function(String name) onSubmit,
  String kind = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => RenameNodeDialog(
      currentName: currentName,
      kind: kind,
      onSubmit: onSubmit,
    ),
  );
}

/// Renames [nodeId] through the structure API. Returns the saved name.
Future<String?> renameNodeWithDialog({
  required BuildContext context,
  required WidgetRef ref,
  required String propertyId,
  required String nodeId,
  required String currentName,
  String kind = '',
}) {
  return showRenameNodeDialog(
    context: context,
    currentName: currentName,
    kind: kind,
    onSubmit: (name) =>
        ref.read(structureRepositoryProvider).renameNode(propertyId, nodeId, name),
  );
}

class RenameNodeDialog extends StatefulWidget {
  final String currentName;
  final String kind;
  final Future<void> Function(String name) onSubmit;

  const RenameNodeDialog({
    super.key,
    required this.currentName,
    required this.onSubmit,
    this.kind = '',
  });

  @override
  State<RenameNodeDialog> createState() => _RenameNodeDialogState();
}

class _RenameNodeDialogState extends State<RenameNodeDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.currentName);
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = normalizeNodeName(_controller.text);
    if (name.isEmpty) {
      setState(() => _error = 'Name cannot be empty.');
      return;
    }
    if (name == widget.currentName) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSubmit(name);
      if (mounted) Navigator.of(context).pop(name);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = networkErrorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind.trim();
    final typed = normalizeNodeName(_controller.text);
    final preview = kind.isEmpty || typed.isEmpty
        ? null
        : 'Shows as "${nodeDisplayLabel(typed, kind)}"';
    return AlertDialog(
      title: Text(kind.isEmpty ? 'Rename' : 'Rename $kind'),
      content: TextField(
        key: const Key('rename-node-field'),
        controller: _controller,
        autofocus: true,
        enabled: !_saving,
        maxLength: maxNodeNameLength,
        textInputAction: TextInputAction.done,
        onChanged: (_) => setState(() => _error = null),
        onSubmitted: (_) => _saving ? null : _save(),
        decoration: InputDecoration(
          labelText: kind.isEmpty ? 'Name' : '$kind name or number',
          helperText: preview,
          errorText: _error,
          errorMaxLines: 3,
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('rename-node-save'),
          onPressed: _saving ? null : _save,
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
