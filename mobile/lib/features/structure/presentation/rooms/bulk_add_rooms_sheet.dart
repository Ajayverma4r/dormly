// features/structure/presentation/rooms/bulk_add_rooms_sheet.dart

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../properties/domain/property_monetization.dart';
import '../../../subscription/presentation/subscription_provider.dart';
import '../../../subscription/presentation/paywall_screen.dart';
import '../../data/structure_repository.dart';
import '../../domain/hierarchy_level.dart';
import '../dynamic_dashboard/dynamic_dashboard_screen.dart'
    show hierarchyLevelsProvider;
import '../property_shell_screen.dart' show propertyDetailProvider;
import 'rooms_structure_config.dart';
import 'rooms_tree_provider.dart';

/// Opens bulk room creation sheet. Returns `true` when rooms were created.
Future<bool> showBulkAddRoomsSheet({
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
    builder: (_) => BulkAddRoomsSheet(
      propertyId: propertyId,
      lockedParentNodeId: lockedParentNodeId,
      lockedParentLabel: lockedParentLabel,
    ),
  );
  return result ?? false;
}

class BulkAddRoomsSheet extends ConsumerStatefulWidget {
  final String propertyId;
  final String? lockedParentNodeId;
  final String? lockedParentLabel;

  const BulkAddRoomsSheet({
    super.key,
    required this.propertyId,
    this.lockedParentNodeId,
    this.lockedParentLabel,
  });

  @override
  ConsumerState<BulkAddRoomsSheet> createState() => _BulkAddRoomsSheetState();
}

class _BulkAddRoomsSheetState extends ConsumerState<BulkAddRoomsSheet> {
  final _startNumberController = TextEditingController(text: '101');
  final _roomCountController = TextEditingController(text: '10');

  RoomFormConfig? _config;
  HierarchyLevel? _parentLevel;
  List<RoomParentOption> _parentOptions = [];
  String? _selectedParentId;

  bool _loading = true;
  bool _generating = false;
  String? _error;
  int _bedsPerRoom = 1;

  bool get _parentLocked => widget.lockedParentNodeId != null;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _startNumberController.dispose();
    _roomCountController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final levels =
          await ref.read(hierarchyLevelsProvider(widget.propertyId).future);
      final config = RoomFormConfig.fromLevels(levels);
      if (config == null) {
        setState(() {
          _error = 'No room level found in structure. Check Structure Settings.';
          _loading = false;
        });
        return;
      }

      final parentLevel = resolveRoomParentLevel(levels, config.roomLevel);
      if (parentLevel == null) {
        setState(() {
          _error =
              'Bulk add needs a parent level (e.g. Floor) above ${config.roomLevel.displayName}.';
          _loading = false;
        });
        return;
      }

      final options = await loadAllRoomParentOptions(
        repo: ref.read(structureRepositoryProvider),
        propertyId: widget.propertyId,
        config: config,
        levels: levels,
      );

      _config = config;
      _parentLevel = parentLevel;
      _parentOptions = options;
      _selectedParentId = widget.lockedParentNodeId ??
          (options.isNotEmpty ? options.first.nodeId : null);
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _error = 'Could not load structure: $e';
        _loading = false;
      });
    }
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
    final levels =
        await ref.read(hierarchyLevelsProvider(widget.propertyId).future);

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

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _generate() async {
    final config = _config!;
    final parentLevel = _parentLevel!;

    if (_selectedParentId == null) {
      _showSnack('Select an existing ${parentLevel.displayName}.');
      return;
    }
    if (!_parentLocked && _parentOptions.isEmpty) {
      _showSnack('Select an existing ${parentLevel.displayName}.');
      return;
    }

    final startNumber = int.tryParse(_startNumberController.text.trim());
    if (startNumber == null || startNumber < 0) {
      _showSnack('Enter a valid starting room number.');
      return;
    }

    final roomCount = int.tryParse(_roomCountController.text.trim());
    if (roomCount == null || roomCount < 1 || roomCount > 100) {
      _showSnack('Number of rooms must be between 1 and 100.');
      return;
    }

    final unitsToAdd = config.showBedCapacity ? roomCount * _bedsPerRoom : roomCount;
    if (!await _checkQuota(unitsToAdd)) return;

    setState(() => _generating = true);
    final repo = ref.read(structureRepositoryProvider);
    final parentNodeId = _selectedParentId!;

    try {
      for (var i = 0; i < roomCount; i++) {
        final roomName = '${startNumber + i}';
        final roomNode = await repo.createNode(
          widget.propertyId,
          levelId: config.roomLevel.id,
          parentNodeId: parentNodeId,
          name: roomName,
          metadata: config.showBedCapacity
              ? {'bed_capacity': _bedsPerRoom}
              : null,
        );
        final roomId = roomNode['id']?.toString();

        if (config.bedLevel != null && roomId != null) {
          for (var b = 1; b <= _bedsPerRoom; b++) {
            await repo.createNode(
              widget.propertyId,
              levelId: config.bedLevel!.id,
              parentNodeId: roomId,
              name: 'Bed $b',
            );
          }
        }
      }

      ref.invalidate(roomsTreeProvider(widget.propertyId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Created $roomCount ${config.roomLevel.displayName}${roomCount == 1 ? '' : 's'} successfully.',
            ),
          ),
        );
        Navigator.of(context).pop(true);
      }
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
          'Could not create rooms: ${data is Map ? data['error'] : e.message}',
        );
      }
    } catch (e) {
      _showSnack('Could not create rooms: $e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Stack(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Bulk Add Rooms',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _generating
                        ? null
                        : () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Generate numbered rooms on one ${(_parentLevel?.displayName ?? 'floor').toLowerCase()}.',
                style: const TextStyle(color: AppColors.slate, fontSize: 13),
              ),
              const SizedBox(height: 12),
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
              else if (_parentOptions.isEmpty && !_parentLocked)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No ${_parentLevel!.displayName.toLowerCase()}s found. '
                    'Add a ${_parentLevel!.displayName.toLowerCase()} first, then bulk create rooms.',
                    style: const TextStyle(color: AppColors.slate),
                  ),
                )
              else
                _buildForm(),
            ],
          ),
        ),
        if (_generating)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black.withValues(alpha: 0.35),
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Creating rooms…'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildForm() {
    final config = _config!;
    final parentLevel = _parentLevel!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_parentLocked)
          InputDecorator(
            decoration: InputDecoration(
              labelText: parentLevel.displayName,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(
              widget.lockedParentLabel ?? widget.lockedParentNodeId!,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
          )
        else
          DropdownButtonFormField<String>(
            value: _selectedParentId,
            decoration: InputDecoration(
              labelText: parentLevel.displayName,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            items: _parentOptions
                .map(
                  (o) => DropdownMenuItem(
                    value: o.nodeId,
                    child: Text(o.label),
                  ),
                )
                .toList(),
            onChanged: _generating
                ? null
                : (v) => setState(() => _selectedParentId = v),
          ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _startNumberController,
          enabled: !_generating,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: 'Starting room number',
            hintText: 'e.g. 101',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _roomCountController,
          enabled: !_generating,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: 'Number of rooms to create',
            hintText: 'e.g. 10',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        if (config.showBedCapacity) ...[
          const SizedBox(height: 16),
          Text(
            'Beds per room',
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
                onPressed: _generating || _bedsPerRoom <= 1
                    ? null
                    : () => setState(() => _bedsPerRoom--),
                icon: const Icon(Icons.remove),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.canvas,
                  foregroundColor: AppColors.ink,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  '$_bedsPerRoom',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
              IconButton.filled(
                onPressed: _generating || _bedsPerRoom >= 20
                    ? null
                    : () => setState(() => _bedsPerRoom++),
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
          onPressed: _generating ? null : _generate,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.blueprint,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: const Text('Generate Rooms'),
        ),
      ],
    );
  }
}
