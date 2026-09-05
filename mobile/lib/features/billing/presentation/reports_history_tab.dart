// features/billing/presentation/reports_history_tab.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import 'billing_invoice_helpers.dart';
import 'billing_providers.dart';
import 'invoice_detail_screen.dart';

/// CA Ledger View: financial-year aggregates + month-by-month cash breakdown.
class ReportsHistoryTab extends ConsumerStatefulWidget {
  final String propertyId;

  const ReportsHistoryTab({super.key, required this.propertyId});

  @override
  ConsumerState<ReportsHistoryTab> createState() => _ReportsHistoryTabState();
}

class _ReportsHistoryTabState extends ConsumerState<ReportsHistoryTab> {
  late FinancialYear _selectedFy;

  @override
  void initState() {
    super.initState();
    _selectedFy = FinancialYear.current();
  }

  List<FinancialYear> get _fyOptions => FinancialYear.recent();

  Future<void> _refresh() async {
    ref.invalidate(invoicesProvider(widget.propertyId));
    ref.invalidate(paymentsProvider(widget.propertyId));
    await Future.wait([
      ref.read(invoicesProvider(widget.propertyId).future),
      ref.read(paymentsProvider(widget.propertyId).future),
    ]);
  }

  void _onDownloadReport() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Generating CA Report CSV...')),
    );
  }

  Future<void> _openInvoice(String? invoiceId) async {
    if (invoiceId == null || invoiceId.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InvoiceDetailScreen(
          propertyId: widget.propertyId,
          invoiceId: invoiceId,
          viewOnly: true,
        ),
      ),
    );
  }

  List<CaPaymentEntry> _resolvePaymentEntries({
    required List<Map<String, dynamic>> apiPayments,
    required List<Map<String, dynamic>> invoices,
  }) {
    final fromApi = apiPayments
        .map(caPaymentFromApiRow)
        .whereType<CaPaymentEntry>()
        .toList();
    if (fromApi.isNotEmpty) return fromApi;
    return synthesizePaymentsFromInvoices(invoices);
  }

  @override
  Widget build(BuildContext context) {
    final invoicesAsync = ref.watch(invoicesProvider(widget.propertyId));
    final paymentsAsync = ref.watch(paymentsProvider(widget.propertyId));

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
        final apiPayments = paymentsAsync.maybeWhen(
          data: (p) => p,
          orElse: () => <Map<String, dynamic>>[],
        );
        final entries = _resolvePaymentEntries(
          apiPayments: apiPayments,
          invoices: invoices,
        );

        final fyInvoices =
            invoices.where((i) => invoiceInFinancialYear(i, _selectedFy));
        final totalBilled = fyInvoices.fold<double>(
          0,
          (s, i) => s + invoiceTotalAmount(i),
        );
        final fyPayments =
            entries.where((e) => _selectedFy.containsDate(e.paidAt)).toList();
        final totalCashIn =
            fyPayments.fold<double>(0, (s, e) => s + e.amount);
        final monthGroups =
            groupPaymentsByMonthForFy(fyPayments, _selectedFy);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _FyFilterBar(
                selected: _selectedFy,
                options: _fyOptions,
                onChanged: (fy) => setState(() => _selectedFy = fy),
                onDownload: _onDownloadReport,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: _AggregateCard(
                      label: 'Total Cash In',
                      value: billingCurrency.format(totalCashIn),
                      valueColor: AppColors.positive,
                      icon: Icons.south_west,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _AggregateCard(
                      label: 'Total Billed',
                      value: billingCurrency.format(totalBilled),
                      valueColor: AppColors.ink,
                      icon: Icons.receipt_long_outlined,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                'Month-by-Month Breakdown',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: monthGroups.isNotEmpty
                    ? ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                        itemCount: monthGroups.length,
                        itemBuilder: (context, i) {
                          final group = monthGroups[i];
                          return _MonthAccordion(
                            group: group,
                            onPaymentTap: (entry) =>
                                _openInvoice(entry.invoiceId),
                          );
                        },
                      )
                    : ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.32,
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.account_balance_outlined,
                                      size: 48,
                                      color: AppColors.slate,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No ledger activity for ${_selectedFy.label}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Payments collected in this financial year will appear here month by month.',
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

class _FyFilterBar extends StatelessWidget {
  final FinancialYear selected;
  final List<FinancialYear> options;
  final ValueChanged<FinancialYear> onChanged;
  final VoidCallback onDownload;

  const _FyFilterBar({
    required this.selected,
    required this.options,
    required this.onChanged,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.hairline),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<FinancialYear>(
                isExpanded: true,
                value: options.contains(selected) ? selected : options.first,
                icon: const Icon(
                  Icons.keyboard_arrow_down,
                  color: AppColors.slate,
                ),
                items: options
                    .map(
                      (fy) => DropdownMenuItem(
                        value: fy,
                        child: Text(
                          fy.label,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (fy) {
                  if (fy != null) onChanged(fy);
                },
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: onDownload,
          icon: const Icon(Icons.file_download, size: 18),
          label: const Text(
            'Download Report',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.blueprint,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          ),
        ),
      ],
    );
  }
}

class _AggregateCard extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final IconData icon;

  const _AggregateCard({
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
                  maxLines: 1,
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

class _MonthAccordion extends StatelessWidget {
  final CaMonthGroup group;
  final ValueChanged<CaPaymentEntry> onPaymentTap;

  const _MonthAccordion({
    required this.group,
    required this.onPaymentTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.only(bottom: 6),
          title: Text(
            group.title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: AppColors.ink,
            ),
          ),
          trailing: Text(
            'Total: ${billingCurrency.format(group.totalCollected)}',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: AppColors.positive,
            ),
          ),
          children: [
            for (final entry in group.payments)
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                title: Text(
                  entry.tenantName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppColors.ink,
                  ),
                ),
                subtitle: Text(
                  entry.roomLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.slate),
                ),
                trailing: Text(
                  billingCurrency.format(entry.amount),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppColors.ink,
                  ),
                ),
                onTap: () => onPaymentTap(entry),
              ),
          ],
        ),
      ),
    );
  }
}
