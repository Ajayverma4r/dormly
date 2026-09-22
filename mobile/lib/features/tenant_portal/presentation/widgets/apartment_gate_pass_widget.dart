// features/tenant_portal/presentation/widgets/apartment_gate_pass_widget.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../gate_pass_screen.dart';
import '../tenant_portal_providers.dart';
import 'module_async_body.dart';

const _brand = Color(0xFF5218D1);
const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);

/// Apartment only — prefetches gate passes; errors stay in this card.
class ApartmentGatePassWidget extends ConsumerWidget {
  const ApartmentGatePassWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(tenantGatePassesProvider);

    return Column(
      children: [
        ModuleAsyncBody<List<Map<String, dynamic>>>(
          async: async,
          errorLabel: 'Failed to load gate passes',
          onRetry: () => ref.invalidate(tenantGatePassesProvider),
          builder: (rows) => Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const GatePassScreen()),
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
                        color: const Color(0xFFDBEAFE),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.badge_outlined,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Gate Passes & Visitor Log',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: _ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            rows.isEmpty
                                ? 'Approve deliveries and guest entries for your flat.'
                                : '${rows.length} request(s) on file',
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: _muted,
                            ),
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
        ),
        const SizedBox(height: 12),
        // Society notices — same apartment channel, isolated provider.
        ModuleAsyncBody<List<Map<String, dynamic>>>(
          async: ref.watch(tenantSocietyNoticesProvider),
          errorLabel: 'Failed to load society notices',
          onRetry: () => ref.invalidate(tenantSocietyNoticesProvider),
          skeletonHeight: 64,
          builder: (notices) => Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.campaign_outlined, color: Color(0xFF059669)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    notices.isEmpty
                        ? 'No society notices yet'
                        : '${notices.length} society notice(s)',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _ink,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
