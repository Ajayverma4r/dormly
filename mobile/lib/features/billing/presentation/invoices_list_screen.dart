// features/billing/presentation/invoices_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/billing_repository.dart';
import 'create_invoice_screen.dart';
import 'invoice_detail_screen.dart';

final invoicesProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, propertyId) => ref.watch(billingRepositoryProvider).listInvoices(propertyId),
);

class InvoicesListScreen extends ConsumerWidget {
  final String propertyId;
  const InvoicesListScreen({super.key, required this.propertyId});

  Color _statusColor(String status) {
    switch (status) {
      case 'paid': return const Color(0xFF2ECC71);
      case 'partial': return const Color(0xFFF5A623);
      case 'overdue': return const Color(0xFFE74C3C);
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoicesAsync = ref.watch(invoicesProvider(propertyId));

    return Scaffold(
      appBar: AppBar(title: const Text('Rent & Billing')),
      body: invoicesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Something went wrong: $err')),
        data: (invoices) {
          if (invoices.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.receipt_long_outlined, size: 56, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text('No invoices yet', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 8),
                    Text('Create your first rent invoice for a tenant.', style: TextStyle(color: Colors.grey.shade600)),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: invoices.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final inv = invoices[index];
              final total = double.tryParse(inv['total_amount'].toString()) ?? 0;
              final paid = double.tryParse(inv['paid_amount'].toString()) ?? 0;
              final status = inv['status'] as String;

              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: Theme.of(context).dividerColor),
                ),
                child: ListTile(
                  title: Text(inv['full_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${inv['node_name']} · Due ${inv['due_date'].toString().split('T').first}'),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('₹${total.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _statusColor(status).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(status.toUpperCase(),
                            style: TextStyle(color: _statusColor(status), fontSize: 10, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => InvoiceDetailScreen(propertyId: propertyId, invoiceId: inv['id']),
                      ),
                    );
                    ref.invalidate(invoicesProvider(propertyId));
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (context) => CreateInvoiceScreen(propertyId: propertyId)),
          );
          if (created == true) ref.invalidate(invoicesProvider(propertyId));
        },
        icon: const Icon(Icons.add),
        label: const Text('New Invoice'),
      ),
    );
  }
}