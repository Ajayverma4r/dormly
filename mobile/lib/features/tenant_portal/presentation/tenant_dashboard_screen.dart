// features/tenant_portal/presentation/tenant_dashboard_screen.dart
//
// Modern SaaS tenant portal: Home + Payments + Services + Community.
// Property-type UI is driven by TenantSession + QuickActionConfig factory.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../complaints/presentation/complaint_details_screen.dart';
import '../../complaints/presentation/raise_complaint_screen.dart';
import '../../notifications/presentation/notifications_providers.dart';
import '../../properties/domain/property_archetype.dart';
import '../data/tenant_portal_repository.dart';
import 'move_out_notice_screen.dart';
import 'tenant_payments_sheet.dart';
import 'tenant_portal_providers.dart';
import 'tenant_profile_menu_screen.dart';
import 'widgets/apartment_gate_pass_widget.dart';
import 'widgets/hostel_mess_menu_widget.dart';
import 'widgets/rental_meter_upload_widget.dart';
import 'widgets/tenant_quick_actions_grid.dart';

export 'tenant_payments_sheet.dart' show showTenantRentPaymentsSheet;
export 'tenant_portal_providers.dart';

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
      final session = ref.read(tenantSessionProvider).valueOrNull;
      if (session == null) {
        ref.invalidate(myTenancyProvider);
        ref.invalidate(tenantSessionProvider);
        return;
      }
      // Property-type-aware channels only (no unused module polls).
      ref.refreshTenantLiveChannels(session);
      ref.read(unreadNotificationsCountProvider.notifier).refreshQuiet();
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
    final sessionAsync = ref.watch(tenantSessionProvider);

    return sessionAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Something went wrong: $e')),
      data: (session) {
        final t = session.tenancy;
        final fullName = session.fullName;
        final firstName = fullName.trim().split(RegExp(r'\s+')).first;
        final initial =
            firstName.isNotEmpty ? firstName[0].toUpperCase() : '?';
        final roomLabel = session.headerBadge;

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(myTenancyProvider);
            ref.invalidate(tenantSessionProvider);
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
                    TenantQuickActionsGrid(
                      session: session,
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
                  final rawLines =
                      inv['lineItems'] ?? inv['line_items'] ?? const [];
                  final lineItems = rawLines is List
                      ? rawLines
                          .whereType<Map>()
                          .map((e) => Map<String, dynamic>.from(e))
                          .toList()
                      : <Map<String, dynamic>>[];

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFF1F5F9)),
                    ),
                    child: Theme(
                      data: Theme.of(context)
                          .copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 4,
                        ),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          14,
                          0,
                          14,
                          14,
                        ),
                        leading: Container(
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
                        title: Text(
                          month,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _ink,
                          ),
                        ),
                        subtitle: Text(
                          _currency.format(total),
                          style: const TextStyle(
                            color: _muted,
                            fontSize: 13,
                          ),
                        ),
                        trailing: Container(
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
                        children: [
                          if (lineItems.isEmpty)
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'No line-item breakdown available.',
                                style: TextStyle(
                                  color: _muted,
                                  fontSize: 12,
                                ),
                              ),
                            )
                          else
                            ...lineItems.map((li) {
                              final amt = double.tryParse(
                                      li['amount']?.toString() ?? '') ??
                                  0;
                              final label = (li['description'] ??
                                      li['charge_type_name'] ??
                                      'Charge')
                                  .toString();
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        label,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: _ink,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      _currency.format(amt),
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          const Divider(height: 20),
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Total',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              Text(
                                _currency.format(total),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
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
    final session = ref.watch(tenantSessionProvider).valueOrNull;
    if (session == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final t = session.tenancy;
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
          if (session.archetype == PropertyArchetype.sharedLiving) ...[
            _WifiServiceCard(ssid: ssid, password: password, tenancy: t),
            const SizedBox(height: 12),
            const HostelMessMenuWidget(),
            const SizedBox(height: 12),
          ],
          if (session.archetype == PropertyArchetype.gatedCommunity) ...[
            const ApartmentGatePassWidget(),
            const SizedBox(height: 12),
            const RentalMeterUploadWidget(title: 'Meter / Electricity'),
            const SizedBox(height: 12),
          ],
          if (session.archetype == PropertyArchetype.individualLease) ...[
            const RentalMeterUploadWidget(),
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
                    propertyId: session.propertyId,
                    nodeId: session.nodeId,
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

