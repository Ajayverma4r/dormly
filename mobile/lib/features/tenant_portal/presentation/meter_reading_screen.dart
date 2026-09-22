// features/tenant_portal/presentation/meter_reading_screen.dart
//
// Tenant submits meter reading → shared meter_readings + invoice line item.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../data/tenant_portal_repository.dart';
import 'tenant_portal_providers.dart';

const _brand = Color(0xFF6D28D9);
const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _bg = Color(0xFFF8FAFC);

final myMeterReadingsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return ref.watch(tenantMeterReadingsProvider.future);
});

class MeterReadingScreen extends ConsumerStatefulWidget {
  const MeterReadingScreen({super.key});

  @override
  ConsumerState<MeterReadingScreen> createState() => _MeterReadingScreenState();
}

class _MeterReadingScreenState extends ConsumerState<MeterReadingScreen> {
  final _readingCtrl = TextEditingController();
  final _picker = ImagePicker();
  XFile? _photo;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _readingCtrl.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 75,
    );
    if (file == null) return;
    setState(() => _photo = file);
  }

  Future<void> _submit() async {
    final raw = _readingCtrl.text.trim();
    final value = double.tryParse(raw);
    if (value == null || value <= 0) {
      setState(() => _error = 'Enter a valid meter reading.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final now = DateTime.now();
      final cycle =
          '${now.year}-${now.month.toString().padLeft(2, '0')}';
      await ref.read(tenantPortalRepositoryProvider).submitMeterReading(
            readingValue: value,
            billingCycle: cycle,
            imagePath: _photo?.path,
          );
      _readingCtrl.clear();
      setState(() => _photo = null);
      ref.invalidate(myMeterReadingsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reading submitted. Owner notified.'),
          ),
        );
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myMeterReadingsProvider);
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        foregroundColor: _ink,
        title: const Text(
          'Meter / Electricity',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          const Text(
            'Submit reading',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _readingCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: 'Current meter reading',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pick,
            icon: const Icon(Icons.photo_camera_outlined),
            label: Text(_photo == null ? 'Add meter photo' : 'Photo attached'),
          ),
          if (_photo != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(File(_photo!.path), height: 140, fit: BoxFit.cover),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _saving ? null : _submit,
            style: FilledButton.styleFrom(backgroundColor: _brand),
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Submit reading'),
          ),
          const SizedBox(height: 28),
          const Text(
            'History',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 10),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('$e', style: const TextStyle(color: _muted)),
            data: (rows) {
              if (rows.isEmpty) {
                return const Text(
                  'No readings yet.',
                  style: TextStyle(color: _muted),
                );
              }
              final fmt = DateFormat('d MMM yyyy, h:mm a');
              return Column(
                children: rows.map((r) {
                  final created = DateTime.tryParse(
                    r['created_at']?.toString() ?? '',
                  );
                  final amount = r['amount'];
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
                                '${r['meter_reading_value']} units',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                r['billing_cycle']?.toString() ?? '',
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
                        if (amount != null)
                          Text(
                            '₹$amount',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: _brand,
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
