// features/billing/presentation/hostel_pg_payments_body.dart
// Screen 3 — Hostel / PG Payments (dark). Rental / apartment keep invoices_list_screen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../structure/presentation/property_shell_screen.dart'
    show propertyDetailProvider;
import 'billing_invoice_helpers.dart';
import 'billing_providers.dart';
import 'create_invoice_screen.dart';
import 'tenant_ledger_sheet.dart';

class _H {
  static const bg = Color(0xFF0D1623);
  static const card = Color(0xFF151F30);
  static const cardElevated = Color(0xFF1A2438);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF94A3B8);
  static const purple = Color(0xFF8B5CF6);
  static const purpleBright = Color(0xFF7C3AED);
  static const green = Color(0xFF22C55E);
  static const greenBg = Color(0xFF14352A);
  static const red = Color(0xFFF87171);
  static const redBg = Color(0xFF3A1F28);
  static const orange = Color(0xFFF2835F);
  static const orangeBg = Color(0xFF3E2A22);
  static const border = Color(0xFF243044);
}

enum _PayFilter { all, collected, pending, overdue }

/// Dark Payments tab for Hostel / PG. Returns null when not Hostel/PG so
/// the caller can fall back to the existing light UI.
class HostelPgPaymentsBody extends ConsumerStatefulWidget {
  final String propertyId;

  const HostelPgPaymentsBody({super.key, required this.propertyId});

  /// True when this property should use Screen 3 dark payments.
  /// True for every property type — dark Payments Screen 3 is the default.
  static bool isHostelPg(Map<String, dynamic>? property) => true;

  @override
  ConsumerState<HostelPgPaymentsBody> createState() =>
      _HostelPgPaymentsBodyState();
}

class _HostelPgPaymentsBodyState extends ConsumerState<HostelPgPaymentsBody> {
  late DateTime _selectedMonth;
  _PayFilter _filter = _PayFilter.all;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month, 1);
  }

  List<DateTime> get _monthOptions {
    final now = DateTime.now();
    return List.generate(24, (i) {
      final d = DateTime(now.year, now.month - i, 1);
      return DateTime(d.year, d.month, 1);
    });
  }

  Future<void> _refresh() async {
    ref.invalidate(invoicesProvider(widget.propertyId));
    ref.invalidate(receivedThisMonthProvider(widget.propertyId));
    await ref.read(invoicesProvider(widget.propertyId).future);
  }

  Future<void> _openNewInvoice() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateInvoiceScreen(propertyId: widget.propertyId),
      ),
    );
    if (created == true) await _refresh();
  }

  Future<void> _pickMonth() async {
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: _H.card,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  'Select month',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: _H.textPrimary,
                  ),
                ),
              ),
              for (final m in _monthOptions)
                ListTile(
                  title: Text(
                    DateFormat('MMMM yyyy').format(m),
                    style: const TextStyle(color: _H.textPrimary),
                  ),
                  trailing: m.year == _selectedMonth.year &&
                          m.month == _selectedMonth.month
                      ? const Icon(Icons.check, color: _H.purple)
                      : null,
                  onTap: () => Navigator.pop(context, m),
                ),
            ],
          ),
        );
      },
    );
    if (picked != null) setState(() => _selectedMonth = picked);
  }

  Future<void> _openLedger(
    _PayGroup group,
    List<Map<String, dynamic>> allInvoices,
  ) async {
    await showTenantLedgerSheet(
      context: context,
      ref: ref,
      propertyId: widget.propertyId,
      tenancyId: group.tenancyId,
      tenantName: group.name,
      roomLabel: group.roomLabel,
      phone: group.phone,
      allInvoices: allInvoices,
    );
    await _refresh();
  }

  List<_PayGroup> _groupByTenant(List<Map<String, dynamic>> invoices) {
    final map = <String, _PayGroup>{};
    for (final inv in invoices) {
      if (!invoiceMatchesMonth(inv, _selectedMonth)) continue;
      final tenancyId =
          (inv['tenancy_id'] ?? inv['tenancyId'])?.toString() ?? '';
      if (tenancyId.isEmpty) continue;
      final group = map.putIfAbsent(
        tenancyId,
        () => _PayGroup(
          tenancyId: tenancyId,
          name: tenantDisplayName(inv),
          room: inv['node_name']?.toString() ??
              inv['nodeName']?.toString() ??
              '—',
          floor: inv['floor_name']?.toString() ?? inv['floorName']?.toString(),
          phone: tenantPhone(inv),
          invoices: [],
        ),
      );
      group.invoices.add(inv);
      final phone = tenantPhone(inv);
      if ((group.phone == null || group.phone!.trim().isEmpty) &&
          phone != null &&
          phone.trim().isNotEmpty) {
        group.phone = phone;
      }
    }
    final groups = map.values.toList()
      ..sort((a, b) {
        final byPending = b.pending.compareTo(a.pending);
        if (byPending != 0) return byPending;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final invoicesAsync = ref.watch(invoicesProvider(widget.propertyId));

    return ColoredBox(
      color: _H.bg,
      child: invoicesAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: _H.purple),
        ),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Something went wrong: $err',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _H.textSecondary),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _refresh,
                  style: TextButton.styleFrom(foregroundColor: _H.purple),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (invoices) {
          final groups = _groupByTenant(invoices);
          var collected = 0.0;
          var pending = 0.0;
          for (final g in groups) {
            collected += g.collected;
            pending += g.pending;
          }

          final collectedCount =
              groups.where((g) => g.displayStatus == 'collected').length;
          final pendingCount =
              groups.where((g) => g.displayStatus == 'pending').length;
          final overdueCount =
              groups.where((g) => g.displayStatus == 'overdue').length;

          final visible = groups.where((g) {
            switch (_filter) {
              case _PayFilter.all:
                return true;
              case _PayFilter.collected:
                return g.displayStatus == 'collected';
              case _PayFilter.pending:
                return g.displayStatus == 'pending';
              case _PayFilter.overdue:
                return g.displayStatus == 'overdue';
            }
          }).toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: _Header(
                  selectedMonth: _selectedMonth,
                  onMonthTap: _pickMonth,
                  onNewInvoice: _openNewInvoice,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: _SummaryCard(
                        label: 'Collected',
                        amount: collected,
                        accent: _H.green,
                        bg: _H.greenBg,
                        icon: Icons.check_circle_outline_rounded,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SummaryCard(
                        label: 'Pending',
                        amount: pending,
                        accent: _H.red,
                        bg: _H.redBg,
                        icon: Icons.schedule_rounded,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _FilterChips(
                allCount: groups.length,
                collectedCount: collectedCount,
                pendingCount: pendingCount,
                overdueCount: overdueCount,
                selected: _filter,
                onSelected: (f) => setState(() => _filter = f),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: RefreshIndicator(
                  color: _H.purple,
                  backgroundColor: _H.card,
                  onRefresh: _refresh,
                  child: visible.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: 260,
                              child: _EmptyState(onAdd: _openNewInvoice),
                            ),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                          itemCount: visible.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final g = visible[i];
                            return _PaymentCard(
                              group: g,
                              onTap: () => _openLedger(g, invoices),
                            );
                          },
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final DateTime selectedMonth;
  final VoidCallback onMonthTap;
  final VoidCallback onNewInvoice;

  const _Header({
    required this.selectedMonth,
    required this.onMonthTap,
    required this.onNewInvoice,
  });

  @override
  Widget build(BuildContext context) {
    final monthLabel = DateFormat('MMMM yyyy').format(selectedMonth);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Payments',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: _H.textPrimary,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              InkWell(
                onTap: onMonthTap,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        monthLabel,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _H.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(
                        Icons.keyboard_arrow_down,
                        size: 20,
                        color: _H.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Material(
          color: _H.purpleBright,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onNewInvoice,
            borderRadius: BorderRadius.circular(12),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 18, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    'New Invoice',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final double amount;
  final Color accent;
  final Color bg;
  final IconData icon;

  const _SummaryCard({
    required this.label,
    required this.amount,
    required this.accent,
    required this.bg,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: accent),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            billingCurrency.format(amount),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: accent,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  final int allCount;
  final int collectedCount;
  final int pendingCount;
  final int overdueCount;
  final _PayFilter selected;
  final ValueChanged<_PayFilter> onSelected;

  const _FilterChips({
    required this.allCount,
    required this.collectedCount,
    required this.pendingCount,
    required this.overdueCount,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _Chip(
            label: 'All ($allCount)',
            selected: selected == _PayFilter.all,
            onTap: () => onSelected(_PayFilter.all),
          ),
          const SizedBox(width: 8),
          _Chip(
            label: 'Collected ($collectedCount)',
            selected: selected == _PayFilter.collected,
            onTap: () => onSelected(_PayFilter.collected),
          ),
          const SizedBox(width: 8),
          _Chip(
            label: 'Pending ($pendingCount)',
            selected: selected == _PayFilter.pending,
            onTap: () => onSelected(_PayFilter.pending),
          ),
          const SizedBox(width: 8),
          _Chip(
            label: 'Overdue ($overdueCount)',
            selected: selected == _PayFilter.overdue,
            onTap: () => onSelected(_PayFilter.overdue),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _H.purple : _H.card,
      shape: StadiumBorder(
        side: BorderSide(color: selected ? _H.purple : _H.border),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : _H.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  final _PayGroup group;
  final VoidCallback onTap;

  const _PaymentCard({required this.group, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final amount = group.pending > 0.009 ? group.pending : group.collected;
    final amountColor =
        group.pending > 0.009 ? _H.red : _H.green;
    final initial = group.name.trim().isEmpty
        ? '?'
        : group.name.trim()[0].toUpperCase();

    return Material(
      color: _H.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
                  ),
                ),
                child: Text(
                  initial,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _H.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      group.roomLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: _H.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      billingCurrency.format(amount),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: amountColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusPill(status: group.displayStatus),
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_vert,
                  color: _H.textSecondary,
                  size: 20,
                ),
                color: _H.cardElevated,
                onSelected: (v) {
                  if (v == 'view') onTap();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'view',
                    child: Text(
                      'View ledger',
                      style: TextStyle(color: _H.textPrimary),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String status;

  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    late Color bg;
    late Color fg;
    late String label;

    switch (status) {
      case 'collected':
        bg = _H.greenBg;
        fg = _H.green;
        label = 'Collected';
      case 'overdue':
        bg = _H.orangeBg;
        fg = _H.orange;
        label = 'Overdue';
      case 'pending':
      default:
        bg = _H.redBg;
        fg = _H.red;
        label = 'Pending';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.payments_outlined,
              size: 48,
              color: _H.textSecondary.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 12),
            const Text(
              'No payments found',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _H.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Try another month or create an invoice.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _H.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: onAdd,
              style: TextButton.styleFrom(foregroundColor: _H.purple),
              child: const Text('+ New Invoice'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PayGroup {
  final String tenancyId;
  final String name;
  final String room;
  final String? floor;
  String? phone;
  final List<Map<String, dynamic>> invoices;

  _PayGroup({
    required this.tenancyId,
    required this.name,
    required this.room,
    required this.floor,
    required this.phone,
    required this.invoices,
  });

  String get roomLabel {
    final roomPart = room.isEmpty
        ? '—'
        : (room.toLowerCase().contains('room') ? room : 'Room $room');
    if (floor != null && floor!.trim().isNotEmpty) {
      return '$roomPart - ${floor!.trim()}';
    }
    return roomPart;
  }

  double get collected {
    var sum = 0.0;
    for (final inv in invoices) {
      sum += invoicePaidAmount(inv);
    }
    return sum;
  }

  double get pending {
    var sum = 0.0;
    for (final inv in invoices) {
      if (invoiceStatus(inv) == 'paid') continue;
      sum += invoiceRemaining(inv);
    }
    return sum;
  }

  bool get hasOverdue => invoices.any((i) => invoiceStatus(i) == 'overdue');

  /// collected | pending | overdue
  String get displayStatus {
    if (hasOverdue && pending > 0.009) return 'overdue';
    if (pending > 0.009) return 'pending';
    return 'collected';
  }
}

/// Helper used by [InvoicesListScreen] to decide Hostel dark branch without
/// re-importing archetype plumbing in every caller.
bool hostelPgPaymentsEnabled(WidgetRef ref, String propertyId) {
  final property =
      ref.watch(propertyDetailProvider(propertyId)).asData?.value;
  return HostelPgPaymentsBody.isHostelPg(property);
}
