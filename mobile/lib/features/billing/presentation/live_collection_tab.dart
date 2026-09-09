// features/billing/presentation/live_collection_tab.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../tenancies/data/tenancy_repository.dart';
import 'billing_invoice_helpers.dart';
import 'billing_providers.dart';
import 'create_invoice_screen.dart';
import 'tenant_ledger_sheet.dart';
import 'whatsapp_reminder.dart';

const _accent = AppColors.blueprint;
const _accentSoft = AppColors.primarySoft;
const _accentMuted = AppColors.primaryMuted;

enum _StatusFilter { all, pending, paid, overdue }

/// Live Collection — matches the Payments reference mock.
class LiveCollectionTab extends ConsumerStatefulWidget {
  final String propertyId;
  final DateTime selectedMonth;

  const LiveCollectionTab({
    super.key,
    required this.propertyId,
    required this.selectedMonth,
  });

  @override
  ConsumerState<LiveCollectionTab> createState() => _LiveCollectionTabState();
}

class _LiveCollectionTabState extends ConsumerState<LiveCollectionTab> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  _StatusFilter _filter = _StatusFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(invoicesProvider(widget.propertyId));
    ref.invalidate(receivedThisMonthProvider(widget.propertyId));
    await Future.wait([
      ref.read(invoicesProvider(widget.propertyId).future),
      ref.read(receivedThisMonthProvider(widget.propertyId).future),
    ]);
  }

  Future<void> _openNewInvoice() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateInvoiceScreen(propertyId: widget.propertyId),
      ),
    );
    if (created == true) await _refresh();
  }

  Future<void> _openLedger(
    _TenantPaymentGroup group,
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

  List<_TenantPaymentGroup> _groupByTenant(
    List<Map<String, dynamic>> invoices,
  ) {
    final map = <String, _TenantPaymentGroup>{};

    for (final inv in invoices) {
      final tenancyId =
          (inv['tenancy_id'] ?? inv['tenancyId'])?.toString() ?? '';
      if (tenancyId.isEmpty) continue;

      final group = map.putIfAbsent(
        tenancyId,
        () => _TenantPaymentGroup(
          tenancyId: tenancyId,
          name: tenantDisplayName(inv),
          room: inv['node_name']?.toString() ??
              inv['nodeName']?.toString() ??
              '—',
          floor: inv['floor_name']?.toString() ??
              inv['floorName']?.toString(),
          photoUrl: tenantPhotoUrl(inv),
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
        final byPending =
            b.grandTotalPending.compareTo(a.grandTotalPending);
        if (byPending != 0) return byPending;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return groups;
  }

  List<_TenantPaymentGroup> _applyFilters(List<_TenantPaymentGroup> groups) {
    final byStatus = groups.where((g) {
      switch (_filter) {
        case _StatusFilter.all:
          return true;
        case _StatusFilter.pending:
          return g.displayStatus == 'pending' ||
              g.displayStatus == 'partial';
        case _StatusFilter.paid:
          return g.displayStatus == 'paid';
        case _StatusFilter.overdue:
          return g.displayStatus == 'overdue';
      }
    });

    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return byStatus.toList();
    return byStatus.where((g) {
      return g.name.toLowerCase().contains(q) ||
          g.room.toLowerCase().contains(q) ||
          (g.phone ?? '').contains(q) ||
          g.grandTotalPending.toStringAsFixed(0).contains(q);
    }).toList();
  }

  /// Month-scoped collection metrics for the unified progress banner.
  _CollectionMonthStats _monthStats(List<Map<String, dynamic>> all) {
    var collected = 0.0;
    var outstanding = 0.0;
    for (final inv in all) {
      if (!invoiceMatchesMonth(inv, widget.selectedMonth)) continue;
      collected += invoicePaidAmount(inv);
      if (isOpenUnpaidInvoice(inv)) {
        outstanding += invoiceRemaining(inv);
      }
    }
    final totalExpected = collected + outstanding;
    return _CollectionMonthStats(
      collected: collected,
      outstanding: outstanding,
      totalExpected: totalExpected,
    );
  }

  /// Tenants with an unpaid invoice due within the next 7 days.
  _DueThisWeekSummary _dueThisWeek(List<_TenantPaymentGroup> allGroups) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekEnd = today.add(const Duration(days: 7));
    var amount = 0.0;
    var tenants = 0;

    for (final g in allGroups) {
      if (g.grandTotalPending <= 0.009) continue;
      var dueHere = 0.0;
      for (final inv in g.invoices) {
        if (!isOpenUnpaidInvoice(inv)) continue;
        final raw = (inv['due_date'] ?? inv['dueDate'])?.toString();
        if (raw == null) continue;
        final d = DateTime.tryParse(raw)?.toLocal();
        if (d == null) continue;
        final day = DateTime(d.year, d.month, d.day);
        if (!day.isBefore(today) && day.isBefore(weekEnd)) {
          dueHere += invoiceRemaining(inv);
        }
      }
      if (dueHere > 0.009) {
        amount += dueHere;
        tenants += 1;
      }
    }
    return _DueThisWeekSummary(amount: amount, tenantCount: tenants);
  }

  Future<void> _sendDueReminders(List<_TenantPaymentGroup> allGroups) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekEnd = today.add(const Duration(days: 7));
    final targets = <_TenantPaymentGroup>[];

    for (final g in allGroups) {
      if (g.grandTotalPending <= 0.009) continue;
      final hasDue = g.invoices.any((inv) {
        if (!isOpenUnpaidInvoice(inv)) return false;
        final raw = (inv['due_date'] ?? inv['dueDate'])?.toString();
        if (raw == null) return false;
        final d = DateTime.tryParse(raw)?.toLocal();
        if (d == null) return false;
        final day = DateTime(d.year, d.month, d.day);
        return !day.isBefore(today) && day.isBefore(weekEnd);
      });
      if (hasDue) targets.add(g);
    }

    if (targets.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No dues falling due this week')),
      );
      return;
    }

    // Open WhatsApp for the first due tenant; others noted in snackbar.
    final first = targets.first;
    await sendWhatsAppReminder(
      context,
      phone: first.phone,
      name: first.name,
      amount: first.grandTotalPending,
    );
    if (!mounted) return;
    if (targets.length > 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Opened reminder for ${first.name}. '
            '${targets.length - 1} more tenant(s) due this week.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<LiveCollectionStatusFilter?>(
      liveCollectionFilterRequestProvider,
      (prev, next) {
        if (next == null) return;
        final mapped = switch (next) {
          LiveCollectionStatusFilter.all => _StatusFilter.all,
          LiveCollectionStatusFilter.pending => _StatusFilter.pending,
          LiveCollectionStatusFilter.paid => _StatusFilter.paid,
          LiveCollectionStatusFilter.overdue => _StatusFilter.overdue,
        };
        if (_filter != mapped) {
          setState(() => _filter = mapped);
        }
      },
    );

    final invoicesAsync = ref.watch(invoicesProvider(widget.propertyId));
    final baseUrl = ref.watch(tenancyRepositoryProvider).baseUrl;

    return invoicesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Something went wrong: $err', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _refresh,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      data: (invoices) {
        final monthStats = _monthStats(invoices);
        final allGroups = _groupByTenant(invoices);
        final visible = _applyFilters(allGroups);
        final hasAnyInvoices = invoices.isNotEmpty;

        final pendingCount = allGroups
            .where((g) =>
                g.displayStatus == 'pending' || g.displayStatus == 'partial')
            .length;
        final paidCount =
            allGroups.where((g) => g.displayStatus == 'paid').length;
        final overdueCount =
            allGroups.where((g) => g.displayStatus == 'overdue').length;
        final dueWeek = _dueThisWeek(allGroups);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 8),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: _CollectionProgressBanner(stats: monthStats),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: _SearchFilterRow(
                        controller: _searchController,
                        onChanged: (v) => setState(() => _searchQuery = v),
                        onFilterTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Use status chips to filter'),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    _StatusFilterPills(
                      allCount: allGroups.length,
                      pendingCount: pendingCount,
                      paidCount: paidCount,
                      overdueCount: overdueCount,
                      selected: _filter,
                      onSelected: (f) => setState(() => _filter = f),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: _TableHeaderRow(),
                    ),
                    if (visible.isEmpty)
                      SizedBox(
                        height: 220,
                        child: _EmptyLiveCollection(
                          onCreate: _openNewInvoice,
                          hasAnyInvoices: hasAnyInvoices,
                          searching: _searchQuery.trim().isNotEmpty,
                        ),
                      )
                    else
                      for (var i = 0; i < visible.length; i++) ...[
                        if (i > 0)
                          const Divider(
                            height: 1,
                            thickness: 1,
                            color: AppColors.hairline,
                            indent: 12,
                            endIndent: 12,
                          ),
                        _TenantLedgerListRow(
                          group: visible[i],
                          baseUrl: baseUrl,
                          onPay: () => _openLedger(visible[i], invoices),
                          onRowTap: () => _openLedger(visible[i], invoices),
                          onWhatsApp: () => sendWhatsAppReminder(
                            context,
                            phone: visible[i].phone,
                            name: visible[i].name,
                            amount: visible[i].grandTotalPending > 0
                                ? visible[i].grandTotalPending
                                : visible[i].totalBilled,
                          ),
                        ),
                      ],
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              minimum: EdgeInsets.zero,
              child: _DueThisWeekBanner(
                summary: dueWeek,
                onTap: () {
                  final dueGroups = allGroups.where((g) {
                    return _dueThisWeek([g]).tenantCount > 0;
                  }).toList();
                  if (dueGroups.isNotEmpty) {
                    _openLedger(dueGroups.first, invoices);
                  }
                },
                onSendReminders: () => _sendDueReminders(allGroups),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DueThisWeekSummary {
  final double amount;
  final int tenantCount;

  const _DueThisWeekSummary({
    required this.amount,
    required this.tenantCount,
  });
}

class _CollectionMonthStats {
  final double collected;
  final double outstanding;
  final double totalExpected;

  const _CollectionMonthStats({
    required this.collected,
    required this.outstanding,
    required this.totalExpected,
  });

  double get progress {
    if (totalExpected <= 0) return 0;
    return (collected / totalExpected).clamp(0.0, 1.0);
  }
}

// ── Unified collection progress banner ──────────────────────────────────

class _CollectionProgressBanner extends StatelessWidget {
  final _CollectionMonthStats stats;

  const _CollectionProgressBanner({required this.stats});

  @override
  Widget build(BuildContext context) {
    final pct = (stats.progress * 100).round();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hairline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 60,
              height: 60,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 60,
                    height: 60,
                    child: CircularProgressIndicator(
                      value: stats.progress,
                      strokeWidth: 8,
                      color: _accent,
                      backgroundColor: Colors.grey.shade200,
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                  Text(
                    '$pct%',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Collection Progress',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: billingCurrency.format(stats.collected),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                            ),
                          ),
                          TextSpan(
                            text:
                                ' / ${billingCurrency.format(stats.totalExpected)}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Text(
                          'Collected',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.positive,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Total Expected',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            VerticalDivider(
              color: Colors.grey.shade300,
              width: 20,
              thickness: 1,
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        billingCurrency.format(stats.outstanding),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Outstanding',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 2),
                const Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: Colors.black54,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Search + chips ──────────────────────────────────────────────────────

class _SearchFilterRow extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onFilterTap;

  const _SearchFilterRow({
    required this.controller,
    required this.onChanged,
    required this.onFilterTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: 'Search tenant, room or amount...',
              hintStyle: TextStyle(
                color: AppColors.slate.withValues(alpha: 0.8),
                fontSize: 13,
              ),
              prefixIcon: const Icon(
                Icons.search,
                color: AppColors.slate,
                size: 20,
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: EdgeInsets.zero,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.hairline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _accent, width: 1.2),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: AppColors.hairline),
          ),
          child: InkWell(
            onTap: onFilterTap,
            borderRadius: BorderRadius.circular(10),
            child: const SizedBox(
              width: 48,
              height: 48,
              child: Icon(Icons.tune, color: AppColors.slate, size: 20),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusFilterPills extends StatelessWidget {
  final int allCount;
  final int pendingCount;
  final int paidCount;
  final int overdueCount;
  final _StatusFilter selected;
  final ValueChanged<_StatusFilter> onSelected;

  const _StatusFilterPills({
    required this.allCount,
    required this.pendingCount,
    required this.paidCount,
    required this.overdueCount,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _FilterPill(
            label: 'All ($allCount)',
            selected: selected == _StatusFilter.all,
            onTap: () => onSelected(_StatusFilter.all),
          ),
          const SizedBox(width: 8),
          _FilterPill(
            label: 'Pending ($pendingCount)',
            dotColor: AppColors.caution,
            selected: selected == _StatusFilter.pending,
            onTap: () => onSelected(_StatusFilter.pending),
          ),
          const SizedBox(width: 8),
          _FilterPill(
            label: 'Paid ($paidCount)',
            dotColor: AppColors.positive,
            selected: selected == _StatusFilter.paid,
            onTap: () => onSelected(_StatusFilter.paid),
          ),
          const SizedBox(width: 8),
          _FilterPill(
            label: 'Overdue ($overdueCount)',
            dotColor: AppColors.danger,
            selected: selected == _StatusFilter.overdue,
            onTap: () => onSelected(_StatusFilter.overdue),
          ),
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final Color? dotColor;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.dotColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _accent : Colors.white,
      shape: StadiumBorder(
        side: BorderSide(color: selected ? _accent : AppColors.hairline),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dotColor != null && !selected) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: dotColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Table ───────────────────────────────────────────────────────────────

class _TableHeaderRow extends StatelessWidget {
  const _TableHeaderRow();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 11,
      color: AppColors.slate,
      fontWeight: FontWeight.w500,
    );
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text('Tenant', style: style)),
          Text('Dues / Amount', style: style),
          SizedBox(width: 12),
          Text('Actions', style: style),
        ],
      ),
    );
  }
}

class _TenantPaymentGroup {
  final String tenancyId;
  final String name;
  final String room;
  final String? floor;
  final String? photoUrl;
  String? phone;
  final List<Map<String, dynamic>> invoices;

  _TenantPaymentGroup({
    required this.tenancyId,
    required this.name,
    required this.room,
    required this.floor,
    required this.photoUrl,
    required this.phone,
    required this.invoices,
  });

  String get roomLabel {
    if (floor != null && floor!.trim().isNotEmpty) {
      final f = floor!.trim();
      return f.toLowerCase().contains('floor')
          ? '$room · $f'
          : '$room · $f Floor';
    }
    return room;
  }

  double get grandTotalPending {
    var sum = 0.0;
    for (final inv in invoices) {
      if (invoiceStatus(inv) == 'paid') continue;
      sum += invoiceRemaining(inv);
    }
    return sum;
  }

  double get totalBilled =>
      invoices.fold<double>(0, (s, i) => s + invoiceTotalAmount(i));

  List<DateTime> get unpaidMonths {
    final months = <String, DateTime>{};
    for (final inv in invoices) {
      if (invoiceStatus(inv) == 'paid') continue;
      if (invoiceRemaining(inv) <= 0.009) continue;
      final d = invoiceMonthDate(inv);
      if (d != null) {
        months['${d.year}-${d.month}'] = d;
      }
    }
    final list = months.values.toList()..sort();
    return list;
  }

  int get unpaidMonthCount {
    final n = unpaidMonths.length;
    if (n > 0) return n;
    return invoices.where((i) => invoiceStatus(i) != 'paid').length;
  }

  String get duesTitle {
    final n = unpaidMonthCount;
    if (displayStatus == 'paid') {
      return '${invoices.length} paid';
    }
    return '$n month${n == 1 ? '' : 's'}';
  }

  String get duesSubtitle {
    if (displayStatus == 'paid') return 'Cleared';
    final labels =
        unpaidMonths.map((d) => DateFormat('MMM').format(d)).toList();
    if (labels.isEmpty) return '—';
    return labels.join(', ');
  }

  bool get hasOverdue => invoices.any((i) => invoiceStatus(i) == 'overdue');

  bool get hasPartial => invoices.any((i) {
        final s = invoiceStatus(i);
        return s == 'partial' || s == 'partially_paid';
      });

  String get displayStatus {
    if (hasOverdue) return 'overdue';
    if (grandTotalPending > 0.009) {
      return hasPartial ? 'partial' : 'pending';
    }
    if (invoices.any((i) => invoiceStatus(i) == 'paid')) return 'paid';
    return 'pending';
  }

  String? get phoneDisplay {
    final raw = phone?.trim();
    if (raw == null || raw.isEmpty) return null;
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('0')) {
      digits = digits.replaceFirst(RegExp(r'^0+'), '');
    }
    if (digits.length == 10) return '+91 $digits';
    if (digits.length == 12 && digits.startsWith('91')) {
      return '+91 ${digits.substring(2)}';
    }
    if (raw.startsWith('+')) return raw;
    return raw;
  }
}

class _TenantLedgerListRow extends StatelessWidget {
  final _TenantPaymentGroup group;
  final String baseUrl;
  final VoidCallback onPay;
  final VoidCallback onRowTap;
  final VoidCallback onWhatsApp;

  const _TenantLedgerListRow({
    required this.group,
    required this.baseUrl,
    required this.onPay,
    required this.onRowTap,
    required this.onWhatsApp,
  });

  @override
  Widget build(BuildContext context) {
    final photoUrl = resolvePhotoUrl(group.photoUrl, baseUrl);
    final initials = initialsFromName(group.name);
    final amount = group.grandTotalPending > 0.009
        ? group.grandTotalPending
        : group.totalBilled;
    final amountColor = group.grandTotalPending > 0.009
        ? const Color(0xFFDC2626)
        : AppColors.positive;
    final phone = group.phoneDisplay;

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onRowTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: _accentSoft,
                    backgroundImage:
                        photoUrl != null ? NetworkImage(photoUrl) : null,
                    child: photoUrl == null
                        ? Text(
                            initials,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _accent,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          group.roomLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.slate,
                          ),
                        ),
                        if (phone != null) ...[
                          const SizedBox(height: 1),
                          Text(
                            phone,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.slate,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _InvoiceStatusBadge(status: group.displayStatus),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.duesTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                        Text(
                          group.duesSubtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.slate,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    billingCurrency.format(amount),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: amountColor,
                    ),
                  ),
                  const SizedBox(width: 4),
                  _ActionIcon(
                    tooltip: 'WhatsApp reminder',
                    icon: Icons.chat,
                    color: whatsAppGreen,
                    onTap: onWhatsApp,
                  ),
                  _ActionIcon(
                    tooltip: 'Pay',
                    icon: Icons.payments_outlined,
                    color: AppColors.blueprint,
                    onTap: onPay,
                  ),
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      iconSize: 18,
                      tooltip: 'More',
                      icon: const Icon(
                        Icons.more_vert,
                        size: 18,
                        color: AppColors.slate,
                      ),
                      onSelected: (v) {
                        if (v == 'ledger') onPay();
                        if (v == 'whatsapp') onWhatsApp();
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'ledger',
                          child: Text('View ledger'),
                        ),
                        PopupMenuItem(
                          value: 'whatsapp',
                          child: Text('WhatsApp reminder'),
                        ),
                      ],
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

class _ActionIcon extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionIcon({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: color),
    );
  }
}

class _InvoiceStatusBadge extends StatelessWidget {
  final String status;

  const _InvoiceStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    late Color bg;
    late Color fg;
    late String label;

    switch (status) {
      case 'paid':
        bg = AppColors.positive.withValues(alpha: 0.12);
        fg = AppColors.positive;
        label = 'Paid';
      case 'overdue':
        bg = AppColors.danger.withValues(alpha: 0.12);
        fg = AppColors.danger;
        label = 'Overdue';
      case 'partial':
        bg = AppColors.caution.withValues(alpha: 0.12);
        fg = AppColors.caution;
        label = 'Partial';
      default:
        bg = const Color(0xFFFFF7ED);
        fg = const Color(0xFFD97706);
        label = 'Pending';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sticky due banner ───────────────────────────────────────────────────

class _DueThisWeekBanner extends StatelessWidget {
  final _DueThisWeekSummary summary;
  final VoidCallback onTap;
  final VoidCallback onSendReminders;

  const _DueThisWeekBanner({
    required this.summary,
    required this.onTap,
    required this.onSendReminders,
  });

  @override
  Widget build(BuildContext context) {
    final tenantLabel = summary.tenantCount == 0
        ? 'No dues this week'
        : '${billingCurrency.format(summary.amount)} from ${summary.tenantCount} tenant${summary.tenantCount == 1 ? '' : 's'}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Material(
        color: _accentMuted,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _accent.withValues(alpha: 0.12)),
          ),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: summary.tenantCount > 0 ? onTap : null,
                  borderRadius: BorderRadius.circular(10),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.calendar_month_outlined,
                          size: 18,
                          color: _accent,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Next due this week',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.slate,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              tenantLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: AppColors.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (summary.tenantCount > 0)
                        const Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: AppColors.slate,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: onSendReminders,
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: _accent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.send_outlined, size: 15),
                    label: const Text(
                      'Send Reminders',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyLiveCollection extends StatelessWidget {
  final VoidCallback onCreate;
  final bool hasAnyInvoices;
  final bool searching;

  const _EmptyLiveCollection({
    required this.onCreate,
    required this.hasAnyInvoices,
    required this.searching,
  });

  @override
  Widget build(BuildContext context) {
    final title = !hasAnyInvoices
        ? 'No invoices found'
        : searching
            ? 'No matching tenants'
            : 'No tenants in this filter';
    final subtitle = !hasAnyInvoices
        ? 'Create your first invoice to start collecting.'
        : searching
            ? 'Try a different search.'
            : 'Try another status chip.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.receipt_long_outlined,
              size: 48,
              color: AppColors.slate,
            ),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (!hasAnyInvoices) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: onCreate,
                child: const Text('New Invoice'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
