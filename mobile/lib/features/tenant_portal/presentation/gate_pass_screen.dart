// features/tenant_portal/presentation/gate_pass_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../data/tenant_portal_repository.dart';

const _brand = Color(0xFF6D28D9);
const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _bg = Color(0xFFF8FAFC);

final myGatePassesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return ref.watch(tenantPortalRepositoryProvider).myGatePasses();
});

class GatePassScreen extends ConsumerStatefulWidget {
  const GatePassScreen({super.key});

  @override
  ConsumerState<GatePassScreen> createState() => _GatePassScreenState();
}

class _GatePassScreenState extends ConsumerState<GatePassScreen> {
  final _name = TextEditingController();
  final _notes = TextEditingController();
  String _purpose = 'visitor';
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(tenantPortalRepositoryProvider).createGatePass(
            visitorName: _name.text.trim(),
            purpose: _purpose,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          );
      _name.clear();
      _notes.clear();
      ref.invalidate(myGatePassesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gate pass requested — owner notified')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myGatePassesProvider);
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        foregroundColor: _ink,
        title: const Text(
          'Gate Passes',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          const Text(
            'New request',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _name,
            decoration: InputDecoration(
              labelText: 'Visitor / delivery name',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _purpose,
            decoration: InputDecoration(
              labelText: 'Purpose',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            items: const [
              DropdownMenuItem(value: 'visitor', child: Text('Visitor')),
              DropdownMenuItem(value: 'delivery', child: Text('Delivery')),
              DropdownMenuItem(value: 'service', child: Text('Service')),
            ],
            onChanged: (v) => setState(() => _purpose = v ?? 'visitor'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _notes,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Notes (optional)',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _saving ? null : _submit,
            style: FilledButton.styleFrom(backgroundColor: _brand),
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Request gate pass'),
          ),
          const SizedBox(height: 28),
          const Text(
            'Your requests',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 10),
          async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('$e', style: const TextStyle(color: _muted)),
            data: (rows) {
              if (rows.isEmpty) {
                return const Text(
                  'No gate passes yet.',
                  style: TextStyle(color: _muted),
                );
              }
              final fmt = DateFormat('d MMM, h:mm a');
              return Column(
                children: rows.map((r) {
                  final created = DateTime.tryParse(
                    r['created_at']?.toString() ?? '',
                  );
                  final status = r['status']?.toString() ?? 'pending';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r['visitor_name']?.toString() ?? '',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                r['purpose']?.toString() ?? '',
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 12,
                                ),
                              ),
                              if (created != null)
                                Text(
                                  fmt.format(created.toLocal()),
                                  style: const TextStyle(
                                    color: _muted,
                                    fontSize: 11,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Text(
                          status.toUpperCase(),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                            color: status == 'approved'
                                ? const Color(0xFF059669)
                                : status == 'denied'
                                    ? Colors.red
                                    : _brand,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
