// core/widgets/dynamic_icon.dart
//
// Maps the backend's string icon key (e.g. "building", "bed", "package")
// to a Material icon, and the color hex to a Color. This is the only place
// that translates config strings into Flutter types — screens never guess.

import 'package:flutter/material.dart';

class DynamicIcon extends StatelessWidget {
  final String? name;
  final String? colorHex;
  final double size;

  const DynamicIcon({super.key, this.name, this.colorHex, this.size = 24});

  static const Map<String, IconData> _icons = {
    'building': Icons.apartment_outlined,
    'layers': Icons.layers_outlined,
    'door-closed': Icons.meeting_room_outlined,
    'bed': Icons.bed_outlined,
    'home': Icons.home_outlined,
    'key': Icons.key_outlined,
    'users': Icons.groups_outlined,
    'briefcase': Icons.work_outline,
    'package': Icons.inventory_2_outlined,
    'sun': Icons.wb_sunny_outlined,
    'plus-circle': Icons.add_circle_outline,
    'book': Icons.menu_book_outlined,
    'settings': Icons.settings_outlined,
    'car': Icons.directions_car_outlined,
    'sliders': Icons.tune,
    'grid': Icons.grid_view_outlined,
    'archive': Icons.archive_outlined,
    'warehouse': Icons.warehouse_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final icon = _icons[name] ?? Icons.category_outlined;
    Color color = Theme.of(context).colorScheme.primary;
    if (colorHex != null) {
      try {
        color = Color(int.parse(colorHex!.replaceFirst('#', '0xff')));
      } catch (_) {}
    }
    return Icon(icon, size: size, color: color);
  }
}
