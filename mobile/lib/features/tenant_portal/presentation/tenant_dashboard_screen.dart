// features/tenant_portal/presentation/tenant_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/tenant_portal_repository.dart';
import '../../auth/data/auth_repository.dart';
import '../../complaints/presentation/raise_complaint_screen.dart';
import '../../complaints/data/complaints_repository.dart';
import 'package:url_launcher/url_launcher.dart';

final myTenancyProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return ref.watch(tenantPortalRepositoryProvider).getMyTenancy();
});
final myInvoicesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return ref.watch(tenantPortalRepositoryProvider).listMyInvoices();
});

final myComplaintsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return ref.watch(complaintsRepositoryProvider).myComplaints();
});

class TenantDashboardScreen extends ConsumerWidget {
  const TenantDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenancyAsync = ref.watch(myTenancyProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('My Home', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.black54),
            tooltip: 'Logout',
            onPressed: () async {
              await ref.read(authRepositoryProvider).logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: tenancyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Something went wrong: $err')),
        data: (t) {
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('Welcome, ${t['full_name']} 👋', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 20),

              _sectionCard(
                icon: Icons.apartment,
                title: t['property_name'] ?? '',
                subtitle: '${t['node_name'] ?? ''} · ${t['property_city'] ?? ''}',
              ),
              const SizedBox(height: 12),

              _sectionCard(
                icon: Icons.person_outline,
                title: 'Owner: ${t['owner_name'] ?? 'N/A'}',
                subtitle: t['owner_phone'] ?? '',
                trailing: IconButton(
                  icon: const Icon(Icons.call_outlined, color: Color(0xFF2B5CFF)),
                  onPressed: () {}, // TODO: launch dialer with owner_phone
                ),
              ),
              const SizedBox(height: 20),

              const Text('Tenancy Details', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (t['move_in_at'] != null)
                      _row('Move-in Date', t['move_in_at'].toString().split('T').first),
                    if (t['security_deposit'] != null)
                      _row('Security Deposit', '₹${t['security_deposit']}'),
                    if (t['notes'] != null && t['notes'].toString().isNotEmpty)
                      _row('Notes', t['notes']),
                    if (t['move_in_at'] == null && t['security_deposit'] == null)
                      Text('No additional details on file yet.', style: TextStyle(color: Colors.grey.shade600)),
                    if (t['agreement_pdf_url'] != null) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final baseUrl = ref.read(tenantPortalRepositoryProvider).baseUrl;
                          final uri = Uri.parse('$baseUrl${t['agreement_pdf_url']}');
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        },
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('View Agreement'),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),

              const Text('Rent & Payments', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 10),
              Consumer(builder: (context, ref, _) {
                final invoicesAsync = ref.watch(myInvoicesProvider);
                return invoicesAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (err, _) => Text('Could not load invoices: $err'),
                  data: (invoices) {
                    if (invoices.isEmpty) {
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                        child: Text('No invoices yet.', style: TextStyle(color: Colors.grey.shade600)),
                      );
                    }
                    return Column(
                      children: invoices.map((inv) {
                        final total = double.tryParse(inv['total_amount'].toString()) ?? 0;
                        final paid = double.tryParse(inv['paid_amount'].toString()) ?? 0;
                        final remaining = total - paid;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                Text('Due ${inv['due_date'].toString().split('T').first}', style: const TextStyle(fontWeight: FontWeight.w700)),
                                Text(inv['status'].toString().toUpperCase(),
                                    style: TextStyle(color: remaining > 0 ? Colors.red : const Color(0xFF2ECC71), fontWeight: FontWeight.w700)),
                              ]),
                              const SizedBox(height: 8),
                              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                const Text('Total'), Text('₹${total.toStringAsFixed(0)}'),
                              ]),
                              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                const Text('Pending', style: TextStyle(fontWeight: FontWeight.w700)),
                                Text('₹${remaining.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                              ]),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  },
                );
              }),

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (context) => RaiseComplaintScreen(
                        propertyId: t['property_id'],
                        nodeId: t['node_id'],
                      ),
                    ));
                    ref.invalidate(myComplaintsProvider);
                  },
                  icon: const Icon(Icons.build_outlined),
                  label: const Text('Raise a Complaint'),
                ),
              ),
              const SizedBox(height: 20),
              const Text('My Complaints', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 10),
              Consumer(builder: (context, ref, _) {
                final complaintsAsync = ref.watch(myComplaintsProvider);
                return complaintsAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (err, _) => Text('Could not load complaints: $err'),
                  data: (complaints) {
                    if (complaints.isEmpty) {
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                        child: Text('No complaints raised yet.', style: TextStyle(color: Colors.grey.shade600)),
                      );
                    }
                    return Column(
                      children: complaints.map((c) {
                        Color statusColor;
                        switch (c['status']) {
                          case 'resolved': statusColor = const Color(0xFF2ECC71); break;
                          case 'closed': statusColor = Colors.grey; break;
                          case 'in_progress': statusColor = const Color(0xFFF5A623); break;
                          default: statusColor = const Color(0xFFE74C3C); // open
                        }
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(c['category'], style: const TextStyle(fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 2),
                                    Text(c['description'], maxLines: 2, overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                                    if (c['resolution_note'] != null && c['resolution_note'].toString().isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text('Note: ${c['resolution_note']}',
                                          style: TextStyle(color: Colors.grey.shade700, fontSize: 12, fontStyle: FontStyle.italic)),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  c['status'].toString().replaceAll('_', ' ').toUpperCase(),
                                  style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  },
                );
              }),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionCard({required IconData icon, required String title, required String subtitle, Widget? trailing}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          CircleAvatar(backgroundColor: const Color(0xFFEFF2FF), child: Icon(icon, color: const Color(0xFF2B5CFF))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 130, child: Text(label, style: TextStyle(color: Colors.grey.shade600))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}