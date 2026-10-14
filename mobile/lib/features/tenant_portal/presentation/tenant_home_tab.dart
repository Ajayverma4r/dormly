// features/tenant_portal/presentation/tenant_home_tab.dart
//
// Tenant Home: stay, dues, quick actions, recent activity and help. Every
// figure comes from the tenant's own scoped APIs; nothing is estimated.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../billing/presentation/billing_invoice_helpers.dart'
    show
        billingCurrency,
        invoiceCalendarDate,
        invoicePaidAmount,
        invoiceRemaining,
        invoiceTotalAmount,
        periodLabel;
import '../../complaints/presentation/complaint_details_screen.dart';
import '../../complaints/presentation/raise_complaint_screen.dart';
import '../../notifications/presentation/notifications_providers.dart';
import '../../properties/domain/property_archetype.dart';
import '../data/tenant_portal_repository.dart';
import '../domain/tenant_home_summary.dart';
import '../domain/tenant_session.dart';
import 'meter_reading_screen.dart';
import 'move_out_notice_screen.dart';
import 'tenant_portal_providers.dart';
import 'tenant_profile_menu_screen.dart';
import 'widgets/tenant_load_error.dart';

const _brand = Color(0xFF5218D1);
const _brandTint = Color(0xFFF3EEFF);
const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _border = Color(0xFFE5E7EB);
const _surface = Color(0xFFF8FAFC);

final _dateFmt = DateFormat('d MMM yyyy');
final _shortDateFmt = DateFormat('d MMM');

class TenantHomeTab extends ConsumerWidget {
  final VoidCallback onOpenPayments;
  final VoidCallback onOpenServices;

  const TenantHomeTab({
    super.key,
    required this.onOpenPayments,
    required this.onOpenServices,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(tenantSessionProvider);
    return ColoredBox(
      color: Colors.white,
      child: sessionAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(key: Key('tenant-home-loading')),
        ),
        error: (e, _) => SafeArea(
          child: TenantLoadError(
            title: "We couldn't load your dashboard",
            error: e,
            onRetry: () {
              ref.invalidate(myTenancyProvider);
              ref.invalidate(tenantSessionProvider);
            },
          ),
        ),
        data: (session) => _HomeContent(
          session: session,
          onOpenPayments: onOpenPayments,
          onOpenServices: onOpenServices,
        ),
      ),
    );
  }
}

class _HomeContent extends ConsumerWidget {
  final TenantSession session;
  final VoidCallback onOpenPayments;
  final VoidCallback onOpenServices;

  const _HomeContent({
    required this.session,
    required this.onOpenPayments,
    required this.onOpenServices,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firstName =
        session.fullName.trim().split(RegExp(r'\s+')).first;

    return RefreshIndicator(
      color: _brand,
      onRefresh: () async {
        ref.invalidate(myTenancyProvider);
        ref.invalidate(tenantSessionProvider);
        ref.invalidate(myInvoicesProvider);
        ref.invalidate(myComplaintsProvider);
        ref.invalidate(tenantMeterReadingsProvider);
        ref.invalidate(unreadNotificationsCountProvider);
      },
      child: SafeArea(
        bottom: false,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _TopBar(session: session, onOpenPayments: onOpenPayments),
            const SizedBox(height: 12),
            Text(
              '${_greeting(DateTime.now())}, $firstName',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: _ink,
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              "Here's an overview of your stay.",
              style: TextStyle(fontSize: 13, color: _muted),
            ),
            const SizedBox(height: 16),
            _MyStayCard(session: session, onOpenPayments: onOpenPayments),
            const SizedBox(height: 12),
            _RentDuesCard(
              session: session,
              onOpenPayments: onOpenPayments,
            ),
            _MoveOutStatusBanner(tenancy: session.tenancy),
            const SizedBox(height: 20),
            _QuickActions(
              session: session,
              onOpenPayments: onOpenPayments,
              onOpenServices: onOpenServices,
            ),
            const SizedBox(height: 20),
            _RecentActivity(session: session, onOpenPayments: onOpenPayments),
            const SizedBox(height: 20),
            _HelpCard(session: session),
          ],
        ),
      ),
    );
  }
}

String _greeting(DateTime now) {
  if (now.hour < 12) return 'Good morning';
  if (now.hour < 17) return 'Good afternoon';
  return 'Good evening';
}

BoxDecoration _cardDecoration() => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _border),
    );

class _SectionTitle extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;

  const _SectionTitle(this.title, {this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: _ink,
            ),
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: _brand,
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              action!,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
      ],
    );
  }
}

// ─── Top bar ────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final TenantSession session;
  final VoidCallback onOpenPayments;

  const _TopBar({required this.session, required this.onOpenPayments});

  @override
  Widget build(BuildContext context) {
    final name = session.fullName.trim();
    final initial = name.isEmpty ? '?' : name[0].toUpperCase();
    return Row(
      children: [
        Image.asset(
          'assets/images/logo.png',
          height: 30,
          errorBuilder: (_, __, ___) => const Text(
            'Dormly',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: _brand,
            ),
          ),
        ),
        const Spacer(),
        const _NotificationBell(),
        const SizedBox(width: 4),
        InkWell(
          customBorder: const CircleBorder(),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  TenantProfileMenuScreen(onOpenPayments: onOpenPayments),
            ),
          ),
          child: CircleAvatar(
            radius: 18,
            backgroundColor: _brandTint,
            child: Text(
              initial,
              style: const TextStyle(
                color: _brand,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NotificationBell extends ConsumerWidget {
  const _NotificationBell();

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
          icon: const Icon(Icons.notifications_none_rounded, color: _ink),
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

// ─── My Stay ────────────────────────────────────────────────────────────────

class _MyStayCard extends StatelessWidget {
  final TenantSession session;
  final VoidCallback onOpenPayments;

  const _MyStayCard({required this.session, required this.onOpenPayments});

  @override
  Widget build(BuildContext context) {
    final t = session.tenancy;
    final property = t['property_name']?.toString().trim();
    final city = t['property_city']?.toString().trim();
    final moveIn = invoiceCalendarDate(t['move_in_at']);
    final status = t['status']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _brandTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.apartment_rounded,
                    color: _brand, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      property == null || property.isEmpty
                          ? 'My stay'
                          : property,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      session.headerBadge,
                      style: const TextStyle(fontSize: 12.5, color: _muted),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TenantProfileMenuScreen(
                      onOpenPayments: onOpenPayments,
                    ),
                  ),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: _brand,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'View details',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: _border),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _InfoCell(
                  label: 'Move-in',
                  value: moveIn == null ? '—' : _dateFmt.format(moveIn),
                ),
              ),
              Expanded(
                child: _InfoCell(
                  label: 'Location',
                  value: city == null || city.isEmpty ? '—' : city,
                ),
              ),
              Expanded(
                child: _InfoCell(
                  label: 'Tenancy',
                  value: _tenancyStatusLabel(status),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _tenancyStatusLabel(String status) {
    switch (status) {
      case 'active':
        return 'Active';
      case '':
        return '—';
      default:
        final s = status.replaceAll('_', ' ');
        return '${s[0].toUpperCase()}${s.substring(1)}';
    }
  }
}

class _InfoCell extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoCell({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: _muted)),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: valueColor ?? _ink,
          ),
        ),
      ],
    );
  }
}

// ─── Rent & Dues ────────────────────────────────────────────────────────────

class _RentDuesCard extends ConsumerWidget {
  final TenantSession session;
  final VoidCallback onOpenPayments;

  const _RentDuesCard({required this.session, required this.onOpenPayments});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoicesAsync = ref.watch(myInvoicesProvider);
    return invoicesAsync.when(
      loading: () => Container(
        key: const Key('rent-dues-loading'),
        height: 170,
        decoration: _cardDecoration(),
        alignment: Alignment.center,
        child: const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (e, _) => TenantLoadError(
        title: "Couldn't load your dues",
        error: e,
        compact: true,
        onRetry: () => ref.invalidate(myInvoicesProvider),
      ),
      data: (invoices) => _buildCard(
        context,
        TenantDuesSummary.fromInvoices(invoices),
      ),
    );
  }

  Widget _buildCard(BuildContext context, TenantDuesSummary s) {
    final (pillLabel, pillColor) = switch (s.status) {
      TenantDuesStatus.overdue => ('Overdue', const Color(0xFFDC2626)),
      TenantDuesStatus.partiallyPaid =>
        ('Partially paid', const Color(0xFFD97706)),
      TenantDuesStatus.upcoming => ('Upcoming', _brand),
      TenantDuesStatus.paid => ('Paid', const Color(0xFF059669)),
      TenantDuesStatus.noBills => ('No bills', _muted),
    };

    final next = s.nextInvoice;
    final String caption;
    switch (s.status) {
      case TenantDuesStatus.overdue:
        caption = '${billingCurrency.format(s.overdueAmount)} overdue on '
            '${s.overdueCount} ${s.overdueCount == 1 ? 'bill' : 'bills'}';
      case TenantDuesStatus.partiallyPaid:
        caption = '${billingCurrency.format(invoicePaidAmount(next!))} paid of '
            '${billingCurrency.format(invoiceTotalAmount(next))} · '
            '${billingCurrency.format(invoiceRemaining(next))} left';
      case TenantDuesStatus.upcoming:
        caption = s.nextDueDate == null
            ? 'Outstanding balance'
            : 'Due ${_dateFmt.format(s.nextDueDate!)}';
      case TenantDuesStatus.paid:
        caption = "You're all paid up";
      case TenantDuesStatus.noBills:
        caption = 'No bills have been sent to you yet';
    }

    final lastPaid = s.lastPaidInvoice;
    final agreement =
        session.tenancy['agreement_pdf_url']?.toString().trim() ?? '';

    return Container(
      key: const Key('rent-dues-card'),
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Rent & Dues',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: _ink,
                  ),
                ),
              ),
              _Pill(label: pillLabel, color: pillColor),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            billingCurrency.format(s.outstanding),
            key: const Key('rent-dues-outstanding'),
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: _ink,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            caption,
            style: TextStyle(
              fontSize: 12.5,
              color: s.status == TenantDuesStatus.overdue
                  ? const Color(0xFFDC2626)
                  : _muted,
              fontWeight: s.status == TenantDuesStatus.overdue
                  ? FontWeight.w700
                  : FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onOpenPayments,
              style: FilledButton.styleFrom(
                backgroundColor: _brand,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'View payment details',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _InfoCell(
                    label: 'Next due',
                    value: s.nextDueDate == null
                        ? '—'
                        : _shortDateFmt.format(s.nextDueDate!),
                  ),
                ),
                Expanded(
                  child: _InfoCell(
                    label: 'Last payment',
                    value: lastPaid == null
                        ? 'None yet'
                        : '${billingCurrency.format(invoicePaidAmount(lastPaid))}'
                            ' · ${periodLabel(lastPaid)}',
                  ),
                ),
                Expanded(
                  child: _InfoCell(
                    label: 'Agreement',
                    value: agreement.isEmpty ? 'Not uploaded' : 'On file',
                    valueColor:
                        agreement.isEmpty ? _muted : const Color(0xFF059669),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;

  const _Pill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
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
    final approved =
        status == 'approved' || status == 'modified_by_mutual_agreement';
    if (status != 'pending' && !approved) return const SizedBox.shrink();

    final proposed = invoiceCalendarDate(
      tenancy['planned_move_out_at'] ?? tenancy['plannedMoveOutAt'],
    );
    final fg = approved ? const Color(0xFF065F46) : const Color(0xFF92400E);

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: approved ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MoveOutNoticeScreen(tenancy: tenancy),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  approved ? Icons.check_circle_rounded : Icons.schedule,
                  color: fg,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${approved ? 'Move-out approved' : 'Move-out pending'}'
                    '${proposed == null ? '' : ' for ${_dateFmt.format(proposed)}'}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: fg,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: fg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Quick actions ──────────────────────────────────────────────────────────

class _QuickActions extends ConsumerWidget {
  final TenantSession session;
  final VoidCallback onOpenPayments;
  final VoidCallback onOpenServices;

  const _QuickActions({
    required this.session,
    required this.onOpenPayments,
    required this.onOpenServices,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tiles = <Widget>[
      _ActionTile(
        icon: Icons.account_balance_wallet_outlined,
        label: 'Payments',
        onTap: onOpenPayments,
      ),
      _ActionTile(
        icon: Icons.description_outlined,
        label: 'Rental Agreement',
        onTap: () => _openAgreement(context, ref),
      ),
      if (session.archetype.showsMeterUpload)
        _ActionTile(
          icon: Icons.bolt_rounded,
          label: 'Meter Reading',
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MeterReadingScreen()),
            );
            ref.invalidate(tenantMeterReadingsProvider);
            ref.invalidate(myInvoicesProvider);
          },
        ),
      _ActionTile(
        icon: Icons.build_outlined,
        label: 'Raise Request',
        onTap: () => _raiseRequest(context, ref, session),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          'Quick actions',
          action: 'More services',
          onAction: onOpenServices,
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: tiles[i]),
            ],
          ],
        ),
      ],
    );
  }

  Future<void> _openAgreement(BuildContext context, WidgetRef ref) async {
    final path = session.tenancy['agreement_pdf_url']?.toString().trim() ?? '';
    if (path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Your rental agreement hasn't been uploaded yet. "
            'Please ask your property owner.',
          ),
        ),
      );
      return;
    }
    final base = ref.read(tenantPortalRepositoryProvider).baseUrl;
    final uri = Uri.tryParse(path.startsWith('http') ? path : '$base$path');
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

Future<void> _raiseRequest(
  BuildContext context,
  WidgetRef ref,
  TenantSession session,
) async {
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => RaiseComplaintScreen(
        propertyId: session.propertyId,
        nodeId: session.nodeId,
      ),
    ),
  );
  ref.invalidate(myComplaintsProvider);
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border),
          ),
          child: Column(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _brandTint,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: _brand, size: 20),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _ink,
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

// ─── Recent activity ────────────────────────────────────────────────────────

class _RecentActivity extends ConsumerWidget {
  final TenantSession session;
  final VoidCallback onOpenPayments;

  const _RecentActivity({required this.session, required this.onOpenPayments});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoices = ref.watch(myInvoicesProvider);
    final requests = ref.watch(myComplaintsProvider);
    final meters = ref.watch(tenantMeterReadingsProvider);

    final Widget body;
    final failed = [invoices, requests, meters]
        .where((a) => a.hasError && !a.hasValue)
        .toList();
    if (failed.isNotEmpty) {
      body = TenantLoadError(
        title: "Couldn't load recent activity",
        error: failed.first.error!,
        compact: true,
        onRetry: () {
          ref.invalidate(myInvoicesProvider);
          ref.invalidate(myComplaintsProvider);
          ref.invalidate(tenantMeterReadingsProvider);
        },
      );
    } else if (!invoices.hasValue || !requests.hasValue || !meters.hasValue) {
      body = Container(
        key: const Key('activity-loading'),
        height: 72,
        decoration: _cardDecoration(),
        alignment: Alignment.center,
        child: const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    } else {
      final items = buildTenantActivity(
        invoices: invoices.value!,
        requests: requests.value!,
        meterReadings: meters.value!,
      );
      body = items.isEmpty
          ? Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: _cardDecoration(),
              child: const Text(
                'No activity yet. Payments, meter readings and requests '
                'will show up here.',
                style: TextStyle(color: _muted, fontSize: 12.5),
              ),
            )
          : Container(
              decoration: _cardDecoration(),
              child: Column(
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0)
                      const Divider(height: 1, indent: 60, color: _border),
                    _ActivityRow(
                      item: items[i],
                      onOpenPayments: onOpenPayments,
                    ),
                  ],
                ],
              ),
            );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Recent activity'),
        const SizedBox(height: 10),
        body,
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final TenantActivity item;
  final VoidCallback onOpenPayments;

  const _ActivityRow({required this.item, required this.onOpenPayments});

  @override
  Widget build(BuildContext context) {
    final src = item.source;
    final IconData icon;
    final Color color;
    final String title;
    final String subtitle;
    final VoidCallback onTap;

    switch (item.kind) {
      case TenantActivityKind.payment:
        final remaining = invoiceRemaining(src);
        icon = Icons.payments_outlined;
        color = const Color(0xFF059669);
        title = 'Paid ${billingCurrency.format(invoicePaidAmount(src))} · '
            '${periodLabel(src)} bill';
        subtitle = remaining > 0.009
            ? '${billingCurrency.format(remaining)} still due'
            : 'Paid in full';
        onTap = onOpenPayments;
      case TenantActivityKind.meterReading:
        final value = src['meter_reading_value'] ?? src['reading_value'];
        final cycle = src['billing_cycle']?.toString().trim() ?? '';
        icon = Icons.bolt_rounded;
        color = const Color(0xFFD97706);
        title = 'Meter reading submitted';
        subtitle = [
          if (value != null) '$value units',
          if (cycle.isNotEmpty) cycle,
        ].join(' · ');
        onTap = () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MeterReadingScreen()),
            );
      case TenantActivityKind.request:
        icon = Icons.build_outlined;
        color = _brand;
        title = (src['title'] ?? src['category'] ?? 'Service request')
            .toString();
        subtitle = _requestStatusLabel(src['status']?.toString() ?? 'open');
        onTap = () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ComplaintDetailsScreen(complaint: src),
              ),
            );
    }

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: _ink,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 11.5, color: _muted),
                    ),
                ],
              ),
            ),
            if (item.hasExactDate)
              Text(
                _shortDateFmt.format(item.sortDate),
                style: const TextStyle(fontSize: 11.5, color: _muted),
              ),
          ],
        ),
      ),
    );
  }

  String _requestStatusLabel(String status) {
    switch (status) {
      case 'resolved':
        return 'Resolved';
      case 'closed':
        return 'Closed';
      case 'in_progress':
        return 'In progress';
      case 'assigned':
        return 'Assigned';
      default:
        return 'Open';
    }
  }
}

// ─── Help ───────────────────────────────────────────────────────────────────

class _HelpCard extends ConsumerWidget {
  final TenantSession session;

  const _HelpCard({required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phone = session.tenancy['owner_phone']?.toString().trim() ?? '';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _brandTint,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.support_agent_rounded, color: _brand, size: 26),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Need help?',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: _ink,
                  ),
                ),
                Text(
                  'Contact your property owner or raise a request.',
                  style: TextStyle(fontSize: 12, color: _muted),
                ),
              ],
            ),
          ),
          if (phone.isNotEmpty)
            IconButton(
              tooltip: 'Call owner',
              onPressed: () =>
                  launchUrl(Uri(scheme: 'tel', path: phone)),
              icon: const Icon(Icons.call_rounded, color: _brand),
            ),
          IconButton(
            tooltip: 'Raise request',
            onPressed: () => _raiseRequest(context, ref, session),
            icon: const Icon(Icons.chat_bubble_outline_rounded,
                color: _brand),
          ),
        ],
      ),
    );
  }
}
