// features/billing/presentation/invoice_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/billing_repository.dart';

final invoiceDetailProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, (String, String)>(
  (ref, args) => ref.watch(billingRepositoryProvider).getInvoice(args.$1, args.$2),
);

class InvoiceDetailScreen extends ConsumerStatefulWidget {
  final String propertyId;
  final String invoiceId;
  const InvoiceDetailScreen({super.key, required this.propertyId, required this.invoiceId});

  @override
  ConsumerState<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends ConsumerState<InvoiceDetailScreen> {
  Future<void> _recordPayment(double remaining) async {
    final controller = TextEditingController(text: remaining.toStringAsFixed(0));
    final amount = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Record Payment'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(prefixText: '₹', labelText: 'Amount'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, double.tryParse(controller.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (amount == null || amount <= 0) return;

    try {
      await ref.read(billingRepositoryProvider).recordPayment(widget.propertyId, widget.invoiceId, amount, 'cash');
      ref.invalidate(invoiceDetailProvider((widget.propertyId, widget.invoiceId)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not record payment: $e')));
    }
  }

  Future<void> _sendReminder() async {
    try {
      await ref.read(billingRepositoryProvider).sendReminder(widget.propertyId, widget.invoiceId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reminder sent')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not send reminder: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final invoiceAsync = ref.watch(invoiceDetailProvider((widget.propertyId, widget.invoiceId)));

    return Scaffold(
      appBar: AppBar(title: const Text('Invoice')),
      body: invoiceAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Something went wrong: $err')),
        data: (invoice) {
          final lineItems = List<Map<String, dynamic>>.from(invoice['lineItems']);
          final payments = List<Map<String, dynamic>>.from(invoice['payments']);
          final total = double.tryParse(invoice['total_amount'].toString()) ?? 0;
          final paid = payments.fold<double>(0, (sum, p) => sum + (double.tryParse(p['amount'].toString()) ?? 0));
          final remaining = total - paid;

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Status: ${invoice['status'].toString().toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('Due: ${invoice['due_date'].toString().split('T').first}'),
                    const Divider(height: 24),
                    ...lineItems.map((li) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [Text(li['description']), Text('₹${li['amount']}')],
                          ),
                        )),
                    const Divider(height: 24),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('Total', style: TextStyle(fontWeight: FontWeight.w700)),
                      Text('₹${total.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    ]),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('Paid'), Text('₹${paid.toStringAsFixed(0)}'),
                    ]),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('Remaining', style: TextStyle(fontWeight: FontWeight.w700)),
                      Text('₹${remaining.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.red)),
                    ]),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (remaining > 0) ...[
                SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2ECC71)),
                    onPressed: () => _recordPayment(remaining),
                    icon: const Icon(Icons.payments_outlined, color: Colors.white),
                    label: const Text('Record Payment', style: TextStyle(color: Colors.white)),
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
                const Text('Payment History', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                ...payments.map((p) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.check_circle_outline, color: Color(0xFF2ECC71)),
                      title: Text('₹${p['amount']}'),
                      subtitle: Text('${p['method']} · ${p['paid_at'].toString().split('T').first}'),
                    )),
              ],
            ],
          );
        },
      ),
    );
  }
}