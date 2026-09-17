// features/tenant_portal/presentation/tenant_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../data/tenant_portal_repository.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/login_flow.dart';
import '../../complaints/presentation/raise_complaint_screen.dart';
import '../../complaints/data/complaints_repository.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../../notifications/presentation/notifications_providers.dart';
import 'request_move_out_sheet.dart';

final myTenancyProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return ref.watch(tenantPortalRepositoryProvider).getMyTenancy();
});
final myInvoicesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return ref.watch(tenantPortalRepositoryProvider).listMyInvoices();
});

final myComplaintsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return ref.watch(complaintsRepositoryProvider).myComplaints();
});

final _hasOwnerContextProvider = FutureProvider.autoDispose<bool>((ref) async {
  final contexts = await ref.watch(authRepositoryProvider).listContexts();
  return contexts.any((c) {
    final role = c['role']?.toString();
    return role == 'owner' || role == 'admin' || role == 'manager';
  });
});

final _dtFmt = DateFormat('d MMM yyyy, h:mm a');
final _dFmt = DateFormat('d MMM yyyy');

class TenantDashboardScreen extends ConsumerStatefulWidget {
  /// Optional deep-link target, e.g. `payments` from rent reminders.
  final String? focusSection;

  const TenantDashboardScreen({super.key, this.focusSection});

  @override
  ConsumerState<TenantDashboardScreen> createState() =>
      _TenantDashboardScreenState();
}

class _TenantDashboardScreenState extends ConsumerState<TenantDashboardScreen> {
  final _scrollController = ScrollController();
  final _paymentsKey = GlobalKey();
  bool _handledFocus = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_handledFocus) return;
    final focus = widget.focusSection?.toLowerCase();
    if (focus != 'payments' && focus != 'rent') return;
    _handledFocus = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      final ctx = _paymentsKey.currentContext;
      if (ctx != null && ctx.mounted) {
        await Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          alignment: 0.1,
        );
      }
      if (!mounted || !context.mounted) return;
      await showTenantRentPaymentsSheet(context: context, ref: ref);
    });
  }

  String? _fmtDate(dynamic raw) {
    if (raw == null || raw.toString().trim().isEmpty) return null;
    final d = DateTime.tryParse(raw.toString());
    if (d == null) return null;
    return _dFmt.format(d.toLocal());
  }

  String? _fmtDateTime(dynamic raw) {
    if (raw == null || raw.toString().trim().isEmpty) return null;
    final d = DateTime.tryParse(raw.toString());
    if (d == null) return null;
    return _dtFmt.format(d.toLocal());
  }

  Future<void> _callOwner(BuildContext context, String? phone) async {
    final digits = (phone ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Owner phone not available.')),
      );
      return;
    }
    await launchUrl(Uri(scheme: 'tel', path: digits));
  }

  @override
  Widget build(BuildContext context) {
    final tenancyAsync = ref.watch(myTenancyProvider);
    final hasOwnerContext = ref.watch(_hasOwnerContextProvider).valueOrNull ?? false;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('My Home', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w800)),
        actions: [
          Builder(
            builder: (context) {
              final unreadAsync =
                  ref.watch(unreadNotificationsCountProvider);
              final unread = unreadAsync.valueOrNull ?? 0;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    tooltip: 'Notifications',
                    onPressed: () async {
                      await context.push('/notifications');
                      ref.invalidate(unreadNotificationsCountProvider);
                    },
                    icon: const Icon(Icons.notifications_outlined,
                        color: Colors.black87),
                  ),
                  if (unread > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: IgnorePointer(
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: AppColors.danger,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(
                              minWidth: 16, minHeight: 16),
                          child: Text(
                            unread > 9 ? '9+' : '$unread',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          if (hasOwnerContext)
            TextButton(
              onPressed: () => switchWorkspaceRole(context, ref, toTenant: false),
              child: const Text('Owner View'),
            ),
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
          final status = t['move_out_request_status']?.toString();
          final hasRequest = status != null &&
              status.isNotEmpty &&
              status != 'rejected';
          final requestedAt = _fmtDateTime(
            t['notice_given_at'] ?? t['noticeGivenAt'],
          );
          final proposed = _fmtDate(
            t['planned_move_out_at'] ?? t['plannedMoveOutAt'],
          );
          final isEmergency = t['move_out_is_emergency'] == true ||
              t['move_out_is_emergency']?.toString() == 'true';

          return ListView(
            controller: _scrollController,
            padding: const EdgeInsets.all(20),
            children: [
              Text('Welcome, ${t['full_name']} 👋', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              if (hasOwnerContext) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () =>
                      switchWorkspaceRole(context, ref, toTenant: false),
                  icon: const Icon(Icons.business_center_outlined),
                  label: const Text('Switch to Owner View'),
                ),
              ],
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
                  icon: const Icon(Icons.call_outlined, color: AppColors.blueprint),
                  onPressed: () =>
                      _callOwner(context, t['owner_phone']?.toString()),
                ),
              ),
              const SizedBox(height: 20),

              if (hasRequest) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isEmergency
                        ? AppColors.caution.withValues(alpha: 0.12)
                        : AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isEmergency
                          ? AppColors.caution
                          : AppColors.blueprint.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Move-Out Request',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          if (isEmergency)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.danger.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'Emergency Exit',
                                style: TextStyle(
                                  color: AppColors.danger,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Request Submitted on: ${requestedAt ?? '—'}',
                        style: const TextStyle(fontSize: 13),
                      ),
                      Text(
                        'Proposed Move-out: ${proposed ?? '—'}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (status == 'approved' ||
                          status == 'modified_by_mutual_agreement') ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFF10B981)
                                  .withValues(alpha: 0.4),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.check_circle,
                                      color: Color(0xFF10B981), size: 18),
                                  SizedBox(width: 6),
                                  Text(
                                    'Approved by Owner',
                                    style: TextStyle(
                                      color: Color(0xFF10B981),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Your move-out request for ${proposed ?? 'the proposed date'} has been confirmed by the owner.',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  height: 1.35,
                                  color: Color(0xFF065F46),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else
                        Text(
                          'Status: ${status.replaceAll('_', ' ')}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ] else if (t['status']?.toString() == 'active') ...[
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.blueprint,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () async {
                      final ok = await showRequestMoveOutSheet(
                        context: context,
                        ref: ref,
                        tenancy: t,
                      );
                      if (ok && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Move-out request submitted. Your submit time is locked in the audit log.',
                            ),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text(
                      'Request Move-Out',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () =>
                      _callOwner(context, t['owner_phone']?.toString()),
                  icon: const Icon(Icons.call_outlined),
                  label: const Text('Call Owner / Manager'),
                ),
                const SizedBox(height: 20),
              ],

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

              KeyedSubtree(
                key: _paymentsKey,
                child: const Text(
                  'Rent & Payments',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
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
                      children: [
                        ...invoices.map((inv) {
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
                      }),
                        TextButton.icon(
                          onPressed: () => showTenantRentPaymentsSheet(
                            context: context,
                            ref: ref,
                          ),
                          icon: const Icon(Icons.receipt_long_outlined, size: 18),
                          label: const Text('View dues summary'),
                        ),
                      ],
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
                                  color: statusColor.withValues(alpha: 0.15),
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
          CircleAvatar(backgroundColor: AppColors.primarySoft, child: Icon(icon, color: AppColors.blueprint)),
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
                        'Rent & Payments',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        due.isEmpty
                            ? 'You have no outstanding dues.'
                            : 'Outstanding invoices — please clear them with your owner.',
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
                              return Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFFF59E0B)
                                        .withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.payments_outlined,
                                        color: Color(0xFFD97706)),
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
                                            'Pending ₹${remaining.toStringAsFixed(0)}',
                                            style: const TextStyle(
                                              color: Color(0xFFB45309),
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
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