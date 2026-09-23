// features/tenancies/presentation/widgets/rental_space_picker.dart
//
// Controlled tenant-first space selection for Rental House properties:
// pick an existing space, or add a new one via categorized radios.

import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/assignable_unit.dart';

enum RentalSpaceKind {
  entireProperty,
  portionFloor,
  room,
  other,
}

class RentalSpaceSelection {
  final String? nodeId;
  final String spaceName;
  final bool isNew;

  const RentalSpaceSelection({
    required this.spaceName,
    this.nodeId,
    this.isNew = false,
  });

  bool get isValid => spaceName.trim().isNotEmpty;
}

class RentalSpacePicker extends StatefulWidget {
  final List<AssignableUnit> existingSpaces;
  final String? initialNodeId;
  final ValueChanged<RentalSpaceSelection> onChanged;

  const RentalSpacePicker({
    super.key,
    required this.existingSpaces,
    required this.onChanged,
    this.initialNodeId,
  });

  @override
  State<RentalSpacePicker> createState() => _RentalSpacePickerState();
}

class _RentalSpacePickerState extends State<RentalSpacePicker> {
  String? _selectedExistingId;
  bool _addingNew = false;
  RentalSpaceKind? _kind;
  final _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedExistingId = widget.initialNodeId;
    if (_selectedExistingId != null) {
      final match = widget.existingSpaces
          .where((u) => u.nodeId == _selectedExistingId)
          .firstOrNull;
      if (match != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.onChanged(RentalSpaceSelection(
            spaceName: match.nodeName,
            nodeId: match.nodeId,
          ));
        });
      }
    } else if (widget.existingSpaces.isEmpty) {
      // No spaces yet — open the "add new" flow by default.
      _addingNew = true;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _emitExisting(String? nodeId) {
    if (nodeId == null) {
      widget.onChanged(const RentalSpaceSelection(spaceName: ''));
      return;
    }
    final match =
        widget.existingSpaces.where((u) => u.nodeId == nodeId).firstOrNull;
    widget.onChanged(RentalSpaceSelection(
      spaceName: match?.nodeName ?? '',
      nodeId: nodeId,
    ));
  }

  void _emitNew() {
    final kind = _kind;
    if (kind == null) {
      widget.onChanged(const RentalSpaceSelection(spaceName: '', isNew: true));
      return;
    }
    if (kind == RentalSpaceKind.entireProperty) {
      widget.onChanged(const RentalSpaceSelection(
        spaceName: 'Entire Property',
        isNew: true,
      ));
      return;
    }
    widget.onChanged(RentalSpaceSelection(
      spaceName: _nameController.text.trim(),
      isNew: true,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final hasExisting = widget.existingSpaces.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'What are they renting?',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        const SizedBox(height: 8),
        if (hasExisting && !_addingNew) ...[
          DropdownButtonFormField<String>(
            value: _selectedExistingId,
            decoration: InputDecoration(
              labelText: 'Existing space',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            items: widget.existingSpaces
                .map(
                  (u) => DropdownMenuItem(
                    value: u.nodeId,
                    child: Text(
                      u.occupied
                          ? '${u.pathLabel} (occupied)'
                          : u.pathLabel,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (id) {
              setState(() => _selectedExistingId = id);
              _emitExisting(id);
            },
            validator: (_) {
              if (_addingNew) return null;
              if (_selectedExistingId == null ||
                  _selectedExistingId!.isEmpty) {
                return 'Select a space or add a new one';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _addingNew = true;
                _selectedExistingId = null;
                _kind = null;
                _nameController.clear();
              });
              widget.onChanged(
                const RentalSpaceSelection(spaceName: '', isNew: true),
              );
            },
            icon: const Icon(Icons.add),
            label: const Text('+ Add new space'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.blueprint,
              side: const BorderSide(color: AppColors.blueprint),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
        if (_addingNew) ...[
          if (hasExisting)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () {
                  setState(() {
                    _addingNew = false;
                    _kind = null;
                    _nameController.clear();
                  });
                  widget.onChanged(const RentalSpaceSelection(spaceName: ''));
                },
                child: const Text('← Use existing space'),
              ),
            ),
          const Text(
            'What kind of space?',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 4),
          ..._kindTiles(),
          if (_kind != null && _kind != RentalSpaceKind.entireProperty) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameController,
              onChanged: (_) {
                setState(() {});
                _emitNew();
              },
              validator: (v) {
                if (!_addingNew || _kind == RentalSpaceKind.entireProperty) {
                  return null;
                }
                if (v == null || v.trim().isEmpty) {
                  return 'Space name is required';
                }
                return null;
              },
              decoration: InputDecoration(
                labelText: 'Space name *',
                hintText: _hintForKind(_kind),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
          if (_kind == RentalSpaceKind.entireProperty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.blueprint.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.blueprint.withOpacity(0.2),
                ),
              ),
              child: const Text(
                'Space will be saved as “Entire Property”.',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ],
      ],
    );
  }

  List<Widget> _kindTiles() {
    const options = <(RentalSpaceKind, String)>[
      (RentalSpaceKind.entireProperty, 'Entire property'),
      (RentalSpaceKind.portionFloor, 'A portion / floor'),
      (RentalSpaceKind.room, 'A room'),
      (RentalSpaceKind.other, 'Other'),
    ];
    return options
        .map(
          (opt) => RadioListTile<RentalSpaceKind>(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(opt.$2),
            value: opt.$1,
            groupValue: _kind,
            activeColor: AppColors.blueprint,
            onChanged: (v) {
              setState(() {
                _kind = v;
                if (v == RentalSpaceKind.entireProperty) {
                  _nameController.text = 'Entire Property';
                } else if (_nameController.text == 'Entire Property') {
                  _nameController.clear();
                }
              });
              _emitNew();
            },
          ),
        )
        .toList();
  }

  String _hintForKind(RentalSpaceKind? kind) {
    switch (kind) {
      case RentalSpaceKind.portionFloor:
        return 'e.g. Ground Floor';
      case RentalSpaceKind.room:
        return 'e.g. Room 1';
      case RentalSpaceKind.other:
        return 'e.g. Shop front, Garage';
      default:
        return 'Space name';
    }
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
