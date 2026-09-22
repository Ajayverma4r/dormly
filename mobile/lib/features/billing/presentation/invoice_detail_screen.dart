// features/billing/presentation/invoice_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../data/billing_repository.dart';
import 'record_payment_dialog.dart';

final invoiceDetailProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, (String, String)>(
  (ref, args) =>
      ref.watch(billingRepositoryProvider).getInvoice(args.$1, args.$2),
);

final _currency =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

class InvoiceDetailScreen extends ConsumerStatefulWidget {
  final String propertyId;
  final String invoiceId;

  /// When true, hides Record Payment / Send Reminder (Reports view-only).
  final bool viewOnly;

  const InvoiceDetailScreen({
    super.key,
    required this.propertyId,
    required this.invoiceId,
    this.viewOnly = false,
  });

  @override
  ConsumerState<InvoiceDetailScreen> createState() =>
      _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends ConsumerState<InvoiceDetailScreen> {
  Future<void> _recordPayment(double remaining) async {
    final result = await showRecordPaymentDialog(
      context: context,
      outstandingLabel: 'Outstanding: ${_currency.format(remaining)}',
      initialAmount: remaining,
      maxAmount: remaining,
    );
    if (result == null || result.amount <= 0) return;

    try {
      await ref.read(billingRepositoryProvider).recordPayment(
            widget.propertyId,
            widget.invoiceId,
            result.amount,
            result.method,
          );
      ref.invalidate(
        invoiceDetailProvider((widget.propertyId, widget.invoiceId)),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not record payment: $e')),
        );
      }
    }
  }

  Future<void> _sendReminder() async {
    try {
      await ref
          .read(billingRepositoryProvider)
          .sendReminder(widget.propertyId, widget.invoiceId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reminder sent')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send reminder: $e')),
        );
      }
    }
  }

  String _lineLabel(Map<String, dynamic> li) {
    final desc = (li['description'] ?? '').toString().trim();
    if (desc.isNotEmpty) return desc;
    final kind = (li['charge_kind'] ?? li['chargeKind'] ?? '').toString();
    switch (kind) {
      case 'previous_dues':
        return 'Previous Dues';
      case 'rent':
        return 'Rent';
      case 'electricity':
        return 'Electricity';
      case 'maintenance':
        return 'Maintenance';
      default:
        return (li['charge_type_name'] ?? 'Charge').toString();
    }
  }

  Color? _kindAccent(Map<String, dynamic> li) {
    final kind = (li['charge_kind'] ?? li['chargeKind'] ?? '').toString();
    final desc = _lineLabel(li).toLowerCase();
    if (kind == 'previous_dues' ||
        desc.contains('previous dues') ||
        desc.contains('arrears')) {
      return const Color(0xFFB45309);
    }
    if (kind == 'electricity' || desc.contains('electric')) {
      return const Color(0xFF2563EB);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final invoiceAsync = ref.watch(
      invoiceDetailProvider((widget.propertyId, widget.invoiceId)),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Invoice')),
      body: invoiceAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) =>
            Center(child: Text('Something went wrong: $err')),
        data: (invoice) {
          final rawLines =
              invoice['lineItems'] ?? invoice['line_items'] ?? const [];
          final lineItems = rawLines is List
              ? rawLines
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList()
              : <Map<String, dynamic>>[];
          final payments = List<Map<String, dynamic>>.from(
            invoice['payments'] ?? const [],
          );
          final total =
              double.tryParse(invoice['total_amount'].toString()) ?? 0;
          final paid = payments.fold<double>(
            0,
            (sum, p) =>
                sum + (double.tryParse(p['amount'].toString()) ?? 0),
          );
          final remaining = total - paid;
          final status =
              (invoice['status'] ?? 'pending').toString().toUpperCase();
          final due =
              invoice['due_date']?.toString().split('T').first ?? '—';

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Status: $status',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text('Due: $due'),
                    const Divider(height: 24),
                    const Text(
                      'Breakdown',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (lineItems.isEmpty)
                      Text(
                        'No line items',
                        style: TextStyle(color: Colors.grey.shade600),
                      )
                    else
                      ...lineItems.map((li) {
                        final amount =
                            double.tryParse(li['amount'].toString()) ?? 0;
                        final accent = _kindAccent(li);
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  _lineLabel(li),
                                  style: TextStyle(
                                    fontWeight: accent != null
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    color: accent ?? Colors.black87,
                                  ),
                                ),
                              ),
                              Text(
                                _currency.format(amount),
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: accent,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          _currency.format(total),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Paid'),
                        Text(_currency.format(paid)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Remaining',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          _currency.format(remaining),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (!widget.viewOnly && remaining > 0) ...[
                SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2ECC71),
                    ),
                    onPressed: () => _recordPayment(remaining),
                    icon: const Icon(
                      Icons.payments_outlined,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'Record Payment',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: _sendReminder,
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: const Text('Send Reminder'),
                  ),
                ),
              ],
              if (payments.isNotEmpty) ...[
                const SizedBox(height: 24),
                const Text(
                  'Payment History',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                ...payments.map(
                  (p) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.check_circle_outline,
                      color: Color(0xFF2ECC71),
                    ),
                    title: Text(_currency.format(
                      double.tryParse(p['amount'].toString()) ?? 0,
                    )),
                    subtitle: Text(
                      '${p['method']} · ${p['paid_at'].toString().split('T').first}',
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
