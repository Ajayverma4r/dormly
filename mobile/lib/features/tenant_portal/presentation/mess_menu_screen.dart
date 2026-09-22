// features/tenant_portal/presentation/mess_menu_screen.dart
//
// Screen 11 — weekly day pills + breakfast / lunch / dinner from mess_menus.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'tenant_portal_providers.dart';

const _brand = Color(0xFF6D28D9);
const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _bg = Color(0xFFF8FAFC);

final _dateFmt = DateFormat('d MMM yyyy');

final messMenuProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  // Alias → type-gated provider (skips API for non-hostel).
  return ref.watch(tenantMessMenuProvider.future);
});

List<String> _splitMeals(String? raw) {
  if (raw == null || raw.trim().isEmpty) return ['Not set yet'];
  return raw
      .split(RegExp(r'[\n,•|]'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
}

class MessMenuScreen extends ConsumerStatefulWidget {
  const MessMenuScreen({super.key});

  @override
  ConsumerState<MessMenuScreen> createState() => _MessMenuScreenState();
}

class _MessMenuScreenState extends ConsumerState<MessMenuScreen> {
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selected = DateTime(now.year, now.month, now.day);
  }

  List<DateTime> get _week {
    final monday = _selected.subtract(Duration(days: _selected.weekday - 1));
    return List.generate(7, (i) => monday.add(Duration(days: i)));
  }

  Map<String, dynamic>? _rowForDay(
    List<Map<String, dynamic>> rows,
    int weekday,
  ) {
    for (final r in rows) {
      final d = int.tryParse('${r['day_of_week'] ?? r['dayOfWeek'] ?? ''}');
      if (d == weekday) return r;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(messMenuProvider);
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        foregroundColor: _ink,
        title: const Text(
          'Mess Menu',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(messMenuProvider),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Could not load mess menu.\n$e',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted),
            ),
          ),
        ),
        data: (rows) {
          final day = _rowForDay(rows, _selected.weekday);
          final breakfast = _splitMeals(day?['breakfast']?.toString());
          final lunch = _splitMeals(day?['lunch']?.toString());
          final dinner = _splitMeals(day?['dinner']?.toString());
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(messMenuProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                SizedBox(
                  height: 42,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: 7,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final dayDate = _week[i];
                      final active = dayDate.day == _selected.day &&
                          dayDate.month == _selected.month;
                      final label =
                          DateFormat('E').format(dayDate).substring(0, 3);
                      return ChoiceChip(
                        label: Text(label),
                        selected: active,
                        onSelected: (_) =>
                            setState(() => _selected = dayDate),
                        selectedColor: _brand,
                        labelStyle: TextStyle(
                          color: active ? Colors.white : _ink,
                          fontWeight: FontWeight.w700,
                        ),
                        backgroundColor: Colors.white,
                        side: BorderSide(
                          color: active ? _brand : const Color(0xFFE2E8F0),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _dateFmt.format(_selected),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _muted,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 18),
                _MealCard(
                  title: 'Breakfast',
                  time: '7:00 AM – 9:30 AM',
                  icon: Icons.wb_sunny_outlined,
                  items: breakfast,
                ),
                const SizedBox(height: 12),
                _MealCard(
                  title: 'Lunch',
                  time: '12:30 PM – 2:30 PM',
                  icon: Icons.restaurant_outlined,
                  items: lunch,
                ),
                const SizedBox(height: 12),
                _MealCard(
                  title: 'Dinner',
                  time: '7:30 PM – 9:30 PM',
                  icon: Icons.nightlight_round,
                  items: dinner,
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 18, color: _muted),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Menu is managed by your property. Pull to refresh for the latest update.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: _muted,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MealCard extends StatelessWidget {
  final String title;
  final String time;
  final IconData icon;
  final List<String> items;

  const _MealCard({
    required this.title,
    required this.time,
    required this.icon,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _brand, size: 22),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: _ink,
                ),
              ),
              const Spacer(),
              Text(time, style: const TextStyle(fontSize: 12, color: _muted)),
            ],
          ),
          const SizedBox(height: 12),
          ...items.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(Icons.circle, size: 6, color: _brand),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      e,
                      style: const TextStyle(color: _ink, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
