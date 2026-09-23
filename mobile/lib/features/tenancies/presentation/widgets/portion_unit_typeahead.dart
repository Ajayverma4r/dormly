// features/tenancies/presentation/widgets/portion_unit_typeahead.dart
//
// Searchable dropdown that lists existing units but also accepts a brand-new
// free-text portion name (tenant-first rental houses).

import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/assignable_unit.dart';

class PortionUnitTypeahead extends StatefulWidget {
  final List<AssignableUnit> units;
  final String? initialText;
  final ValueChanged<PortionUnitSelection> onChanged;

  const PortionUnitTypeahead({
    super.key,
    required this.units,
    required this.onChanged,
    this.initialText,
  });

  @override
  State<PortionUnitTypeahead> createState() => _PortionUnitTypeaheadState();
}

class PortionUnitSelection {
  /// Existing node id when user picks a suggestion; null for a new name.
  final String? nodeId;
  final String unitName;

  const PortionUnitSelection({required this.unitName, this.nodeId});
}

class _PortionUnitTypeaheadState extends State<PortionUnitTypeahead> {
  late final TextEditingController _controller;
  final _focus = FocusNode();
  bool _showOptions = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText ?? '');
    _focus.addListener(() {
      setState(() => _showOptions = _focus.hasFocus);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<AssignableUnit> get _filtered {
    final q = _controller.text.trim().toLowerCase();
    if (q.isEmpty) return widget.units;
    return widget.units
        .where((u) =>
            u.pathLabel.toLowerCase().contains(q) ||
            u.nodeName.toLowerCase().contains(q))
        .toList();
  }

  void _emit() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      widget.onChanged(const PortionUnitSelection(unitName: ''));
      return;
    }
    AssignableUnit? match;
    for (final u in widget.units) {
      if (u.nodeName.toLowerCase() == text.toLowerCase() ||
          u.pathLabel.toLowerCase() == text.toLowerCase()) {
        match = u;
        break;
      }
    }
    widget.onChanged(
      PortionUnitSelection(
        unitName: text,
        nodeId: match?.nodeId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final options = _filtered;
    final typed = _controller.text.trim();
    final exactExists = widget.units.any(
      (u) =>
          u.nodeName.toLowerCase() == typed.toLowerCase() ||
          u.pathLabel.toLowerCase() == typed.toLowerCase(),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _controller,
          focusNode: _focus,
          validator: (v) =>
              (v == null || v.trim().isEmpty)
                  ? 'Property Portion / Unit is required'
                  : null,
          onChanged: (_) {
            setState(() {});
            _emit();
          },
          decoration: InputDecoration(
            labelText: 'Property Portion / Unit *',
            hintText: 'e.g. Ground Floor, 1st Floor - Room 1',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            suffixIcon: const Icon(Icons.search),
          ),
        ),
        if (_showOptions && (options.isNotEmpty || typed.isNotEmpty))
          Material(
            elevation: 3,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: [
                  ...options.map((u) {
                    return ListTile(
                      dense: true,
                      title: Text(u.pathLabel,
                          style: const TextStyle(fontSize: 13)),
                      subtitle: Text(
                        u.occupied ? 'Occupied' : 'Vacant · ${u.levelName}',
                        style: TextStyle(
                          fontSize: 11,
                          color: u.occupied
                              ? AppColors.danger
                              : AppColors.positive,
                        ),
                      ),
                      onTap: () {
                        _controller.text = u.nodeName;
                        _focus.unfocus();
                        setState(() => _showOptions = false);
                        widget.onChanged(
                          PortionUnitSelection(
                            unitName: u.nodeName,
                            nodeId: u.nodeId,
                          ),
                        );
                      },
                    );
                  }),
                  if (typed.isNotEmpty && !exactExists)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.add, size: 18),
                      title: Text(
                        'Create “$typed”',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.blueprint,
                        ),
                      ),
                      subtitle: const Text(
                        'New unit — created when you save the tenant',
                        style: TextStyle(fontSize: 11),
                      ),
                      onTap: () {
                        _focus.unfocus();
                        setState(() => _showOptions = false);
                        _emit();
                      },
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 6),
        Text(
          typed.isNotEmpty && !exactExists
              ? 'A new unit named “$typed” will be created when you save.'
              : 'Search existing units or type a new portion name.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}
