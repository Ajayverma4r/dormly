// features/billing/presentation/invoices_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../tenancies/data/tenancy_repository.dart';
import '../data/billing_repository.dart';
import 'create_invoice_screen.dart';
import 'tenant_ledger_sheet.dart';

enum _InvoiceStatusFilter { all, pending, paid, overdue }

const _accent = Color(0xFF7C3AED);

final invoicesProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, propertyId) =>
      ref.watch(billingRepositoryProvider).listInvoices(propertyId),
);

class InvoicesListScreen extends ConsumerStatefulWidget {
  final String propertyId;
  final bool asTab;

  const InvoicesListScreen({
    super.key,
    required this.propertyId,
    this.asTab = false,
  });

  @override
  ConsumerState<InvoicesListScreen> createState() => _InvoicesListScreenState();
}

class _InvoicesListScreenState extends ConsumerState<InvoicesListScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  _InvoiceStatusFilter _filter = _InvoiceStatusFilter.all;
  late DateTime _selectedMonth;

  static final _monthFormat = DateFormat('MMMM yyyy');
  static final _currency =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month, 1);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Select month',
    );
    if (picked != null) {
      setState(() => _selectedMonth = DateTime(picked.year, picked.month, 1));
    }
  }

  Future<void> _openNewInvoice() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateInvoiceScreen(propertyId: widget.propertyId),
      ),
    );
    if (created == true) {
      ref.invalidate(invoicesProvider(widget.propertyId));
    }
  }

  Future<void> _openTenantLedger(
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
      allInvoices: allInvoices,
    );
    ref.invalidate(invoicesProvider(widget.propertyId));
  }

  DateTime? _invoiceMonthDate(Map<String, dynamic> inv) {
    for (final key in [
      'period_start',
      'periodStart',
      'period_end',
      'periodEnd',
      'due_date',
      'dueDate',
      'created_at',
      'createdAt',
    ]) {
      final raw = inv[key]?.toString().trim();
      if (raw == null || raw.isEmpty) continue;
      final match = RegExp(r'^(\d{4})-(\d{2})').firstMatch(raw);
      if (match != null) {
        final year = int.tryParse(match.group(1)!);
        final month = int.tryParse(match.group(2)!);
        if (year != null && month != null) return DateTime(year, month, 1);
      }
      final d = DateTime.tryParse(raw);
      if (d != null) {
        final local = d.toLocal();
        return DateTime(local.year, local.month, 1);
      }
    }
    return null;
  }

  /// Match invoice to selected month using YYYY-MM from the raw date string
  /// so UTC midnight DATE values are not shifted into the previous month.
  bool _inSelectedMonth(Map<String, dynamic> inv) {
    final month = _invoiceMonthDate(inv);
    if (month == null) return true;
    return month.year == _selectedMonth.year &&
        month.month == _selectedMonth.month;
  }

  bool _isBeforeSelectedMonth(Map<String, dynamic> inv) {
    final month = _invoiceMonthDate(inv);
    if (month == null) return false;
    return month.isBefore(_selectedMonth);
  }

  bool _isOpenUnpaid(Map<String, dynamic> inv) {
    final status = _status(inv);
    if (!{'pending', 'overdue', 'partial', 'partially_paid'}.contains(status)) {
      return false;
    }
    return (_totalAmount(inv) - _paidAmount(inv)) > 0.009;
  }

  /// Selected-month invoices + ALL open unpaid invoices from earlier months.
  List<Map<String, dynamic>> _listWithCarryForward(
      List<Map<String, dynamic>> invoices) {
    final seen = <String>{};
    final result = <Map<String, dynamic>>[];

    void add(Map<String, dynamic> inv) {
      final id = inv['id']?.toString();
      if (id == null || id.isEmpty || seen.contains(id)) return;
      seen.add(id);
      result.add(inv);
    }

    for (final inv in invoices) {
      if (_inSelectedMonth(inv)) add(inv);
    }
    for (final inv in invoices) {
      if (_isBeforeSelectedMonth(inv) && _isOpenUnpaid(inv)) add(inv);
    }

    result.sort((a, b) {
      final am = _invoiceMonthDate(a) ?? DateTime(1970);
      final bm = _invoiceMonthDate(b) ?? DateTime(1970);
      final cmp = bm.compareTo(am);
      if (cmp != 0) return cmp;
      return _totalAmount(b).compareTo(_totalAmount(a));
    });
    return result;
  }

  double _totalAmount(Map<String, dynamic> inv) =>
      double.tryParse(
        (inv['total_amount'] ?? inv['totalAmount'])?.toString() ?? '',
      ) ??
      0;

  double _paidAmount(Map<String, dynamic> inv) =>
      double.tryParse(
        (inv['paid_amount'] ?? inv['paidAmount'])?.toString() ?? '',
      ) ??
      0;

  double _remaining(Map<String, dynamic> inv) =>
      (_totalAmount(inv) - _paidAmount(inv)).clamp(0.0, double.infinity);

  String _status(Map<String, dynamic> inv) =>
      inv['status']?.toString().toLowerCase().trim() ?? 'pending';

  /// One ledger row per tenant from unpaid (and optionally paid) invoices.
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
          name: inv['full_name']?.toString() ??
              inv['fullName']?.toString() ??
              'Tenant',
          room: inv['node_name']?.toString() ??
              inv['nodeName']?.toString() ??
              '—',
          floor: inv['floor_name']?.toString() ??
              inv['floorName']?.toString(),
          photoUrl: (inv['profile_photo_url'] ?? inv['profilePhotoUrl'])
              ?.toString(),
          invoices: [],
        ),
      );
      group.invoices.add(inv);
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

  List<_TenantPaymentGroup> _filterTenantGroups(
    List<_TenantPaymentGroup> groups,
  ) {
    final q = _searchQuery.trim().toLowerCase();
    return groups.where((g) {
      if (q.isEmpty) return true;
      return g.name.toLowerCase().contains(q) ||
          g.room.toLowerCase().contains(q) ||
          g.grandTotalPending.toStringAsFixed(0).contains(q);
    }).toList();
  }

  /// Expected/Collected for selected month; Pending = global unpaid debt.
  _CollectionSummary _summary({
    required List<Map<String, dynamic>> monthInvoices,
    required List<Map<String, dynamic>> allInvoices,
  }) {
    var expected = 0.0;
    var collected = 0.0;

    for (final inv in monthInvoices) {
      final amount = _totalAmount(inv);
      final paid = _paidAmount(inv);
      final status = _status(inv);
      expected += amount;
      if (status == 'paid') {
        collected += amount;
      } else if (status == 'partial' || status == 'partially_paid') {
        collected += paid;
      }
    }

    var pending = 0.0;
    for (final inv in allInvoices) {
      if (!_isOpenUnpaid(inv)) continue;
      pending += _remaining(inv);
    }

    final ratio = expected > 0 ? (collected / expected).clamp(0.0, 1.0) : 0.0;
    return _CollectionSummary(
      expected: expected,
      collected: collected,
      pending: pending,
      percent: ratio * 100,
    );
  }

  Future<void> _refreshInvoices() async {
    ref.invalidate(invoicesProvider(widget.propertyId));
    await ref.read(invoicesProvider(widget.propertyId).future);
  }

  @override
  Widget build(BuildContext context) {
    final invoicesAsync = ref.watch(invoicesProvider(widget.propertyId));
    final baseUrl = ref.watch(tenancyRepositoryProvider).baseUrl;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: widget.asTab
          ? null
          : AppBar(title: const Text('Rent & Billing')),
      body: SafeArea(
        child: invoicesAsync.when(
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
                    onPressed: _refreshInvoices,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
          data: (invoices) {
            final monthInvoices = invoices.where(_inSelectedMonth).toList();
            final visible = _listWithCarryForward(invoices);
            final summary = _summary(
              monthInvoices: monthInvoices,
              allInvoices: invoices,
            );

            // Build one row per tenant from unpaid invoices (or paid-only when
            // the Paid filter is active).
            final sourceInvoices = switch (_filter) {
              _InvoiceStatusFilter.paid =>
                monthInvoices.where((i) => _status(i) == 'paid').toList(),
              _InvoiceStatusFilter.pending => visible
                  .where((i) {
                    final s = _status(i);
                    return s == 'pending' ||
                        s == 'partial' ||
                        s == 'partially_paid';
                  })
                  .toList(),
              _InvoiceStatusFilter.overdue =>
                visible.where((i) => _status(i) == 'overdue').toList(),
              _InvoiceStatusFilter.all =>
                visible.where(_isOpenUnpaid).toList(),
            };

            final tenantGroups = _filterTenantGroups(
              _groupByTenant(sourceInvoices)
                ..forEach((g) {
                  g._filterIsPaidView = _filter == _InvoiceStatusFilter.paid;
                }),
            );

            final unpaidVisible = visible.where(_isOpenUnpaid).toList();
            final allCount = _groupByTenant(unpaidVisible).length;
            final pendingCount = _groupByTenant(
              unpaidVisible.where((i) {
                final s = _status(i);
                return s == 'pending' ||
                    s == 'partial' ||
                    s == 'partially_paid';
              }).toList(),
            ).length;
            final overdueCount = _groupByTenant(
              unpaidVisible.where((i) => _status(i) == 'overdue').toList(),
            ).length;
            final paidCount = _groupByTenant(
              monthInvoices.where((i) => _status(i) == 'paid').toList(),
            ).length;

            final hasAnyInvoices = invoices.isNotEmpty;
            final hasVisibleInvoices = tenantGroups.isNotEmpty;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: _PaymentsHeader(
                    monthLabel: _monthFormat.format(_selectedMonth),
                    onMonthTap: _pickMonth,
                    onNewInvoice: _openNewInvoice,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: _CollectionSummaryCard(summary: summary),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: _SearchFilterRow(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _searchQuery = v),
                    onFilterTap: () {},
                  ),
                ),
                const SizedBox(height: 10),
                _StatusFilterPills(
                  allCount: allCount,
                  pendingCount: pendingCount,
                  paidCount: paidCount,
                  overdueCount: overdueCount,
                  selected: _filter,
                  onSelected: (f) => setState(() => _filter = f),
                ),
                const SizedBox(height: 6),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: _TableHeaderRow(),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _refreshInvoices,
                    child: tenantGroups.isNotEmpty
                        ? ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.only(top: 4, bottom: 16),
                            itemCount: tenantGroups.length,
                            separatorBuilder: (_, __) => const Divider(
                              height: 1,
                              thickness: 1,
                              color: AppColors.hairline,
                              indent: 12,
                              endIndent: 12,
                            ),
                            itemBuilder: (context, i) => _TenantLedgerListRow(
                              group: tenantGroups[i],
                              baseUrl: baseUrl,
                              onTap: () => _openTenantLedger(
                                tenantGroups[i],
                                invoices,
                              ),
                            ),
                          )
                        : ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height:
                                    MediaQuery.of(context).size.height * 0.35,
                                child: _EmptyInvoices(
                                  onCreate: _openNewInvoice,
                                  hasAnyInvoices: hasAnyInvoices,
                                  hasMonthInvoices: hasVisibleInvoices,
                                  monthLabel:
                                      _monthFormat.format(_selectedMonth),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CollectionSummary {
  final double expected;
  final double collected;
  final double pending;
  final double percent;

  const _CollectionSummary({
    required this.expected,
    required this.collected,
    required this.pending,
    required this.percent,
  });
}

class _PaymentsHeader extends StatelessWidget {
  final String monthLabel;
  final VoidCallback onMonthTap;
  final VoidCallback onNewInvoice;

  const _PaymentsHeader({
    required this.monthLabel,
    required this.onMonthTap,
    required this.onNewInvoice,
  });

  @override
  Widget build(BuildContext context) {
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
                  color: AppColors.ink,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 6),
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
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.keyboard_arrow_down,
                          size: 18, color: AppColors.slate),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        ElevatedButton.icon(
          onPressed: onNewInvoice,
          style: ElevatedButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          icon: const Icon(Icons.add, size: 18),
          label: const Text(
            'New Invoice',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

class _CollectionSummaryCard extends StatelessWidget {
  final _CollectionSummary summary;

  const _CollectionSummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final currency = _InvoicesListScreenState._currency;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Collection Summary',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _SummaryMetric(
                    label: 'Expected',
                    value: currency.format(summary.expected),
                    valueColor: AppColors.ink,
                  ),
                ),
                Expanded(
                  child: _SummaryMetric(
                    label: 'Collected',
                    value: currency.format(summary.collected),
                    valueColor: AppColors.positive,
                  ),
                ),
                Expanded(
                  child: _SummaryMetric(
                    label: 'Pending (all time)',
                    value: currency.format(summary.pending),
                    valueColor: AppColors.caution,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: summary.percent / 100,
                minHeight: 8,
                backgroundColor: AppColors.canvas,
                valueColor: const AlwaysStoppedAnimation<Color>(_accent),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${summary.percent.toStringAsFixed(0)}% collected',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 11,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const _SummaryMetric({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: valueColor,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 11),
        ),
      ],
    );
  }
}

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
              hintStyle:
                  TextStyle(color: AppColors.slate.withValues(alpha: 0.8)),
              prefixIcon:
                  const Icon(Icons.search, color: AppColors.slate, size: 20),
              filled: true,
              fillColor: AppColors.canvas,
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
          color: AppColors.surface,
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
  final _InvoiceStatusFilter selected;
  final ValueChanged<_InvoiceStatusFilter> onSelected;

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
            selected: selected == _InvoiceStatusFilter.all,
            onTap: () => onSelected(_InvoiceStatusFilter.all),
          ),
          const SizedBox(width: 8),
          _FilterPill(
            label: 'Pending ($pendingCount)',
            dotColor: AppColors.caution,
            selected: selected == _InvoiceStatusFilter.pending,
            onTap: () => onSelected(_InvoiceStatusFilter.pending),
          ),
          const SizedBox(width: 8),
          _FilterPill(
            label: 'Paid ($paidCount)',
            dotColor: AppColors.positive,
            selected: selected == _InvoiceStatusFilter.paid,
            onTap: () => onSelected(_InvoiceStatusFilter.paid),
          ),
          const SizedBox(width: 8),
          _FilterPill(
            label: 'Overdue ($overdueCount)',
            dotColor: AppColors.danger,
            selected: selected == _InvoiceStatusFilter.overdue,
            onTap: () => onSelected(_InvoiceStatusFilter.overdue),
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
      color: selected ? _accent : AppColors.surface,
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

class _TableHeaderRow extends StatelessWidget {
  const _TableHeaderRow();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 12,
      color: AppColors.slate,
      fontWeight: FontWeight.w500,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: const [
          Expanded(flex: 3, child: Text('Tenant', style: style)),
          Expanded(flex: 2, child: Text('Dues', style: style)),
          Expanded(flex: 2, child: Text('Amount', style: style)),
          Expanded(flex: 2, child: Text('Status', style: style)),
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
  final List<Map<String, dynamic>> invoices;

  _TenantPaymentGroup({
    required this.tenancyId,
    required this.name,
    required this.room,
    required this.floor,
    required this.photoUrl,
    required this.invoices,
  });

  String get roomLabel {
    if (floor != null && floor!.trim().isNotEmpty) {
      final f = floor!.trim();
      return f.toLowerCase().contains('floor') ? '$room · $f' : '$room · $f Floor';
    }
    return room;
  }

  double _amount(Map<String, dynamic> inv) =>
      double.tryParse(
        (inv['total_amount'] ?? inv['totalAmount'])?.toString() ?? '',
      ) ??
      0;

  double _paid(Map<String, dynamic> inv) =>
      double.tryParse(
        (inv['paid_amount'] ?? inv['paidAmount'])?.toString() ?? '',
      ) ??
      0;

  String _status(Map<String, dynamic> inv) =>
      inv['status']?.toString().toLowerCase().trim() ?? 'pending';

  double get grandTotalPending {
    var sum = 0.0;
    for (final inv in invoices) {
      final s = _status(inv);
      if (s == 'paid') continue;
      sum += (_amount(inv) - _paid(inv)).clamp(0.0, double.infinity);
    }
    return sum;
  }

  int get unpaidMonthCount {
    final months = <String>{};
    for (final inv in invoices) {
      final s = _status(inv);
      if (s == 'paid') continue;
      if ((_amount(inv) - _paid(inv)) <= 0.009) continue;
      for (final key in ['period_start', 'periodStart', 'due_date', 'dueDate']) {
        final raw = inv[key]?.toString();
        if (raw == null) continue;
        final m = RegExp(r'^(\d{4})-(\d{2})').firstMatch(raw);
        if (m != null) {
          months.add('${m.group(1)}-${m.group(2)}');
          break;
        }
      }
    }
    return months.isEmpty ? invoices.where((i) => _status(i) != 'paid').length : months.length;
  }

  bool get hasOverdue =>
      invoices.any((i) => _status(i) == 'overdue');

  bool get hasPaid => invoices.any((i) => _status(i) == 'paid');

  String get displayStatus {
    if (hasOverdue) return 'overdue';
    if (grandTotalPending > 0) return 'pending';
    if (hasPaid) return 'paid';
    return 'pending';
  }

  String get duesSummary {
    if (_filterIsPaidView) {
      return '${invoices.length} paid invoice${invoices.length == 1 ? '' : 's'}';
    }
    final n = unpaidMonthCount;
    return '$n unpaid month${n == 1 ? '' : 's'}';
  }

  /// Set when this group was built for the Paid filter.
  bool _filterIsPaidView = false;
}

class _TenantLedgerListRow extends StatelessWidget {
  final _TenantPaymentGroup group;
  final String baseUrl;
  final VoidCallback onTap;

  const _TenantLedgerListRow({
    required this.group,
    required this.baseUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final photoUrl = _resolvePhoto(group.photoUrl, baseUrl);
    final initials = _initials(group.name);
    final amount = group.grandTotalPending > 0
        ? group.grandTotalPending
        : group.invoices.fold<double>(
            0,
            (s, i) =>
                s +
                (double.tryParse(
                      (i['total_amount'] ?? i['totalAmount'])?.toString() ??
                          '',
                    ) ??
                    0),
          );
    final status = group.displayStatus;

    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.canvas,
                      backgroundImage:
                          photoUrl != null ? NetworkImage(photoUrl) : null,
                      child: photoUrl == null
                          ? Text(
                              initials,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _accent,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 8),
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
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  group.duesSummary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  _InvoicesListScreenState._currency.format(amount),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: _InvoiceStatusBadge(status: status),
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: AppColors.slate,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _resolvePhoto(String? raw, String baseUrl) {
    if (raw == null || raw.trim().isEmpty) return null;
    if (raw.startsWith('http')) return raw;
    return '$baseUrl$raw';
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
        bg = AppColors.caution.withValues(alpha: 0.12);
        fg = AppColors.caution;
        label = 'Pending';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
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
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyInvoices extends StatelessWidget {
  final VoidCallback onCreate;
  final bool hasAnyInvoices;
  final bool hasMonthInvoices;
  final String monthLabel;

  const _EmptyInvoices({
    required this.onCreate,
    this.hasAnyInvoices = false,
    this.hasMonthInvoices = false,
    this.monthLabel = '',
  });

  @override
  Widget build(BuildContext context) {
    final title = !hasAnyInvoices
        ? 'No invoices found'
        : !hasMonthInvoices
            ? 'No invoices in $monthLabel'
            : 'No matching invoices';
    final subtitle = !hasAnyInvoices
        ? 'Create your first invoice to see it here.'
        : !hasMonthInvoices
            ? 'Invoices exist in other months. Try switching the month above.'
            : 'Try clearing search or status filters.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.receipt_long_outlined,
                size: 48, color: AppColors.slate),
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

String _initials(String name) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return '${parts.first[0]}${parts[1][0]}'.toUpperCase();
}
