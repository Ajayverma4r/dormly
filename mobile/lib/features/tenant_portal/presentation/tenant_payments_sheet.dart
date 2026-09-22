// features/tenant_portal/presentation/tenant_payments_sheet.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import 'tenant_portal_providers.dart';

const _brand = Color(0xFF5218D1);
final _currency =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// Bottom sheet listing outstanding invoices for the logged-in tenant.
Future<void> showTenantRentPaymentsSheet({
  required BuildContext context,
  required WidgetRef ref,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Consumer(
            builder: (context, ref, _) {
              final async = ref.watch(myInvoicesProvider);
              return async.when(
                loading: () => const SizedBox(
                  height: 160,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Text('Could not load dues: $e'),
                data: (invoices) {
                  final due = invoices.where((inv) {
                    final total =
                        double.tryParse(inv['total_amount'].toString()) ?? 0;
                    final paid =
                        double.tryParse(inv['paid_amount'].toString()) ?? 0;
                    return total - paid > 0.009;
                  }).toList();

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.black12,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Pay via UPI / Owner',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        due.isEmpty
                            ? 'You have no outstanding dues.'
                            : 'Outstanding invoices — clear them with your owner via UPI.',
                        style: const TextStyle(
                          color: AppColors.slate,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (due.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Icon(Icons.check_circle,
                                color: Color(0xFF10B981), size: 40),
                          ),
                        )
                      else
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: MediaQuery.sizeOf(ctx).height * 0.45,
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: due.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              final inv = due[i];
                              final total = double.tryParse(
                                      inv['total_amount'].toString()) ??
                                  0;
                              final paid = double.tryParse(
                                      inv['paid_amount'].toString()) ??
                                  0;
                              final remaining = total - paid;
                              final dueDate = inv['due_date']
                                      ?.toString()
                                      .split('T')
                                      .first ??
                                  '—';
                              final rawLines = inv['lineItems'] ??
                                  inv['line_items'] ??
                                  const [];
                              final lineItems = rawLines is List
                                  ? rawLines
                                      .whereType<Map>()
                                      .map((e) =>
                                          Map<String, dynamic>.from(e))
                                      .toList()
                                  : <Map<String, dynamic>>[];
                              return Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF3E8FF),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.payments_outlined,
                                            color: _brand),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Due $dueDate',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              Text(
                                                'Pending ${_currency.format(remaining)}',
                                                style: const TextStyle(
                                                  color: _brand,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (lineItems.isNotEmpty) ...[
                                      const SizedBox(height: 10),
                                      ...lineItems.map((li) {
                                        final amt = double.tryParse(
                                                li['amount']?.toString() ??
                                                    '') ??
                                            0;
                                        final label = (li['description'] ??
                                                'Charge')
                                            .toString();
                                        return Padding(
                                          padding: const EdgeInsets.only(
                                              bottom: 4),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  label,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: AppColors.slate,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                _currency.format(amt),
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }),
                                      const Divider(height: 16),
                                      Row(
                                        children: [
                                          const Expanded(
                                            child: Text(
                                              'Total',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            _currency.format(total),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          style: FilledButton.styleFrom(
                            backgroundColor: _brand,
                          ),
                          child: const Text('Got it'),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      );
    },
  );
}
