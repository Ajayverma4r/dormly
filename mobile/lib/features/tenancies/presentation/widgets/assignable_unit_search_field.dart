// features/tenancies/presentation/widgets/assignable_unit_search_field.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/assignable_unit.dart';

class AssignableUnitSearchField extends StatelessWidget {
  final List<AssignableUnit> units;
  final String? selectedNodeId;
  final ValueChanged<AssignableUnit?> onSelected;

  const AssignableUnitSearchField({
    super.key,
    required this.units,
    required this.onSelected,
    this.selectedNodeId,
  });

  @override
  Widget build(BuildContext context) {
    AssignableUnit? selected;
    for (final u in units) {
      if (u.nodeId == selectedNodeId) {
        selected = u;
        break;
      }
    }

    return Autocomplete<AssignableUnit>(
      initialValue: selected != null
          ? TextEditingValue(text: selected.pathLabel)
          : null,
      displayStringForOption: (u) => u.pathLabel,
      optionsBuilder: (query) {
        final q = query.text.toLowerCase();
        return units.where((u) {
          if (q.isEmpty) return true;
          return u.pathLabel.toLowerCase().contains(q) ||
              u.nodeName.toLowerCase().contains(q);
        });
      },
      onSelected: onSelected,
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: 'Unit *',
            hintText: 'Search by building, room, bed…',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            suffixIcon: const Icon(Icons.search),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, maxWidth: 400),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, i) {
                  final u = options.elementAt(i);
                  return ListTile(
                    dense: true,
                    title:
                        Text(u.pathLabel, style: const TextStyle(fontSize: 13)),
                    subtitle: Text(
                      u.occupied ? 'Occupied' : 'Vacant · ${u.levelName}',
                      style: TextStyle(
                        fontSize: 11,
                        color:
                            u.occupied ? AppColors.danger : AppColors.positive,
                      ),
                    ),
                    onTap: () => onSelected(u),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
