// features/tenant_portal/presentation/tenant_dashboard_screen.dart
//
// Modern SaaS tenant portal: Home (Screen 6) + Payments (Screen 7) tabs.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/data/auth_repository.dart';
import '../../complaints/data/complaints_repository.dart';
import '../../complaints/presentation/complaint_details_screen.dart';
import '../../complaints/presentation/raise_complaint_screen.dart';
import '../../notifications/presentation/notifications_providers.dart';
import '../data/tenant_portal_repository.dart';
import '../domain/tenant_property_profile.dart';
import 'gate_pass_screen.dart';
import 'mess_menu_screen.dart';
import 'meter_reading_screen.dart';
import 'move_out_notice_screen.dart';
import 'request_move_out_sheet.dart';
import 'tenant_profile_menu_screen.dart';

final myTenancyProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return ref.watch(tenantPortalRepositoryProvider).getMyTenancy();
});

final myInvoicesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return ref.watch(tenantPortalRepositoryProvider).listMyInvoices();
});

final myComplaintsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return ref.watch(complaintsRepositoryProvider).myComplaints();
});

final hasOwnerContextProvider = FutureProvider.autoDispose<bool>((ref) async {
  final contexts = await ref.watch(authRepositoryProvider).listContexts();
  return contexts.any((c) {
    final role = c['role']?.toString();
    return role == 'owner' || role == 'admin' || role == 'manager';
  });
});

final _currency =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _dFmt = DateFormat('d MMM yyyy');
final _dtFmt = DateFormat('d MMM yyyy, h:mm a');
final _monthFmt = DateFormat('MMM yyyy');
final _dueShort = DateFormat('d MMM yyyy');

const _bg = Color(0xFFF7F5FB);
const _brand = Color(0xFF5218D1);
const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _border = Color(0xFFE9E0FF);
const _success = Color(0xFF10B981);

class TenantDashboardScreen extends ConsumerStatefulWidget {
  /// Optional deep-link target, e.g. `payments` from rent reminders.
  final String? focusSection;

  const TenantDashboardScreen({super.key, this.focusSection});

  @override
  ConsumerState<TenantDashboardScreen> createState() =>
      _TenantDashboardScreenState();
}

class _TenantDashboardScreenState extends ConsumerState<TenantDashboardScreen> {
  int _tab = 0;
  bool _handledFocus = false;
  Timer? _livePoll;

  @override
  void initState() {
    super.initState();
    // Live sync without WebSockets: soft-refresh shared state every 20s.
    _livePoll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      ref.invalidate(myTenancyProvider);
      ref.invalidate(myComplaintsProvider);
      ref.invalidate(myInvoicesProvider);
      ref.read(unreadNotificationsCountProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _livePoll?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_handledFocus) return;
    final focus = widget.focusSection?.toLowerCase();
    if (focus == 'payments' || focus == 'rent') {
      _handledFocus = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _tab = 1);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: IndexedStack(
        index: _tab,
        children: [
          _TenantHomeTab(
            onSeeAllPayments: () => setState(() => _tab = 1),
            onOpenServices: () => setState(() => _tab = 2),
            onOpenPaymentsTab: () => setState(() => _tab = 1),
          ),
          const _TenantPaymentsTab(),
          const _TenantServicesTab(),
          const _TenantCommunityTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        height: 68,
        backgroundColor: Colors.white,
        indicatorColor: _brand.withValues(alpha: 0.12),
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded, color: _brand),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.payments_outlined),
            selectedIcon: Icon(Icons.payments_rounded, color: _brand),
            label: 'Payments',
          ),
          NavigationDestination(
            icon: Icon(Icons.handyman_outlined),
            selectedIcon: Icon(Icons.handyman_rounded, color: _brand),
            label: 'Services',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups_rounded, color: _brand),
            label: 'Community',
          ),
        ],
      ),
    );
  }
}

// ─── Home (Screen 6) ─────────────────────────────────────────────────────────

class _TenantHomeTab extends ConsumerWidget {
  final VoidCallback onSeeAllPayments;
  final VoidCallback onOpenServices;
  final VoidCallback onOpenPaymentsTab;

  const _TenantHomeTab({
    required this.onSeeAllPayments,
    required this.onOpenServices,
    required this.onOpenPaymentsTab,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenancyAsync = ref.watch(myTenancyProvider);
    final hasOwnerContext =
        ref.watch(hasOwnerContextProvider).valueOrNull ?? false;

    return tenancyAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Something went wrong: $e')),
      data: (t) {
        final fullName = t['full_name']?.toString() ?? 'there';
        final firstName = fullName.trim().split(RegExp(r'\s+')).first;
        final initial =
            firstName.isNotEmpty ? firstName[0].toUpperCase() : '?';
        final profile = TenantPropertyProfile.fromTenancy(t);
        final roomLabel = profile.headerBadge(t);

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(myTenancyProvider);
            ref.invalidate(myInvoicesProvider);
            ref.invalidate(myComplaintsProvider);
            ref.invalidate(unreadNotificationsCountProvider);
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 16, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hi $firstName 👋',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: _ink,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                roomLabel,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: _muted,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _NotificationBell(),
                        const SizedBox(width: 4),
                        _ProfileAvatar(
                          initial: initial,
                          onOpenPayments: onOpenPaymentsTab,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _CurrentMonthRentCard(tenancy: t),
                    const SizedBox(height: 22),
                    _QuickActionsRow(
                      tenancy: t,
                      profile: profile,
                      onSeeAll: onOpenServices,
                    ),
                    const SizedBox(height: 16),
                    _MoveOutStatusBanner(tenancy: t),
                    const SizedBox(height: 20),
                    _RecentComplaintsSection(tenancy: t),
                  ]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

String _roomBedLabel(Map<String, dynamic> t) {
  return TenantPropertyProfile.fromTenancy(t).headerBadge(t);
}

class _NotificationBell extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationsCountProvider).valueOrNull ?? 0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: 'Notifications',
          onPressed: () async {
            await context.push('/notifications');
            ref.invalidate(unreadNotificationsCountProvider);
          },
          icon: const Icon(Icons.notifications_outlined, color: _ink),
        ),
        if (unread > 0)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444),
                borderRadius: BorderRadius.circular(10),
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text(
                unread > 9 ? '9+' : '$unread',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  final String initial;
  final VoidCallback onOpenPayments;

  const _ProfileAvatar({
    required this.initial,
    required this.onOpenPayments,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TenantProfileMenuScreen(
              onOpenPayments: onOpenPayments,
            ),
          ),
        );
      },
      customBorder: const CircleBorder(),
      child: CircleAvatar(
        radius: 20,
        backgroundColor: const Color(0xFFEDE9FE),
        child: Text(
          initial,
          style: const TextStyle(
            color: _brand,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}

class _CurrentMonthRentCard extends ConsumerWidget {
  final Map<String, dynamic> tenancy;

  const _CurrentMonthRentCard({required this.tenancy});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoicesAsync = ref.watch(myInvoicesProvider);
    return invoicesAsync.when(
      loading: () => const SizedBox(
        height: 160,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Text('Could not load rent: $e'),
      data: (invoices) {
        final current = _pickCurrentInvoice(invoices);
        final total = current == null
            ? 0.0
            : double.tryParse(current['total_amount']?.toString() ?? '') ?? 0;
        final paid = current == null
            ? 0.0
            : double.tryParse(current['paid_amount']?.toString() ?? '') ?? 0;
        final remaining = (total - paid).clamp(0.0, 1e12);
        final isPaid = remaining <= 0.009;
        final dueRaw = current?['due_date'];
        final dueLabel = _fmtDue(dueRaw);

        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _border, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: _brand.withValues(alpha: 0.06),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3E8FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.calendar_month_outlined,
                        color: _brand, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Current Month Rent',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: _ink,
                          ),
                        ),
                        Text(
                          dueLabel == null ? 'No due date' : 'Due on $dueLabel',
                          style: const TextStyle(fontSize: 12, color: _muted),
                        ),
                      ],
                    ),
                  ),
                  _StatusChip(paid: isPaid),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      _currency.format(isPaid ? total : remaining),
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  if (!isPaid)
                    FilledButton(
                      onPressed: () => showTenantRentPaymentsSheet(
                        context: context,
                        ref: ref,
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: _brand,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bolt, size: 16),
                          SizedBox(width: 4),
                          Text(
                            'Pay via UPI >',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total Amount: ${_currency.format(total)}',
                          style: const TextStyle(fontSize: 12, color: _muted),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Paid Amount: ${_currency.format(paid)}',
                          style: const TextStyle(fontSize: 12, color: _muted),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _downloadReceipt(context, ref, current),
                    icon: const Icon(Icons.description_outlined,
                        size: 16, color: _brand),
                    label: const Text(
                      'Download Receipt',
                      style: TextStyle(
                        color: _brand,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Map<String, dynamic>? _pickCurrentInvoice(List<Map<String, dynamic>> list) {
    if (list.isEmpty) return null;
    final now = DateTime.now();
    Map<String, dynamic>? best;
    DateTime? bestDue;
    for (final inv in list) {
      final due = DateTime.tryParse(inv['due_date']?.toString() ?? '');
      if (due == null) continue;
      final sameMonth = due.year == now.year && due.month == now.month;
      if (sameMonth) return inv;
      if (bestDue == null || due.isAfter(bestDue)) {
        bestDue = due;
        best = inv;
      }
    }
    // Prefer any unpaid invoice if no current-month match.
    for (final inv in list) {
      final total = double.tryParse(inv['total_amount']?.toString() ?? '') ?? 0;
      final paid = double.tryParse(inv['paid_amount']?.toString() ?? '') ?? 0;
      if (total - paid > 0.009) return inv;
    }
    return best ?? list.first;
  }

  String? _fmtDue(dynamic raw) {
    if (raw == null || raw.toString().trim().isEmpty) return null;
    final d = DateTime.tryParse(raw.toString());
    if (d == null) return null;
    return _dueShort.format(d.toLocal());
  }

  Future<void> _downloadReceipt(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic>? invoice,
  ) async {
    final agreement = tenancy['agreement_pdf_url']?.toString();
    final invUrl = invoice?['pdf_url']?.toString() ??
        invoice?['receipt_url']?.toString();
    final path = invUrl ?? agreement;
    if (path == null || path.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No receipt available yet.')),
      );
      return;
    }
    final base = ref.read(tenantPortalRepositoryProvider).baseUrl;
    final full = path.startsWith('http') ? path : '$base$path';
    final uri = Uri.tryParse(full);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _StatusChip extends StatelessWidget {
  final bool paid;
  const _StatusChip({required this.paid});

  @override
  Widget build(BuildContext context) {
    final bg = paid ? const Color(0xFFD1FAE5) : const Color(0xFFFEE2E2);
    final fg = paid ? const Color(0xFF047857) : const Color(0xFFDC2626);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        paid ? 'PAID' : 'PENDING',
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _QuickActionsRow extends ConsumerWidget {
  final Map<String, dynamic> tenancy;
  final TenantPropertyProfile profile;
  final VoidCallback onSeeAll;

  const _QuickActionsRow({
    required this.tenancy,
    required this.profile,
    required this.onSeeAll,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = profile.quickActions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Quick Actions',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: _ink,
                ),
              ),
            ),
            TextButton(
              onPressed: onSeeAll,
              style: TextButton.styleFrom(
                foregroundColor: _brand,
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'See All >',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(
                child: _QuickActionTile(
                  label: _actionLabel(actions[i]),
                  icon: _actionIcon(actions[i]),
                  tint: _actionTint(actions[i]),
                  iconColor: _actionColor(actions[i]),
                  onTap: () => _onAction(context, ref, actions[i]),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  String _actionLabel(TenantQuickActionId id) {
    switch (id) {
      case TenantQuickActionId.raiseComplaint:
        return 'Raise\nComplaint';
      case TenantQuickActionId.wifi:
        return 'Wi-Fi\nDetails';
      case TenantQuickActionId.messMenu:
        return 'Mess\nMenu';
      case TenantQuickActionId.moveOut:
        return 'Move-Out\n/ Notice';
      case TenantQuickActionId.gatePass:
        return 'Gate Pass\n/ Delivery';
      case TenantQuickActionId.societyDues:
        return 'Society\nDues';
      case TenantQuickActionId.meterElectricity:
        return 'Meter /\nElectricity';
      case TenantQuickActionId.leaseAgreement:
        return 'Lease\nAgreement';
      case TenantQuickActionId.gstInvoices:
        return 'GST\nInvoices';
      case TenantQuickActionId.commercialEb:
        return 'Commercial\nEB';
      case TenantQuickActionId.maintenance:
        return 'Maintenance';
      case TenantQuickActionId.leaseTerms:
        return 'Lease\nTerms';
    }
  }

  IconData _actionIcon(TenantQuickActionId id) {
    switch (id) {
      case TenantQuickActionId.raiseComplaint:
        return Icons.build_outlined;
      case TenantQuickActionId.wifi:
        return Icons.wifi_rounded;
      case TenantQuickActionId.messMenu:
        return Icons.restaurant_outlined;
      case TenantQuickActionId.moveOut:
        return Icons.logout_rounded;
      case TenantQuickActionId.gatePass:
        return Icons.badge_outlined;
      case TenantQuickActionId.societyDues:
        return Icons.account_balance_outlined;
      case TenantQuickActionId.meterElectricity:
        return Icons.bolt_rounded;
      case TenantQuickActionId.leaseAgreement:
      case TenantQuickActionId.leaseTerms:
        return Icons.description_outlined;
      case TenantQuickActionId.gstInvoices:
        return Icons.receipt_long_outlined;
      case TenantQuickActionId.commercialEb:
        return Icons.electrical_services_outlined;
      case TenantQuickActionId.maintenance:
        return Icons.handyman_outlined;
    }
  }

  Color _actionTint(TenantQuickActionId id) {
    switch (id) {
      case TenantQuickActionId.raiseComplaint:
      case TenantQuickActionId.maintenance:
        return const Color(0xFFF3E8FF);
      case TenantQuickActionId.wifi:
      case TenantQuickActionId.gatePass:
        return const Color(0xFFDBEAFE);
      case TenantQuickActionId.messMenu:
      case TenantQuickActionId.societyDues:
        return const Color(0xFFD1FAE5);
      case TenantQuickActionId.moveOut:
        return const Color(0xFFFFEDD5);
      case TenantQuickActionId.meterElectricity:
      case TenantQuickActionId.commercialEb:
        return const Color(0xFFFEF3C7);
      case TenantQuickActionId.leaseAgreement:
      case TenantQuickActionId.leaseTerms:
      case TenantQuickActionId.gstInvoices:
        return const Color(0xFFE0E7FF);
    }
  }

  Color _actionColor(TenantQuickActionId id) {
    switch (id) {
      case TenantQuickActionId.raiseComplaint:
      case TenantQuickActionId.maintenance:
        return _brand;
      case TenantQuickActionId.wifi:
      case TenantQuickActionId.gatePass:
        return const Color(0xFF2563EB);
      case TenantQuickActionId.messMenu:
      case TenantQuickActionId.societyDues:
        return const Color(0xFF059669);
      case TenantQuickActionId.moveOut:
        return const Color(0xFFEA580C);
      case TenantQuickActionId.meterElectricity:
      case TenantQuickActionId.commercialEb:
        return const Color(0xFFD97706);
      case TenantQuickActionId.leaseAgreement:
      case TenantQuickActionId.leaseTerms:
      case TenantQuickActionId.gstInvoices:
        return const Color(0xFF4338CA);
    }
  }

  Future<void> _onAction(
    BuildContext context,
    WidgetRef ref,
    TenantQuickActionId id,
  ) async {
    switch (id) {
      case TenantQuickActionId.raiseComplaint:
      case TenantQuickActionId.maintenance:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RaiseComplaintScreen(
              propertyId: tenancy['property_id']?.toString() ?? '',
              nodeId: tenancy['node_id']?.toString() ?? '',
            ),
          ),
        );
        ref.invalidate(myComplaintsProvider);
        return;
      case TenantQuickActionId.wifi:
        _showWifiSheet(context, tenancy);
        return;
      case TenantQuickActionId.messMenu:
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MessMenuScreen()),
        );
        return;
      case TenantQuickActionId.moveOut:
        final status = tenancy['move_out_request_status']?.toString() ?? '';
        final already = status == 'pending' ||
            status == 'approved' ||
            status == 'modified_by_mutual_agreement';
        if (already) {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MoveOutNoticeScreen(tenancy: tenancy),
            ),
          );
          return;
        }
        final ok = await showRequestMoveOutSheet(
          context: context,
          ref: ref,
          tenancy: tenancy,
        );
        if (ok) ref.invalidate(myTenancyProvider);
        return;
      case TenantQuickActionId.gatePass:
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const GatePassScreen()),
        );
        return;
      case TenantQuickActionId.societyDues:
        await showTenantRentPaymentsSheet(context: context, ref: ref);
        return;
      case TenantQuickActionId.meterElectricity:
      case TenantQuickActionId.commercialEb:
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MeterReadingScreen()),
        );
        ref.invalidate(myInvoicesProvider);
        return;
      case TenantQuickActionId.leaseAgreement:
      case TenantQuickActionId.leaseTerms:
        final url = tenancy['agreement_pdf_url']?.toString();
        if (url == null || url.trim().isEmpty) {
          _showInfoSheet(
            context,
            title: 'Lease',
            body: 'No lease PDF is on file yet. Ask your owner to upload it.',
          );
          return;
        }
        final base = ref.read(tenantPortalRepositoryProvider).baseUrl;
        final full = url.startsWith('http') ? url : '$base$url';
        final uri = Uri.tryParse(full);
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
        return;
      case TenantQuickActionId.gstInvoices:
        await showTenantRentPaymentsSheet(context: context, ref: ref);
        return;
    }
  }
}

void _showInfoSheet(
  BuildContext context, {
  required String title,
  required String body,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(body, style: const TextStyle(color: _muted, height: 1.4)),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: FilledButton.styleFrom(backgroundColor: _brand),
                  child: const Text('Got it'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _QuickActionTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color tint;
  final Color iconColor;
  final VoidCallback onTap;

  const _QuickActionTile({
    required this.label,
    required this.icon,
    required this.tint,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: tint,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          child: Column(
            children: [
              Icon(icon, color: iconColor, size: 24),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: iconColor.withValues(alpha: 0.9),
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoveOutStatusBanner extends StatelessWidget {
  final Map<String, dynamic> tenancy;
  const _MoveOutStatusBanner({required this.tenancy});

  @override
  Widget build(BuildContext context) {
    final status = tenancy['move_out_request_status']?.toString() ?? '';
    final show = status == 'pending' ||
        status == 'approved' ||
        status == 'modified_by_mutual_agreement';
    if (!show) return const SizedBox.shrink();

    final proposed = DateTime.tryParse(
      (tenancy['planned_move_out_at'] ?? tenancy['plannedMoveOutAt'])
              ?.toString() ??
          '',
    );
    final dateLabel =
        proposed == null ? '—' : _dFmt.format(proposed.toLocal());
    final days = proposed == null
        ? null
        : proposed
            .toLocal()
            .difference(DateTime.now())
            .inDays
            .clamp(-999, 999);
    final approved = status == 'approved' ||
        status == 'modified_by_mutual_agreement';

    final title = approved ? 'Move-Out Approved' : 'Move-Out Pending';
    final subtitle = days == null
        ? 'for $dateLabel'
        : days >= 0
            ? 'for $dateLabel • $days days remaining'
            : 'for $dateLabel';

    return Material(
      color: approved
          ? const Color(0xFFD1FAE5)
          : const Color(0xFFFEF3C7),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MoveOutNoticeScreen(tenancy: tenancy),
            ),
          );
        },
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                approved ? Icons.check_circle : Icons.schedule,
                color: approved ? _success : const Color(0xFFD97706),
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: approved
                            ? const Color(0xFF065F46)
                            : const Color(0xFF92400E),
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: approved
                            ? const Color(0xFF047857)
                            : const Color(0xFFB45309),
                      ),
                    ),
                  ],
                ),
              ),
              const Text(
                'View Details >',
                style: TextStyle(
                  color: _brand,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentComplaintsSection extends ConsumerWidget {
  final Map<String, dynamic> tenancy;
  const _RecentComplaintsSection({required this.tenancy});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myComplaintsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Recent Complaints',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: _ink,
                ),
              ),
            ),
            TextButton(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => RaiseComplaintScreen(
                      propertyId: tenancy['property_id']?.toString() ?? '',
                      nodeId: tenancy['node_id']?.toString() ?? '',
                    ),
                  ),
                );
                ref.invalidate(myComplaintsProvider);
              },
              style: TextButton.styleFrom(
                foregroundColor: _brand,
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'See All >',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Could not load complaints: $e'),
          data: (list) {
            if (list.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFF1F5F9)),
                ),
                child: const Text(
                  'No complaints raised yet.',
                  style: TextStyle(color: _muted, fontSize: 13),
                ),
              );
            }
            final recent = list.take(3).toList();
            return Column(
              children: [
                for (final c in recent) ...[
                  InkWell(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              ComplaintDetailsScreen(complaint: c),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: _ComplaintTicketCard(complaint: c),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ComplaintTicketCard extends StatelessWidget {
  final Map<String, dynamic> complaint;
  const _ComplaintTicketCard({required this.complaint});

  @override
  Widget build(BuildContext context) {
    final title = complaint['category']?.toString() ??
        complaint['title']?.toString() ??
        'Complaint';
    final id = complaint['ticket_number']?.toString() ??
        complaint['id']?.toString() ??
        '';
    final shortId = id.length > 8 ? id.substring(0, 8).toUpperCase() : id;
    final created = DateTime.tryParse(
      complaint['created_at']?.toString() ?? '',
    );
    final when = created == null ? '—' : _dtFmt.format(created.toLocal());
    final status = complaint['status']?.toString() ?? 'open';
    final (label, color) = _statusStyle(status);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFF3E8FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.desktop_windows_outlined,
                color: _brand, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Ticket #$shortId',
                  style: const TextStyle(fontSize: 12, color: _muted),
                ),
                Text(
                  'Raised on $when',
                  style: const TextStyle(fontSize: 11, color: _muted),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  (String, Color) _statusStyle(String status) {
    switch (status) {
      case 'resolved':
        return ('Resolved', _success);
      case 'closed':
        return ('Closed', Colors.grey);
      case 'in_progress':
        return ('In Progress', const Color(0xFF2563EB));
      case 'assigned':
        return ('Technician Assigned', _brand);
      default:
        return ('Open', const Color(0xFFDC2626));
    }
  }
}

// ─── Payments (Screen 7) ─────────────────────────────────────────────────────

class _TenantPaymentsTab extends ConsumerWidget {
  const _TenantPaymentsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myInvoicesProvider);
    return SafeArea(
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load payments: $e')),
        data: (invoices) {
          double totalDue = 0;
          DateTime? nearestDue;
          for (final inv in invoices) {
            final total =
                double.tryParse(inv['total_amount']?.toString() ?? '') ?? 0;
            final paid =
                double.tryParse(inv['paid_amount']?.toString() ?? '') ?? 0;
            final rem = total - paid;
            if (rem > 0.009) {
              totalDue += rem;
              final d = DateTime.tryParse(inv['due_date']?.toString() ?? '');
              if (d != null &&
                  (nearestDue == null || d.isBefore(nearestDue))) {
                nearestDue = d;
              }
            }
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              const Text(
                'Payments',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _border, width: 1.2),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Total Due',
                            style: TextStyle(
                              color: _brand,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _currency.format(totalDue),
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: _brand,
                            ),
                          ),
                          if (nearestDue != null)
                            Text(
                              'Due on ${_dueShort.format(nearestDue.toLocal())}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: _muted,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (totalDue > 0.009)
                      FilledButton(
                        onPressed: () => showTenantRentPaymentsSheet(
                          context: context,
                          ref: ref,
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: _brand,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Pay Now',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'History',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 10),
              if (invoices.isEmpty)
                const Text('No payment history yet.',
                    style: TextStyle(color: _muted))
              else
                ...invoices.map((inv) {
                  final total = double.tryParse(
                          inv['total_amount']?.toString() ?? '') ??
                      0;
                  final paid = double.tryParse(
                          inv['paid_amount']?.toString() ?? '') ??
                      0;
                  final rem = total - paid;
                  final pending = rem > 0.009;
                  final due = DateTime.tryParse(
                      inv['due_date']?.toString() ?? '');
                  final month = due == null
                      ? 'Invoice'
                      : _monthFmt.format(due.toLocal());
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFF1F5F9)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: pending
                                ? const Color(0xFFF3E8FF)
                                : const Color(0xFFD1FAE5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.calendar_month_outlined,
                            color: pending ? _brand : _success,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                month,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: _ink,
                                ),
                              ),
                              Text(
                                _currency.format(total),
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: pending
                                ? const Color(0xFFFEE2E2)
                                : const Color(0xFFD1FAE5),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            pending ? 'Pending' : 'Paid',
                            style: TextStyle(
                              color: pending
                                  ? const Color(0xFFDC2626)
                                  : const Color(0xFF047857),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}

// ─── Services (Screen 10) / Community (Screen 13) ────────────────────────────

class _TenantServicesTab extends ConsumerWidget {
  const _TenantServicesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(myTenancyProvider).valueOrNull ?? {};
    final profile = TenantPropertyProfile.fromTenancy(t);
    final node = t['node_name']?.toString() ?? 'Room';
    final ssid = 'Dormly_${node.replaceAll(RegExp(r'\s+'), '')}';
    const password = '••••••••';

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          const Text(
            'Services',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          const SizedBox(height: 16),
          if (profile.showsWifi) ...[
            _WifiServiceCard(ssid: ssid, password: password, tenancy: t),
            const SizedBox(height: 12),
          ],
          if (profile.showsMessMenu) ...[
            _ServiceLinkCard(
              icon: Icons.restaurant_outlined,
              iconColor: const Color(0xFF059669),
              tint: const Color(0xFFD1FAE5),
              title: 'Mess Menu',
              subtitle: "Check today's meals and weekly menu.",
              action: 'View Menu →',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MessMenuScreen()),
                );
              },
            ),
            const SizedBox(height: 12),
          ],
          if (profile.showsGatePass) ...[
            _ServiceLinkCard(
              icon: Icons.badge_outlined,
              iconColor: const Color(0xFF2563EB),
              tint: const Color(0xFFDBEAFE),
              title: 'Gate Passes & Visitor Log',
              subtitle: 'Approve deliveries and guest entries for your flat.',
              action: 'Open →',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const GatePassScreen()),
                );
              },
            ),
            const SizedBox(height: 12),
          ],
          if (profile.kind == TenantPropertyKind.rentalHouse ||
              profile.kind == TenantPropertyKind.apartment ||
              profile.kind == TenantPropertyKind.commercial) ...[
            _ServiceLinkCard(
              icon: Icons.bolt_rounded,
              iconColor: const Color(0xFFD97706),
              tint: const Color(0xFFFEF3C7),
              title: profile.kind == TenantPropertyKind.commercial
                  ? 'Commercial EB'
                  : 'Meter / Electricity',
              subtitle:
                  'Submit a reading — dues update on the shared billing ledger.',
              action: 'Open →',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const MeterReadingScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
          ],
          if (profile.kind == TenantPropertyKind.commercial) ...[
            _ServiceLinkCard(
              icon: Icons.receipt_long_outlined,
              iconColor: const Color(0xFF4338CA),
              tint: const Color(0xFFE0E7FF),
              title: 'GST Invoices',
              subtitle: 'View commercial invoices and tax documents.',
              action: 'View →',
              onTap: () =>
                  showTenantRentPaymentsSheet(context: context, ref: ref),
            ),
            const SizedBox(height: 12),
          ],
          _ServiceLinkCard(
            icon: Icons.cleaning_services_outlined,
            iconColor: _brand,
            tint: const Color(0xFFF3E8FF),
            title: 'Housekeeping',
            subtitle: 'Request room cleaning or additional services.',
            action: 'Request →',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Housekeeping request sent to your owner.'),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _ServiceLinkCard(
            icon: Icons.settings_outlined,
            iconColor: _brand,
            tint: const Color(0xFFF3E8FF),
            title: 'Maintenance',
            subtitle: 'View ongoing maintenance in your building.',
            action: 'View Status →',
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => RaiseComplaintScreen(
                    propertyId: t['property_id']?.toString() ?? '',
                    nodeId: t['node_id']?.toString() ?? '',
                  ),
                ),
              );
              ref.invalidate(myComplaintsProvider);
            },
          ),
        ],
      ),
    );
  }
}

class _WifiServiceCard extends StatelessWidget {
  final String ssid;
  final String password;
  final Map<String, dynamic> tenancy;

  const _WifiServiceCard({
    required this.ssid,
    required this.password,
    required this.tenancy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFF3E8FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.wifi_rounded, color: _brand),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Wi-Fi Details',
                  style: TextStyle(fontWeight: FontWeight.w800, color: _ink),
                ),
                Text('Network: $ssid',
                    style: const TextStyle(fontSize: 12.5, color: _muted)),
                Text('Password: $password',
                    style: const TextStyle(fontSize: 12.5, color: _muted)),
              ],
            ),
          ),
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: ssid));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Network name copied')),
                );
              }
            },
            style: TextButton.styleFrom(foregroundColor: _brand),
            child: const Text(
              'Copy',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceLinkCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color tint;
  final String title;
  final String subtitle;
  final String action;
  final VoidCallback onTap;

  const _ServiceLinkCard({
    required this.icon,
    required this.iconColor,
    required this.tint,
    required this.title,
    required this.subtitle,
    required this.action,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor),
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
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 12.5, color: _muted),
                    ),
                  ],
                ),
              ),
              Text(
                action,
                style: const TextStyle(
                  color: _brand,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TenantCommunityTab extends StatefulWidget {
  const _TenantCommunityTab();

  @override
  State<_TenantCommunityTab> createState() => _TenantCommunityTabState();
}

class _TenantCommunityTabState extends State<_TenantCommunityTab> {
  int _segment = 0; // 0 announcements, 1 events

  static const _announcements = [
    (
      Icons.notifications_active_outlined,
      Color(0xFF6D28D9),
      'Maintenance Notice',
      'Water supply will be interrupted on 12 Aug 2026 from 10 AM – 2 PM for tank cleaning.',
      '12 Aug 2026',
    ),
    (
      Icons.wifi_tethering_rounded,
      Color(0xFF059669),
      'New Wi-Fi Router Installed',
      'Building internet hardware was upgraded. Expect faster speeds on all floors.',
      '08 Aug 2026',
    ),
  ];

  static const _events = [
    (
      Icons.celebration_outlined,
      Color(0xFFEA580C),
      'Festive Dinner',
      'Join us for a community dinner this Friday at 8 PM in the common hall.',
      '10 Aug 2026',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final feed = _segment == 0 ? _announcements : _events;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6D28D9), Color(0xFF5B21B6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.groups_rounded, color: Colors.white, size: 36),
                SizedBox(height: 12),
                Text(
                  'Good People, Better Living',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Connect, share and be part of the Dormly community.',
                  style: TextStyle(color: Color(0xFFE9D5FF), height: 1.35),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _SegChip(
                label: 'Announcements',
                active: _segment == 0,
                onTap: () => setState(() => _segment = 0),
              ),
              const SizedBox(width: 10),
              _SegChip(
                label: 'Events',
                active: _segment == 1,
                onTap: () => setState(() => _segment = 1),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...feed.map(
            (e) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: e.$2.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(e.$1, color: e.$2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.$3,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: _ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          e.$4,
                          style: const TextStyle(
                            fontSize: 13,
                            color: _muted,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          e.$5,
                          style: const TextStyle(
                            fontSize: 11,
                            color: _muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SegChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _SegChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? _brand : Colors.transparent,
              width: 2.5,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: active ? _brand : _muted,
          ),
        ),
      ),
    );
  }
}

// ─── Shared sheets / helpers ─────────────────────────────────────────────────

void _showWifiSheet(BuildContext context, Map<String, dynamic> tenancy) {
  final property = tenancy['property_name']?.toString() ?? 'Property';
  final ssid = '$property-Guest';
  const password = 'Ask your owner';

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
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
              const SizedBox(height: 16),
              const Text(
                'Wi-Fi Details',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              _CopyRow(label: 'SSID', value: ssid),
              const SizedBox(height: 10),
              _CopyRow(label: 'Password', value: password),
              const SizedBox(height: 8),
              const Text(
                'Confirm the password with your owner if this does not work.',
                style: TextStyle(fontSize: 12, color: _muted),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _CopyRow extends StatelessWidget {
  final String label;
  final String value;
  const _CopyRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(fontSize: 11, color: _muted)),
                Text(value,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: value));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$label copied')),
                );
              }
            },
            icon: const Icon(Icons.copy_rounded, size: 18, color: _brand),
          ),
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
                              return Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF3E8FF),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
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
