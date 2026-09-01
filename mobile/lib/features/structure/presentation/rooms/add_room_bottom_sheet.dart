// features/structure/presentation/rooms/add_room_bottom_sheet.dart

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/structure_repository.dart';
import '../../domain/hierarchy_level.dart';
import '../../../properties/domain/property_monetization.dart';
import '../../../subscription/presentation/subscription_provider.dart';
import '../../../subscription/presentation/paywall_screen.dart';
import '../dynamic_dashboard/dynamic_dashboard_screen.dart'
    show hierarchyLevelsProvider;
import '../property_shell_screen.dart' show propertyDetailProvider;
import 'rooms_structure_config.dart';
import 'rooms_tree_provider.dart';

/// Opens the smart Add Room bottom sheet. Returns `true` when a room was created.
Future<bool> showAddRoomBottomSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String propertyId,
  String? lockedParentNodeId,
  String? lockedParentLabel,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => AddRoomBottomSheet(
      propertyId: propertyId,
      lockedParentNodeId: lockedParentNodeId,
      lockedParentLabel: lockedParentLabel,
    ),
  );
  return result ?? false;
}

class AddRoomBottomSheet extends ConsumerStatefulWidget {
  final String propertyId;
  final String? lockedParentNodeId;
  final String? lockedParentLabel;

  const AddRoomBottomSheet({
    super.key,
    required this.propertyId,
    this.lockedParentNodeId,
    this.lockedParentLabel,
  });

  @override
  ConsumerState<AddRoomBottomSheet> createState() => _AddRoomBottomSheetState();
}

class _AddRoomBottomSheetState extends ConsumerState<AddRoomBottomSheet> {
  final _roomNameController = TextEditingController();
  final _newNameControllers = <String, TextEditingController>{};

  RoomFormConfig? _config;
  bool _loading = true;
  String? _error;

  /// Cached node lists keyed by level id + optional parent node id.
  final Map<String, List<Map<String, dynamic>>> _nodesCache = {};

  /// Selected node id per hierarchy level id, or [kAddNewPickerValue].
  final Map<String, String> _selected = {};

  int _bedCapacity = 1;
  bool _submitting = false;

  bool get _parentLocked => widget.lockedParentNodeId != null;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _roomNameController.dispose();
    for (final c in _newNameControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _cacheKey(String levelId, String? parentNodeId) =>
      '$levelId::${parentNodeId ?? ''}';

  Future<void> _bootstrap() async {
    try {
      final levels = await ref.read(hierarchyLevelsProvider(widget.propertyId).future);
      final config = RoomFormConfig.fromLevels(levels);
      if (config == null) {
        setState(() {
          _error = 'No room level found in structure. Check Structure Settings.';
          _loading = false;
        });
        return;
      }
      _config = config;
      if (!_parentLocked) {
        for (final level in config.hierarchyPickers) {
          _newNameControllers[level.id] = TextEditingController();
        }
        await _loadPickerLevel(config.hierarchyPickers.first, null);
      }
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _error = 'Could not load structure: $e';
        _loading = false;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _loadNodes(
    HierarchyLevel level,
    String? parentNodeId,
  ) async {
    final key = _cacheKey(level.id, parentNodeId);
    if (_nodesCache.containsKey(key)) return _nodesCache[key]!;

    final list = await ref.read(structureRepositoryProvider).listNodes(
          widget.propertyId,
          level.id,
          parentNodeId: parentNodeId,
        );
    _nodesCache[key] = list;
    return list;
  }

  Future<void> _loadPickerLevel(
    HierarchyLevel level,
    String? parentNodeId,
  ) async {
    final nodes = await _loadNodes(level, parentNodeId);
    if (nodes.isNotEmpty) {
      _selected[level.id] = nodes.first['id']?.toString() ?? kAddNewPickerValue;
    } else {
      _selected[level.id] = kAddNewPickerValue;
      _newNameControllers[level.id]?.text = defaultNameForLevel(level);
    }

    final idx = _config!.hierarchyPickers.indexWhere((l) => l.id == level.id);
    if (idx >= 0 && idx < _config!.hierarchyPickers.length - 1) {
      final childLevel = _config!.hierarchyPickers[idx + 1];
      final parentId = _selected[level.id] == kAddNewPickerValue
          ? null
          : _selected[level.id];
      if (parentId != null && parentId != kAddNewPickerValue) {
        await _loadPickerLevel(childLevel, parentId);
      } else {
        _selected.remove(childLevel.id);
      }
    }
  }

  Future<void> _onPickerChanged(
    HierarchyLevel level,
    String? value,
  ) async {
    if (value == null) return;
    _selected[level.id] = value;

    final idx = _config!.hierarchyPickers.indexWhere((l) => l.id == level.id);
    for (var i = idx + 1; i < _config!.hierarchyPickers.length; i++) {
      _selected.remove(_config!.hierarchyPickers[i].id);
      _nodesCache.removeWhere((k, _) => k.startsWith(_config!.hierarchyPickers[i].id));
    }

    if (idx < _config!.hierarchyPickers.length - 1) {
      final childLevel = _config!.hierarchyPickers[idx + 1];
      if (value != kAddNewPickerValue) {
        await _loadPickerLevel(childLevel, value);
      }
    }
    setState(() {});
  }

  Future<bool> _checkQuota(int unitsToAdd) async {
    final propertyTypeKey = ref
        .read(propertyDetailProvider(widget.propertyId))
        .valueOrNull?['property_type_key'] as String?;
    final sub = ref.read(subscriptionProvider).valueOrNull;
    final isPaid = PropertyMonetization.isPaidPlan(
      sub?.subscription.planSlug,
      sub?.subscription.status,
    );
    final repo = ref.read(structureRepositoryProvider);
    final levels = await ref.read(hierarchyLevelsProvider(widget.propertyId).future);

    if (!isPaid && PropertyMonetization.isApartment(propertyTypeKey)) {
      var roomCount = 0;
      for (final l in levels) {
        if (PropertyMonetization.isRoomLevel(
          l.internalKey,
          supportsOccupancy: l.supportsOccupancy,
        )) {
          final rooms = await repo.listNodes(widget.propertyId, l.id);
          roomCount += rooms.length;
        }
      }
      if (roomCount + unitsToAdd > PropertyMonetization.freeApartmentMaxRooms) {
        if (!mounted) return false;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const PaywallScreen(
              reason: PropertyMonetization.expiredLockMessage,
            ),
          ),
        );
        return false;
      }
    }

    final entitlements = ref.read(entitlementsProvider);
    var leafCount = 0;
    for (final l in levels) {
      if (l.supportsOccupancy || l.internalKey == 'bed') {
        leafCount += await repo.countNodes(widget.propertyId, l.id);
      }
    }
    if (!entitlements.hasQuota('max_rooms', leafCount + unitsToAdd - 1)) {
      if (!mounted) return false;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const PaywallScreen(
            reason: PropertyMonetization.expiredLockMessage,
          ),
        ),
      );
      return false;
    }
    return true;
  }

  Future<void> _submit() async {
    final config = _config!;
    final roomName = _roomNameController.text.trim();
    if (roomName.isEmpty) {
      _showSnack('Enter a room name or number.');
      return;
    }

    for (final level in config.hierarchyPickers) {
      if (!_parentLocked && _selected[level.id] == kAddNewPickerValue) {
        final name = _newNameControllers[level.id]?.text.trim() ?? '';
        if (name.isEmpty) {
          _showSnack('Enter a name for the new ${level.displayName}.');
          return;
        }
      }
    }

    final unitsToAdd = config.showBedCapacity ? _bedCapacity : 1;
    if (!await _checkQuota(unitsToAdd)) return;

    setState(() => _submitting = true);
    final repo = ref.read(structureRepositoryProvider);

    try {
      String? parentNodeId;
      if (_parentLocked) {
        parentNodeId = widget.lockedParentNodeId;
      } else {
        for (final level in config.hierarchyPickers) {
          final sel = _selected[level.id];
          if (sel == kAddNewPickerValue) {
            final name = _newNameControllers[level.id]!.text.trim();
            final created = await repo.createNode(
              widget.propertyId,
              levelId: level.id,
              parentNodeId: parentNodeId,
              name: name,
            );
            parentNodeId = created['id']?.toString();
          } else {
            parentNodeId = sel;
          }
        }
      }

      final roomNode = await repo.createNode(
        widget.propertyId,
        levelId: config.roomLevel.id,
        parentNodeId: parentNodeId,
        name: roomName,
        metadata: config.showBedCapacity
            ? {'bed_capacity': _bedCapacity}
            : null,
      );
      final roomId = roomNode['id']?.toString();

      if (config.bedLevel != null && roomId != null) {
        for (var i = 1; i <= _bedCapacity; i++) {
          await repo.createNode(
            widget.propertyId,
            levelId: config.bedLevel!.id,
            parentNodeId: roomId,
            name: 'Bed $i',
          );
        }
      }

      ref.invalidate(roomsTreeProvider(widget.propertyId));
      if (mounted) Navigator.of(context).pop(true);
    } on DioException catch (e) {
      final data = e.response?.data;
      final code = data is Map ? data['code'] : null;
      if (e.response?.statusCode == 403 &&
          (code == 'SUBSCRIPTION_REQUIRED' ||
              (data is Map && data['upgradeRequired'] == true))) {
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const PaywallScreen(
                reason: PropertyMonetization.expiredLockMessage,
              ),
            ),
          );
        }
      } else {
        _showSnack(
          'Could not add room: ${data is Map ? data['error'] : e.message}',
        );
      }
    } catch (e) {
      _showSnack('Could not add room: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Add Room',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: const TextStyle(color: AppColors.slate)),
            )
          else
            _buildForm(),
        ],
      ),
    );
  }

  Widget _buildForm() {
    final config = _config!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_parentLocked) ...[
          InputDecorator(
            decoration: InputDecoration(
              labelText: config.hierarchyPickers.isNotEmpty
                  ? config.hierarchyPickers.last.displayName
                  : 'Location',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(
              widget.lockedParentLabel ?? widget.lockedParentNodeId!,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ] else
          ...config.hierarchyPickers.map(_buildHierarchyPicker),
        const SizedBox(height: 12),
        TextFormField(
          controller: _roomNameController,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: '${config.roomLevel.displayName} name / number',
            hintText: 'e.g. 101, A-204',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        if (config.showBedCapacity) ...[
          const SizedBox(height: 16),
          Text(
            'Bed capacity',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.slate,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton.filled(
                onPressed: _bedCapacity > 1
                    ? () => setState(() => _bedCapacity--)
                    : null,
                icon: const Icon(Icons.remove),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.canvas,
                  foregroundColor: AppColors.ink,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  '$_bedCapacity',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
              IconButton.filled(
                onPressed: _bedCapacity < 20
                    ? () => setState(() => _bedCapacity++)
                    : null,
                icon: const Icon(Icons.add),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.canvas,
                  foregroundColor: AppColors.ink,
                ),
              ),
              const Spacer(),
              Text(
                '${config.bedLevel!.displayName}s',
                style: const TextStyle(color: AppColors.slate, fontSize: 13),
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.blueprint,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: _submitting
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text('Add ${config.roomLevel.displayName}'),
        ),
      ],
    );
  }

  Widget _buildHierarchyPicker(HierarchyLevel level) {
    final parentIdx = _config!.hierarchyPickers.indexWhere((l) => l.id == level.id) - 1;
    String? parentNodeId;
    if (parentIdx >= 0) {
      final parentLevel = _config!.hierarchyPickers[parentIdx];
      final sel = _selected[parentLevel.id];
      if (sel == null || sel == kAddNewPickerValue) {
        return const SizedBox.shrink();
      }
      parentNodeId = sel;
    }

    final key = _cacheKey(level.id, parentNodeId);
    final nodes = _nodesCache[key] ?? [];
    final selected = _selected[level.id] ?? kAddNewPickerValue;
    final showNewField = selected == kAddNewPickerValue;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            value: selected,
            decoration: InputDecoration(
              labelText: level.displayName,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            items: [
              ...nodes.map(
                (n) => DropdownMenuItem(
                  value: n['id']?.toString(),
                  child: Text(n['name']?.toString() ?? ''),
                ),
              ),
              DropdownMenuItem(
                value: kAddNewPickerValue,
                child: Text('+ Add New ${level.displayName}'),
              ),
            ],
            onChanged: (v) => _onPickerChanged(level, v),
          ),
          if (showNewField) ...[
            const SizedBox(height: 8),
            TextFormField(
              controller: _newNameControllers[level.id],
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'New ${level.displayName} name',
                hintText: defaultNameForLevel(level),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
