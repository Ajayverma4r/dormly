// features/billing/presentation/invoice_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../data/billing_repository.dart';
import 'billing_invoice_helpers.dart';
import 'billing_providers.dart';
import 'create_invoice_screen.dart';
import 'invoice_send_flow.dart';
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

  Future<void> _editDueDate(DateTime current) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    final dueDate = DateFormat('yyyy-MM-dd').format(picked);
    try {
      await ref.read(billingRepositoryProvider).updateDueDate(
            widget.propertyId,
            widget.invoiceId,
            dueDate: dueDate,
          );
      ref.invalidate(
        invoiceDetailProvider((widget.propertyId, widget.invoiceId)),
      );
      ref.invalidate(invoicesProvider(widget.propertyId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update due date: $e')),
        );
      }
    }
  }

  void _refresh() {
    ref.invalidate(
      invoiceDetailProvider((widget.propertyId, widget.invoiceId)),
    );
    ref.invalidate(invoicesProvider(widget.propertyId));
  }

  Future<void> _reviewAndEdit(Map<String, dynamic> invoice) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateInvoiceScreen(
          propertyId: widget.propertyId,
          invoiceId: widget.invoiceId,
          invoice: invoice,
        ),
      ),
    );
    _refresh();
  }

  Future<void> _sendToTenant(Map<String, dynamic> invoice) async {
    final sent = await confirmAndSendInvoice(
      context,
      ref,
      propertyId: widget.propertyId,
      invoice: invoice,
    );
    if (sent) _refresh();
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
          final remaining = (total - paid).clamp(0.0, double.infinity);
          final isDraft = isDraftInvoice(invoice);
          final backendStatus =
              (invoice['status'] ?? 'pending').toString().toUpperCase();
          final status = isDraft
              ? 'DRAFT — REVIEW REQUIRED'
              : isOverdueInvoice(invoice) && backendStatus != 'OVERDUE'
                  ? '$backendStatus · OVERDUE'
                  : backendStatus;
          final dueDate = invoiceDueDate(invoice);
          final dueLabel = dueDate == null
              ? '—'
              : DateFormat('d MMM yyyy').format(dueDate);
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (isDraft && !widget.viewOnly) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDE9FE),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFC4B5FD)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.rate_review_outlined,
                          color: Color(0xFF6D28D9)),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Generated automatically and not yet visible to the '
                          'tenant. Check rent, utilities and the due date, '
                          'then send it.',
                          style: TextStyle(
                            color: Color(0xFF4C1D95),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
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
                    if (!widget.viewOnly)
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Due Date',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF6B7280),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  dueLabel,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: dueDate == null
                                ? null
                                : () => _editDueDate(dueDate),
                            child: const Text('Edit'),
                          ),
                        ],
                      )
                    else
                      Text('Due: $dueLabel'),
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
              if (!widget.viewOnly && isDraft) ...[
                SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6D28D9),
                    ),
                    onPressed: () => _sendToTenant(invoice),
                    icon: const Icon(Icons.send_rounded, color: Colors.white),
                    label: const Text(
                      'Send to Tenant',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: () => _reviewAndEdit(invoice),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Review & Edit Charges'),
                  ),
                ),
                const SizedBox(height: 10),
              ],
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
                if (!isDraft) ...[
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
