// features/tenancies/presentation/widgets/unit_selection_cascade.dart
//
// Dynamic drill-down pickers that mirror the property hierarchy until the user
// reaches an assignable unit (Bed, Flat, Shop, Room, etc.).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../structure/data/structure_repository.dart';
import '../../../structure/domain/hierarchy_level.dart';
import '../../domain/assignable_unit.dart';

class UnitSelectionCascade extends ConsumerStatefulWidget {
  final String propertyId;
  final List<HierarchyLevel> levels;
  final String? initialNodeId;
  final ValueChanged<String?> onNodeSelected;

  const UnitSelectionCascade({
    super.key,
    required this.propertyId,
    required this.levels,
    required this.onNodeSelected,
    this.initialNodeId,
  });

  @override
  ConsumerState<UnitSelectionCascade> createState() =>
      _UnitSelectionCascadeState();
}

class _UnitSelectionCascadeState extends ConsumerState<UnitSelectionCascade> {
  final List<String?> _selectedNodeIds = [];
  List<_PickerStep> _steps = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initSteps();
  }

  Future<void> _initSteps() async {
    setState(() => _loading = true);
    final roots = widget.levels.where((l) => l.parentLevelId == null).toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    if (roots.isEmpty) {
      setState(() => _loading = false);
      return;
    }

    _steps = [
      _PickerStep.single(level: roots.first, parentNodeId: null),
    ];
    _selectedNodeIds.clear();
    await _loadStepNodes(0);

    if (widget.initialNodeId != null) {
      await _applyInitialSelection(widget.initialNodeId!);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _applyInitialSelection(String nodeId) async {
    final repo = ref.read(structureRepositoryProvider);
    final path = await _findNodePath(repo, nodeId);
    if (path == null || path.isEmpty) return;

    for (var i = 0; i < path.length; i++) {
      if (i >= _steps.length) break;
      final entry = path[i];
      _selectedNodeIds.add(entry.nodeId);
      if (i < path.length - 1) {
        await _advanceFrom(i, entry.nodeId);
      }
    }
    _emitSelection();
  }

  Future<List<({String nodeId, String levelId})>?> _findNodePath(
    StructureRepository repo,
    String targetNodeId,
  ) async {
    Future<List<({String nodeId, String levelId})>?> search(
      HierarchyLevel level,
      String? parentNodeId,
      List<({String nodeId, String levelId})> prefix,
    ) async {
      final nodes = await repo.listNodes(
        widget.propertyId,
        level.id,
        parentNodeId: parentNodeId,
      );
      for (final n in nodes) {
        final id = n['id']?.toString() ?? '';
        final trail = [...prefix, (nodeId: id, levelId: level.id)];
        if (id == targetNodeId) return trail;
        for (final cl
            in widget.levels.where((l) => l.parentLevelId == level.id)) {
          final found = await search(cl, id, trail);
          if (found != null) return found;
        }
      }
      return null;
    }

    for (final root in widget.levels.where((l) => l.parentLevelId == null)) {
      final found = await search(root, null, []);
      if (found != null) return found;
    }
    return null;
  }

  Future<void> _loadStepNodes(int stepIndex) async {
    final step = _steps[stepIndex];
    final repo = ref.read(structureRepositoryProvider);
    if (step.isMerged) {
      final merged = <Map<String, dynamic>>[];
      for (final level in step.levels!) {
        final nodes = await repo.listNodes(
          widget.propertyId,
          level.id,
          parentNodeId: step.parentNodeId,
        );
        for (final n in nodes) {
          merged.add({
            ...n,
            '_levelName': level.displayName,
            '_levelId': level.id,
          });
        }
      }
      _steps[stepIndex] = step.copyWith(nodes: merged);
    } else {
      final nodes = await repo.listNodes(
        widget.propertyId,
        step.level!.id,
        parentNodeId: step.parentNodeId,
      );
      _steps[stepIndex] = step.copyWith(nodes: nodes);
    }
  }

  Future<void> _advanceFrom(int stepIndex, String nodeId) async {
    final step = _steps[stepIndex];
    late final HierarchyLevel level;
    if (step.isMerged) {
      final node = step.nodes.firstWhere((n) => n['id']?.toString() == nodeId);
      final levelId = node['_levelId']?.toString();
      level = widget.levels.firstWhere((l) => l.id == levelId);
    } else {
      level = step.level!;
    }

    if (isAssignableLevel(level.id, widget.levels)) {
      _steps = _steps.sublist(0, stepIndex + 1);
      return;
    }

    final childLevels = widget.levels
        .where((l) => l.parentLevelId == level.id)
        .toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

    _steps = _steps.sublist(0, stepIndex + 1);

    final assignableChildren = childLevels
        .where((l) => isAssignableLevel(l.id, widget.levels))
        .toList();
    final nonAssignableChildren = childLevels
        .where((l) => !isAssignableLevel(l.id, widget.levels))
        .toList();

    if (assignableChildren.length > 1) {
      _steps.add(_PickerStep.merged(
        levels: assignableChildren,
        parentNodeId: nodeId,
      ));
      await _loadStepNodes(_steps.length - 1);
    } else if (assignableChildren.length == 1) {
      _steps.add(
          _PickerStep.single(level: assignableChildren.first, parentNodeId: nodeId));
      await _loadStepNodes(_steps.length - 1);
    } else if (nonAssignableChildren.isNotEmpty) {
      _steps.add(_PickerStep.single(
          level: nonAssignableChildren.first, parentNodeId: nodeId));
      await _loadStepNodes(_steps.length - 1);
    }
  }

  void _emitSelection() {
    if (_selectedNodeIds.isEmpty) {
      widget.onNodeSelected(null);
      return;
    }
    final lastIndex = _selectedNodeIds.length - 1;
    if (lastIndex >= _steps.length) {
      widget.onNodeSelected(null);
      return;
    }
    final step = _steps[lastIndex];
    final nodeId = _selectedNodeIds[lastIndex];
    if (nodeId == null) {
      widget.onNodeSelected(null);
      return;
    }

    HierarchyLevel? level = step.level;
    if (step.isMerged) {
      final node = step.nodes.firstWhere((n) => n['id'] == nodeId);
      final levelId = node['_levelId']?.toString();
      level = widget.levels.where((l) => l.id == levelId).firstOrNull;
    }

    if (level != null && isAssignableLevel(level.id, widget.levels)) {
      widget.onNodeSelected(nodeId);
    } else {
      widget.onNodeSelected(null);
    }
  }

  Future<void> _onStepChanged(int stepIndex, String? nodeId) async {
    setState(() {
      while (_selectedNodeIds.length > stepIndex) {
        _selectedNodeIds.removeLast();
      }
      if (nodeId != null) _selectedNodeIds.add(nodeId);
      _steps = _steps.sublist(0, stepIndex + 1);
    });

    if (nodeId == null) {
      _emitSelection();
      return;
    }

    setState(() => _loading = true);
    await _advanceFrom(stepIndex, nodeId);
    _emitSelection();
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _steps.every((s) => s.nodes.isEmpty)) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _steps.length; i++) ...[
          _LevelDropdown(
            step: _steps[i],
            value: i < _selectedNodeIds.length ? _selectedNodeIds[i] : null,
            onChanged: (v) => _onStepChanged(i, v),
          ),
          const SizedBox(height: 12),
        ],
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }
}

class _PickerStep {
  final HierarchyLevel? level;
  final List<HierarchyLevel>? levels;
  final String? parentNodeId;
  final List<Map<String, dynamic>> nodes;

  bool get isMerged => levels != null && levels!.length > 1;

  const _PickerStep._({
    this.level,
    this.levels,
    this.parentNodeId,
    this.nodes = const [],
  });

  factory _PickerStep.single({
    required HierarchyLevel level,
    required String? parentNodeId,
    List<Map<String, dynamic>> nodes = const [],
  }) =>
      _PickerStep._(level: level, parentNodeId: parentNodeId, nodes: nodes);

  factory _PickerStep.merged({
    required List<HierarchyLevel> levels,
    required String? parentNodeId,
    List<Map<String, dynamic>> nodes = const [],
  }) =>
      _PickerStep._(levels: levels, parentNodeId: parentNodeId, nodes: nodes);

  _PickerStep copyWith({List<Map<String, dynamic>>? nodes}) => _PickerStep._(
        level: level,
        levels: levels,
        parentNodeId: parentNodeId,
        nodes: nodes ?? this.nodes,
      );

  String get label {
    if (isMerged) return levels!.map((l) => l.displayName).join(' / ');
    return level!.displayName;
  }
}

class _LevelDropdown extends StatelessWidget {
  final _PickerStep step;
  final String? value;
  final ValueChanged<String?> onChanged;

  const _LevelDropdown({
    required this.step,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final validValue =
        step.nodes.any((n) => n['id']?.toString() == value) ? value : null;

    return DropdownButtonFormField<String>(
      value: validValue,
      decoration: InputDecoration(
        labelText: '${step.label} *',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      hint: Text('Select ${step.label.toLowerCase()}'),
      items: step.nodes
          .map(
            (n) => DropdownMenuItem<String>(
              value: n['id']?.toString(),
              child: Text(
                step.isMerged
                    ? '${n['_levelName']}: ${n['name']}'
                    : n['name']?.toString() ?? 'Untitled',
              ),
            ),
          )
          .toList(),
      onChanged: step.nodes.isEmpty ? null : onChanged,
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
