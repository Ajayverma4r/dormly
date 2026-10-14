// features/tenant_portal/presentation/tenant_dashboard_screen.dart
//
// Modern SaaS tenant portal: Home + Payments + Services + Community.
// Property-type UI is driven by TenantSession; Home lives in tenant_home_tab.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../billing/presentation/billing_invoice_helpers.dart'
    show invoiceDueDate, isOpenUnpaidInvoice, outstandingTotal;
import '../../complaints/presentation/raise_complaint_screen.dart';
import '../../notifications/presentation/notifications_providers.dart';
import '../../properties/domain/property_archetype.dart';
import 'tenant_home_tab.dart';
import 'tenant_payment_history_screen.dart';
import 'tenant_payments_sheet.dart';
import 'tenant_portal_providers.dart';
import 'widgets/apartment_gate_pass_widget.dart';
import 'widgets/hostel_mess_menu_widget.dart';
import 'widgets/rental_meter_upload_widget.dart';
import 'widgets/tenant_load_error.dart';

export 'tenant_payments_sheet.dart' show showTenantRentPaymentsSheet;
export 'tenant_portal_providers.dart';

final _currency =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
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
          TenantHomeTab(
            onOpenPayments: () => setState(() => _tab = 1),
            onOpenServices: () => setState(() => _tab = 2),
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

// ─── Payments (Screen 7) ─────────────────────────────────────────────────────

class _TenantPaymentsTab extends ConsumerWidget {
  const _TenantPaymentsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myInvoicesProvider);
    return SafeArea(
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => TenantLoadError(
          title: "We couldn't load your payments",
          error: e,
          onRetry: () => ref.invalidate(myInvoicesProvider),
        ),
        data: (invoices) {
          final totalDue = outstandingTotal(invoices);
          DateTime? nearestDue;
          for (final inv in invoices.where(isOpenUnpaidInvoice)) {
            final d = invoiceDueDate(inv);
            if (d != null && (nearestDue == null || d.isBefore(nearestDue))) {
              nearestDue = d;
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
              const SizedBox(height: 12),
              const _PaymentHistoryEntry(),
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

class _PaymentHistoryEntry extends StatelessWidget {
  const _PaymentHistoryEntry();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: const Key('payment-history-entry'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const TenantPaymentHistoryScreen(),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _border, width: 1.2),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3E8FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.receipt_long_outlined,
                    color: _brand, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Payment History & Statements',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: _ink,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'View past payments and download PDF statements',
                      style: TextStyle(fontSize: 12, color: _muted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: _muted),
            ],
          ),
        ),
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

