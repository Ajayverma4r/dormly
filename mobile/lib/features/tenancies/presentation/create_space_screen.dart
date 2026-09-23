// features/tenancies/presentation/create_space_screen.dart
//
// 2-step progressive Create Space for rental houses:
// Step 1 — What are you renting?  →  Step 2 — details + pricing.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../properties/domain/property_setup_state.dart';
import '../../structure/data/structure_repository.dart';
import '../../structure/domain/hierarchy_level.dart';
import '../../structure/presentation/dynamic_dashboard/dynamic_dashboard_screen.dart'
    show hierarchyLevelsProvider;
import 'assignable_units_provider.dart';

class CreatedSpaceResult {
  final String nodeId;
  final String name;
  final double? monthlyRent;
  final double? securityDeposit;

  const CreatedSpaceResult({
    required this.nodeId,
    required this.name,
    this.monthlyRent,
    this.securityDeposit,
  });
}

Future<CreatedSpaceResult?> openCreateSpaceScreen({
  required BuildContext context,
  required String propertyId,
}) {
  return Navigator.of(context).push<CreatedSpaceResult>(
    MaterialPageRoute(
      builder: (_) => CreateSpaceScreen(propertyId: propertyId),
    ),
  );
}

enum _SpaceKind {
  entireProperty,
  floorPortion,
  room,
  commercial,
}

extension _SpaceKindX on _SpaceKind {
  RentalSpaceType get rentalType {
    switch (this) {
      case _SpaceKind.entireProperty:
        return RentalSpaceType.entireProperty;
      case _SpaceKind.floorPortion:
        return RentalSpaceType.portion;
      case _SpaceKind.room:
        return RentalSpaceType.room;
      case _SpaceKind.commercial:
        return RentalSpaceType.shop;
    }
  }

  String get emoji {
    switch (this) {
      case _SpaceKind.entireProperty:
        return '🏠';
      case _SpaceKind.floorPortion:
        return '🏢';
      case _SpaceKind.room:
        return '🚪';
      case _SpaceKind.commercial:
        return '🏪';
    }
  }

  String get title {
    switch (this) {
      case _SpaceKind.entireProperty:
        return 'Entire Property';
      case _SpaceKind.floorPortion:
        return 'Floor / Portion';
      case _SpaceKind.room:
        return 'Room';
      case _SpaceKind.commercial:
        return 'Commercial Space';
    }
  }

  String get subtitle {
    switch (this) {
      case _SpaceKind.entireProperty:
        return 'The whole house';
      case _SpaceKind.floorPortion:
        return 'A separate part of the house';
      case _SpaceKind.room:
        return 'An individual room';
      case _SpaceKind.commercial:
        return 'Shop, office, etc.';
    }
  }

  String get nameHint {
    switch (this) {
      case _SpaceKind.entireProperty:
        return 'e.g., Entire House';
      case _SpaceKind.floorPortion:
        return 'e.g., Ground Floor Portion';
      case _SpaceKind.room:
        return 'e.g., Room 1, Back Room';
      case _SpaceKind.commercial:
        return 'e.g., Front Shop';
    }
  }

  bool get needsFloor => this != _SpaceKind.entireProperty;
}

class _FloorOption {
  final String? nodeId;
  final String name;
  final bool isPendingCreate;

  const _FloorOption({
    required this.name,
    this.nodeId,
    this.isPendingCreate = false,
  });
}

class CreateSpaceScreen extends ConsumerStatefulWidget {
  final String propertyId;

  const CreateSpaceScreen({super.key, required this.propertyId});

  @override
  ConsumerState<CreateSpaceScreen> createState() => _CreateSpaceScreenState();
}

class _CreateSpaceScreenState extends ConsumerState<CreateSpaceScreen> {
  static const _defaultFloors = [
    'Ground Floor',
    '1st Floor',
    '2nd Floor',
    '3rd Floor',
    'Roof',
  ];

  _SpaceKind? _kind;
  final _nameController = TextEditingController();
  final _rentController = TextEditingController();
  final _depositController = TextEditingController();
  final List<_FloorOption> _floors = [];
  String? _selectedFloorKey;
  bool _loadingFloors = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFloors();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _rentController.dispose();
    _depositController.dispose();
    super.dispose();
  }

  String _floorKey(_FloorOption f) =>
      f.nodeId != null ? 'id:${f.nodeId}' : 'new:${f.name.toLowerCase()}';

  Future<void> _loadFloors() async {
    setState(() => _loadingFloors = true);
    try {
      final repo = ref.read(structureRepositoryProvider);
      final levels = await ref.read(
        hierarchyLevelsProvider(widget.propertyId).future,
      );
      final unitLevel = _unitLevel(levels);
      if (unitLevel == null) {
        if (mounted) {
          setState(() {
            _loadingFloors = false;
            _error = 'This property has no unit level configured.';
          });
        }
        return;
      }

      final nodes = <Map<String, dynamic>>[];
      final seen = <String>{};
      Future<void> addAll(List<Map<String, dynamic>> batch) async {
        for (final n in batch) {
          final id = n['id']?.toString();
          if (id == null || seen.contains(id)) continue;
          seen.add(id);
          nodes.add(n);
        }
      }

      await addAll(await repo.listNodes(widget.propertyId, unitLevel.id));
      final propertyLevel = _propertyLevel(levels);
      if (propertyLevel != null) {
        final roots = await repo.listNodes(
          widget.propertyId,
          propertyLevel.id,
          parentNodeId: null,
        );
        for (final root in roots) {
          final rootId = root['id']?.toString();
          if (rootId == null) continue;
          await addAll(await repo.listNodes(
            widget.propertyId,
            unitLevel.id,
            parentNodeId: rootId,
          ));
        }
      }

      final byName = <String, _FloorOption>{};
      for (final n in nodes) {
        final type = (n['spaceType'] ??
                n['space_type'] ??
                (n['metadata'] is Map ? n['metadata']['space_type'] : null))
            ?.toString();
        final name = n['name']?.toString() ?? '';
        final id = n['id']?.toString();
        if (id == null || name.isEmpty) continue;
        final looksLikeFloor = type == 'floor' ||
            RegExp(r'floor|ground|roof|basement', caseSensitive: false)
                .hasMatch(name);
        if (looksLikeFloor) {
          byName[name.toLowerCase()] = _FloorOption(nodeId: id, name: name);
        }
      }

      for (final p in _floors.where((f) => f.isPendingCreate)) {
        byName.putIfAbsent(p.name.toLowerCase(), () => p);
      }
      for (final label in _defaultFloors) {
        byName.putIfAbsent(
          label.toLowerCase(),
          () => _FloorOption(name: label, isPendingCreate: true),
        );
      }

      final merged = byName.values.toList()
        ..sort((a, b) =>
            _floorSortIndex(a.name).compareTo(_floorSortIndex(b.name)));

      if (!mounted) return;
      setState(() {
        _floors
          ..clear()
          ..addAll(merged);
        _loadingFloors = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingFloors = false;
        _error = 'Could not load floors: $e';
      });
    }
  }

  int _floorSortIndex(String name) {
    final lower = name.toLowerCase();
    for (var i = 0; i < _defaultFloors.length; i++) {
      if (_defaultFloors[i].toLowerCase() == lower) return i;
    }
    return 100 + name.hashCode.abs() % 1000;
  }

  HierarchyLevel? _unitLevel(List<HierarchyLevel> levels) {
    final enabled = levels.where((l) => l.isEnabled).toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    HierarchyLevel? pick(List<String> keys) {
      for (final k in keys) {
        final hit = enabled.where((l) => l.internalKey == k).firstOrNull;
        if (hit != null) return hit;
      }
      return null;
    }

    return pick(const ['unit', 'room', 'flat']) ??
        enabled.where((l) => l.supportsOccupancy).firstOrNull ??
        enabled.lastOrNull;
  }

  HierarchyLevel? _propertyLevel(List<HierarchyLevel> levels) {
    return levels
        .where((l) => l.isEnabled && l.internalKey == 'property')
        .firstOrNull;
  }

  void _selectKind(_SpaceKind kind) {
    setState(() {
      _kind = kind;
      _error = null;
      if (kind == _SpaceKind.entireProperty) {
        _selectedFloorKey = null;
        if (_nameController.text.trim().isEmpty) {
          _nameController.text = 'Entire House';
        }
      } else if (_nameController.text.trim() == 'Entire House') {
        _nameController.clear();
      }
    });
  }

  void _backToTypes() {
    setState(() {
      _kind = null;
      _error = null;
    });
  }

  _FloorOption? get _selectedFloor {
    if (_selectedFloorKey == null) return null;
    for (final f in _floors) {
      if (_floorKey(f) == _selectedFloorKey) return f;
    }
    return null;
  }

  Future<void> _promptAddFloor() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add floor'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Floor name',
            hintText: 'e.g., Basement, Mezzanine',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final v = controller.text.trim();
              if (v.isNotEmpty) Navigator.pop(ctx, v);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;

    for (final f in _floors) {
      if (f.name.toLowerCase() == name.toLowerCase()) {
        setState(() => _selectedFloorKey = _floorKey(f));
        return;
      }
    }
    final option = _FloorOption(name: name, isPendingCreate: true);
    setState(() {
      _floors.add(option);
      _floors.sort(
        (a, b) => _floorSortIndex(a.name).compareTo(_floorSortIndex(b.name)),
      );
      _selectedFloorKey = _floorKey(option);
    });
  }

  bool get _canSave {
    if (_saving || _kind == null) return false;
    if (_nameController.text.trim().isEmpty) return false;
    if (_kind!.needsFloor && _selectedFloor == null) return false;
    if (double.tryParse(_rentController.text.trim()) == null) return false;
    return true;
  }

  Future<void> _save() async {
    final kind = _kind;
    if (kind == null || !_canSave) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final repo = ref.read(structureRepositoryProvider);
      final levels = await ref.read(
        hierarchyLevelsProvider(widget.propertyId).future,
      );
      final unitLevel = _unitLevel(levels);
      if (unitLevel == null) {
        throw Exception('No occupancy level found for this property.');
      }

      String? propertyRootId;
      final propertyLevel = _propertyLevel(levels);
      if (propertyLevel != null) {
        final roots = await repo.listNodes(
          widget.propertyId,
          propertyLevel.id,
          parentNodeId: null,
        );
        if (roots.isNotEmpty) {
          propertyRootId = roots.first['id']?.toString();
        } else {
          final root = await repo.createNode(
            widget.propertyId,
            levelId: propertyLevel.id,
            parentNodeId: null,
            name: 'Main Property',
          );
          propertyRootId = root['id']?.toString();
        }
      }

      final spaceName = _nameController.text.trim();
      final rent = double.parse(_rentController.text.trim());
      final deposit = double.tryParse(_depositController.text.trim());

      String? parentNodeId = propertyRootId;

      if (kind.needsFloor) {
        final floorOpt = _selectedFloor!;
        if (floorOpt.nodeId != null) {
          parentNodeId = floorOpt.nodeId;
        } else {
          final floorNode = await repo.createNode(
            widget.propertyId,
            levelId: unitLevel.id,
            parentNodeId: propertyRootId,
            name: floorOpt.name,
            metadata: {'space_type': RentalSpaceType.floor.apiValue},
          );
          parentNodeId = floorNode['id']?.toString();
          if (parentNodeId == null || parentNodeId.isEmpty) {
            throw Exception('Could not create floor.');
          }
        }
      }

      final created = await repo.createNode(
        widget.propertyId,
        levelId: unitLevel.id,
        parentNodeId: parentNodeId,
        name: spaceName,
        monthlyRent: rent,
        securityDeposit: deposit,
        metadata: {'space_type': kind.rentalType.apiValue},
      );
      final id = created['id']?.toString();
      if (id == null) throw Exception('Space created but id missing.');
      if (!mounted) return;
      ref.invalidate(assignableUnitsProvider(widget.propertyId));
      Navigator.of(context).pop(
        CreatedSpaceResult(
          nodeId: id,
          name: spaceName,
          monthlyRent: rent,
          securityDeposit: deposit,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final kind = _kind;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(kind == null ? 'What are you renting?' : 'Space details'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (kind != null) {
              _backToTypes();
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: kind == null
            ? _buildTypeStep(key: const ValueKey('types'))
            : _buildDetailsStep(key: const ValueKey('details'), kind: kind),
      ),
    );
  }

  Widget _buildTypeStep({required Key key}) {
    return ListView(
      key: key,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        const Text(
          'Pick the kind of space this tenant will rent.',
          style: TextStyle(fontSize: 14, color: AppColors.slate, height: 1.4),
        ),
        const SizedBox(height: 16),
        ..._SpaceKind.values.map((k) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _TypeCard(
                emoji: k.emoji,
                title: k.title,
                subtitle: k.subtitle,
                onTap: () => _selectKind(k),
              ),
            )),
      ],
    );
  }

  Widget _buildDetailsStep({
    required Key key,
    required _SpaceKind kind,
  }) {
    return Column(
      key: key,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              _SelectedTypeBanner(
                emoji: kind.emoji,
                title: kind.title,
                onChange: _backToTypes,
              ),
              const SizedBox(height: 20),
              _fieldLabel('Space Name'),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
                decoration: _inputDecoration(hint: kind.nameHint),
              ),
              if (kind.needsFloor) ...[
                const SizedBox(height: 18),
                _fieldLabel('Floor Location'),
                const SizedBox(height: 8),
                if (_loadingFloors)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  DropdownButtonFormField<String>(
                    value: _selectedFloorKey,
                    decoration: _inputDecoration(hint: 'Select a floor'),
                    items: _floors
                        .map(
                          (f) => DropdownMenuItem(
                            value: _floorKey(f),
                            child: Text(f.name),
                          ),
                        )
                        .toList(),
                    onChanged: (key) =>
                        setState(() => _selectedFloorKey = key),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _promptAddFloor,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('+ Add Floor'),
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 18),
              _fieldLabel('Monthly Rent'),
              const SizedBox(height: 8),
              TextField(
                controller: _rentController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                onChanged: (_) => setState(() {}),
                decoration: _inputDecoration(
                  hint: 'e.g., 15000',
                  prefixText: '₹ ',
                ),
              ),
              const SizedBox(height: 18),
              _fieldLabel('Security Deposit'),
              const SizedBox(height: 8),
              TextField(
                controller: _depositController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                onChanged: (_) => setState(() {}),
                decoration: _inputDecoration(
                  hint: 'Optional',
                  prefixText: '₹ ',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: const TextStyle(color: AppColors.danger),
                ),
              ],
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: SizedBox(
              height: 54,
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _canSave ? _save : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor: Colors.grey.shade300,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Save Space',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _fieldLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
    );
  }

  InputDecoration _inputDecoration({String? hint, String? prefixText}) {
    return InputDecoration(
      hintText: hint,
      prefixText: prefixText,
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _TypeCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(18),
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
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(emoji, style: const TextStyle(fontSize: 26)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.slate,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.slate),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedTypeBanner extends StatelessWidget {
  final String emoji;
  final String title;
  final VoidCallback onChange;

  const _SelectedTypeBanner({
    required this.emoji,
    required this.title,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryDark,
              ),
            ),
          ),
          TextButton(
            onPressed: onChange,
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}

extension _LastOrNull<E> on List<E> {
  E? get lastOrNull => isEmpty ? null : last;
}
