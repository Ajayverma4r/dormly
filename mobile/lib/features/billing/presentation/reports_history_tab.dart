// features/billing/presentation/reports_history_tab.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../tenancies/data/tenancy_repository.dart';
import 'billing_invoice_helpers.dart';
import 'billing_providers.dart';
import 'invoice_detail_screen.dart';

const _accent = Color(0xFF7C3AED);

/// Analytics-oriented history: month filter, billed/collected, all invoices.
class ReportsHistoryTab extends ConsumerStatefulWidget {
  final String propertyId;

  const ReportsHistoryTab({super.key, required this.propertyId});

  @override
  ConsumerState<ReportsHistoryTab> createState() => _ReportsHistoryTabState();
}

class _ReportsHistoryTabState extends ConsumerState<ReportsHistoryTab> {
  late DateTime _selectedMonth;

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
    await ref.read(invoicesProvider(widget.propertyId).future);
  }

  Future<void> _openInvoice(Map<String, dynamic> inv) async {
    final id = (inv['id'] ?? inv['invoice_id'])?.toString();
    if (id == null || id.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InvoiceDetailScreen(
          propertyId: widget.propertyId,
          invoiceId: id,
          viewOnly: true,
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _invoicesForMonth(
    List<Map<String, dynamic>> all,
  ) {
    final filtered = all
        .where((inv) => invoiceMatchesMonth(inv, _selectedMonth))
        .toList()
      ..sort((a, b) {
        final an = tenantDisplayName(a).toLowerCase();
        final bn = tenantDisplayName(b).toLowerCase();
        final byName = an.compareTo(bn);
        if (byName != 0) return byName;
        return invoiceTotalAmount(b).compareTo(invoiceTotalAmount(a));
      });
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final invoicesAsync = ref.watch(invoicesProvider(widget.propertyId));
    final baseUrl = ref.watch(tenancyRepositoryProvider).baseUrl;
    final monthLabel = DateFormat('MMMM yyyy').format(_selectedMonth);
    final shortMonth = DateFormat('MMM').format(_selectedMonth);

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
        final monthInvoices = _invoicesForMonth(invoices);
        final billed = monthInvoices.fold<double>(
          0,
          (s, i) => s + invoiceTotalAmount(i),
        );
        final collected = monthInvoices.fold<double>(
          0,
          (s, i) => s + invoicePaidAmount(i),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _MonthYearPicker(
                selected: _selectedMonth,
                options: _monthOptions,
                onChanged: (m) => setState(() => _selectedMonth = m),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: _ReportSummaryTile(
                      label: 'Total Billed in $shortMonth',
                      value: billingCurrency.format(billed),
                      valueColor: AppColors.blueprint,
                      icon: Icons.receipt_long_outlined,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ReportSummaryTile(
                      label: 'Total Collected in $shortMonth',
                      value: billingCurrency.format(collected),
                      valueColor: AppColors.positive,
                      icon: Icons.account_balance_wallet_outlined,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Text(
                'Invoices · $monthLabel',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: _ReportTableHeader(),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: monthInvoices.isNotEmpty
                    ? ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(top: 4, bottom: 16),
                        itemCount: monthInvoices.length,
                        separatorBuilder: (_, __) => const Divider(
                          height: 1,
                          thickness: 1,
                          color: AppColors.hairline,
                          indent: 12,
                          endIndent: 12,
                        ),
                        itemBuilder: (context, i) {
                          final inv = monthInvoices[i];
                          return _InvoiceHistoryRow(
                            invoice: inv,
                            baseUrl: baseUrl,
                            onTap: () => _openInvoice(inv),
                          );
                        },
                      )
                    : ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height:
                                MediaQuery.of(context).size.height * 0.32,
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.inbox_outlined,
                                      size: 48,
                                      color: AppColors.slate,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No invoices for $monthLabel',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Pick another month or create invoices for this period.',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MonthYearPicker extends StatelessWidget {
  final DateTime selected;
  final List<DateTime> options;
  final ValueChanged<DateTime> onChanged;

  const _MonthYearPicker({
    required this.selected,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.hairline),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<DateTime>(
          isExpanded: true,
          value: options.firstWhere(
            (o) => o.year == selected.year && o.month == selected.month,
            orElse: () => options.first,
          ),
          icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.slate),
          items: options
              .map(
                (m) => DropdownMenuItem(
                  value: m,
                  child: Text(
                    DateFormat('MMMM yyyy').format(m),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: (m) {
            if (m != null) onChanged(m);
          },
        ),
      ),
    );
  }
}

class _ReportSummaryTile extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final IconData icon;

  const _ReportSummaryTile({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: valueColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.slate,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: valueColor,
                ),
          ),
        ],
      ),
    );
  }
}

class _ReportTableHeader extends StatelessWidget {
  const _ReportTableHeader();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 12,
      color: AppColors.slate,
      fontWeight: FontWeight.w500,
    );
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('Tenant', style: style)),
          Expanded(flex: 2, child: Text('Period', style: style)),
          Expanded(flex: 2, child: Text('Amount', style: style)),
          Expanded(flex: 2, child: Text('Status', style: style)),
        ],
      ),
    );
  }
}

class _InvoiceHistoryRow extends StatelessWidget {
  final Map<String, dynamic> invoice;
  final String baseUrl;
  final VoidCallback onTap;

  const _InvoiceHistoryRow({
    required this.invoice,
    required this.baseUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = tenantDisplayName(invoice);
    final room = tenantRoomLabel(invoice);
    final photoUrl = resolvePhotoUrl(tenantPhotoUrl(invoice), baseUrl);
    final initials = initialsFromName(name);
    final status = invoiceStatus(invoice);
    final amount = invoiceTotalAmount(invoice);

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
                            name,
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
                            room,
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
                  periodLabel(invoice),
                  maxLines: 1,
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
                  billingCurrency.format(amount),
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
                    Flexible(child: _StatusBadge(status: status)),
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
}

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

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
      case 'partially_paid':
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
