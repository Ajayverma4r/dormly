// features/tenant_portal/presentation/owner_mess_menu_screen.dart
//
// Owner/Warden edits mess_menus for a property — same table tenants read.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/tenant_portal_repository.dart';

const _brand = Color(0xFF6D28D9);
const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _bg = Color(0xFFF8FAFC);

const _dayNames = [
  '',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

final ownerMessMenuProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, propertyId) async {
  return ref
      .watch(tenantPortalRepositoryProvider)
      .listMessMenuForProperty(propertyId);
});

class OwnerMessMenuScreen extends ConsumerStatefulWidget {
  final String propertyId;
  const OwnerMessMenuScreen({super.key, required this.propertyId});

  @override
  ConsumerState<OwnerMessMenuScreen> createState() =>
      _OwnerMessMenuScreenState();
}

class _OwnerMessMenuScreenState extends ConsumerState<OwnerMessMenuScreen> {
  int _day = DateTime.now().weekday;
  final _breakfast = TextEditingController();
  final _lunch = TextEditingController();
  final _dinner = TextEditingController();
  bool _saving = false;
  bool _hydrated = false;

  @override
  void dispose() {
    _breakfast.dispose();
    _lunch.dispose();
    _dinner.dispose();
    super.dispose();
  }

  void _hydrate(List<Map<String, dynamic>> rows) {
    Map<String, dynamic>? row;
    for (final r in rows) {
      final d = int.tryParse('${r['day_of_week'] ?? r['dayOfWeek'] ?? ''}');
      if (d == _day) {
        row = r;
        break;
      }
    }
    _breakfast.text = row?['breakfast']?.toString() ?? '';
    _lunch.text = row?['lunch']?.toString() ?? '';
    _dinner.text = row?['dinner']?.toString() ?? '';
    _hydrated = true;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(tenantPortalRepositoryProvider).upsertMessMenuDay(
            propertyId: widget.propertyId,
            dayOfWeek: _day,
            breakfast: _breakfast.text,
            lunch: _lunch.text,
            dinner: _dinner.text,
          );
      ref.invalidate(ownerMessMenuProvider(widget.propertyId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_dayNames[_day]} menu saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(ownerMessMenuProvider(widget.propertyId));
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
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (rows) {
          if (!_hydrated) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _hydrate(rows));
            });
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var d = 1; d <= 7; d++)
                    ChoiceChip(
                      label: Text(_dayNames[d].substring(0, 3)),
                      selected: _day == d,
                      selectedColor: _brand,
                      labelStyle: TextStyle(
                        color: _day == d ? Colors.white : _ink,
                        fontWeight: FontWeight.w700,
                      ),
                      onSelected: (_) {
                        setState(() {
                          _day = d;
                          _hydrate(rows);
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                _dayNames[_day],
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Separate dishes with commas. Tenants see this instantly.',
                style: TextStyle(color: _muted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              _field('Breakfast', _breakfast),
              const SizedBox(height: 12),
              _field('Lunch', _lunch),
              const SizedBox(height: 12),
              _field('Dinner', _dinner),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: _brand,
                  minimumSize: const Size.fromHeight(48),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save day'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl) {
    return TextField(
      controller: ctrl,
      maxLines: 3,
      decoration: InputDecoration(
        labelText: label,
        alignLabelWithHint: true,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
