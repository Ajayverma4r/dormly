// features/tenant_portal/presentation/widgets/rental_meter_upload_widget.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../meter_reading_screen.dart';
import '../tenant_portal_providers.dart';
import 'module_async_body.dart';

const _brand = Color(0xFF5218D1);
const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);

/// Rental / flat / commercial — meter prefetch isolated from dashboard core.
class RentalMeterUploadWidget extends ConsumerWidget {
  final String title;

  const RentalMeterUploadWidget({
    super.key,
    this.title = 'Upload Meter Reading',
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(tenantMeterReadingsProvider);

    return ModuleAsyncBody<List<Map<String, dynamic>>>(
      async: async,
      errorLabel: 'Failed to load meter readings',
      onRetry: () => ref.invalidate(tenantMeterReadingsProvider),
      builder: (rows) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MeterReadingScreen()),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.bolt_rounded,
                    color: Color(0xFFD97706),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        rows.isEmpty
                            ? 'Submit a reading — dues update on the shared billing ledger.'
                            : 'Last reading: ${rows.first['meter_reading_value']}',
                        style: const TextStyle(fontSize: 12.5, color: _muted),
                      ),
                    ],
                  ),
                ),
                const Text(
                  'Open →',
                  style: TextStyle(
                    color: _brand,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
