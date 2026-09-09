// features/billing/presentation/billing_insights_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../dashboard/presentation/property_dashboard_provider.dart';
import '../../tenancies/presentation/residents_list_screen.dart'
    show propertyResidentsProvider;
import '../data/billing_repository.dart';
import 'billing_invoice_helpers.dart';
import 'billing_providers.dart';
import 'create_invoice_screen.dart';
import 'invoice_detail_screen.dart';

const _accent = AppColors.primary;
const _unpaidOrange = Color(0xFFD97706);

final _currency =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

Future<void> showBillingInsightsSheet({
  required BuildContext context,
  required String propertyId,
  required double billedThisMonth,
  VoidCallback? onGenerateInvoice,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => BillingInsightsSheet(
      propertyId: propertyId,
      billedThisMonth: billedThisMonth,
      onGenerateInvoice: onGenerateInvoice,
    ),
  );
}

void _goToCreateInvoice(
  BuildContext context, {
  required String propertyId,
  VoidCallback? onGenerateInvoice,
}) {
  final nav = Navigator.of(context, rootNavigator: true);
  Navigator.pop(context);
  if (onGenerateInvoice != null) {
    onGenerateInvoice();
    return;
  }
  nav.push(
    MaterialPageRoute(
      builder: (_) => CreateInvoiceScreen(propertyId: propertyId),
    ),
  );
}

class BillingInsightsSheet extends ConsumerStatefulWidget {
  final String propertyId;
  final double billedThisMonth;
  final VoidCallback? onGenerateInvoice;

  const BillingInsightsSheet({
    super.key,
    required this.propertyId,
    required this.billedThisMonth,
    this.onGenerateInvoice,
  });

  @override
  ConsumerState<BillingInsightsSheet> createState() =>
      _BillingInsightsSheetState();
}

class _BillingInsightsSheetState extends ConsumerState<BillingInsightsSheet> {
  String currentFilter = 'All';

  void _toggleFilter(String filter) {
    setState(() {
      currentFilter = currentFilter == filter ? 'All' : filter;
    });
  }

  List<_RecentInvoice> _applyFilter(List<_RecentInvoice> invoices) {
    switch (currentFilter) {
      case 'Collected':
        return invoices.where((i) => i.hasCollection).toList();
      case 'Unpaid':
        return invoices.where((i) => i.hasUnpaid).toList();
      default:
        return invoices;
    }
  }

  String _emptyListLabel() {
    switch (currentFilter) {
      case 'Collected':
        return 'No paid invoices this month.';
      case 'Unpaid':
        return 'No unpaid invoices this month.';
      default:
        return 'No invoices generated this month.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final invoicesAsync = ref.watch(invoicesProvider(widget.propertyId));
    final tenanciesAsync = ref.watch(propertyResidentsProvider(widget.propertyId));
    final now = DateTime.now();
    final month = DateTime(now.year, now.month);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.68,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        final invoices = invoicesAsync.maybeWhen(
          data: (rows) => rows,
          orElse: () => const <Map<String, dynamic>>[],
        );
        final tenancies = tenanciesAsync.maybeWhen(
          data: (rows) => rows,
          orElse: () => const <Map<String, dynamic>>[],
        );
        final allRecent = _recentInvoices(invoices, month);
        final split = _StatusSplit(
          collected: allRecent.fold<double>(0, (s, i) => s + i.paidAmount),
          unpaid: allRecent.fold<double>(0, (s, i) => s + i.remaining),
        );
        final billedLive =
            allRecent.fold<double>(0, (s, i) => s + i.amount);
        final billedDisplay = invoicesAsync.hasValue
            ? billedLive
            : widget.billedThisMonth;
        final recent = _applyFilter(allRecent);
        final unbilledCount = _unbilledCount(
          invoices: invoices,
          tenancies: tenancies,
          month: month,
          invoicesReady: invoicesAsync.hasValue,
          tenanciesReady: tenanciesAsync.hasValue,
        );

        return Material(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: CustomScrollView(
              controller: scrollController,
              slivers: [
                const SliverToBoxAdapter(child: SizedBox(height: 10)),
                SliverToBoxAdapter(
                  child: Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.hairline,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 14, 20, 0),
                    child: Text(
                      'Billing Health - This Month',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 2, 20, 4),
                    child: Text(
                      '${_currency.format(billedDisplay)} billed',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.slate,
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: _StatusSplitRow(
                      collected: split.collected,
                      unpaid: split.unpaid,
                      currentFilter: currentFilter,
                      onCollectedTap: () => _toggleFilter('Collected'),
                      onUnpaidTap: () => _toggleFilter('Unpaid'),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    child: _UnbilledAlert(
                      count: unbilledCount,
                      onGenerateInvoice: () => _goToCreateInvoice(
                        context,
                        propertyId: widget.propertyId,
                        onGenerateInvoice: widget.onGenerateInvoice,
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Divider(height: 1),
                  ),
                ),
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
                    child: Text(
                      'Recently Generated',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.slate,
                      ),
                    ),
                  ),
                ),
                if (invoicesAsync.isLoading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _accent,
                        ),
                      ),
                    ),
                  )
                else if (recent.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                      child: Text(
                        _emptyListLabel(),
                        style: const TextStyle(color: AppColors.slate),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                    sliver: SliverList.builder(
                      itemCount: recent.length,
                      itemBuilder: (context, i) => _InvoiceTile(
                        invoice: recent[i],
                        propertyId: widget.propertyId,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatusSplitRow extends StatelessWidget {
  final double collected;
  final double unpaid;
  final String currentFilter;
  final VoidCallback onCollectedTap;
  final VoidCallback onUnpaidTap;

  const _StatusSplitRow({
    required this.collected,
    required this.unpaid,
    required this.currentFilter,
    required this.onCollectedTap,
    required this.onUnpaidTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SplitChip(
            label: 'Collected',
            amount: collected,
            color: AppColors.positive,
            bg: const Color(0xFFDCFCE7),
            selected: currentFilter == 'Collected',
            dimmed: currentFilter == 'Unpaid',
            onTap: onCollectedTap,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SplitChip(
            label: 'Unpaid',
            amount: unpaid,
            color: _unpaidOrange,
            bg: const Color(0xFFFEF3C7),
            selected: currentFilter == 'Unpaid',
            dimmed: currentFilter == 'Collected',
            onTap: onUnpaidTap,
          ),
        ),
      ],
    );
  }
}

class _SplitChip extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  final Color bg;
  final bool selected;
  final bool dimmed;
  final VoidCallback onTap;

  const _SplitChip({
    required this.label,
    required this.amount,
    required this.color,
    required this.bg,
    required this.selected,
    required this.dimmed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: dimmed ? 0.55 : 1,
      child: Material(
        color: bg,
        elevation: selected ? 2 : 0,
        shadowColor: color.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? color : Colors.transparent,
                width: 2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _currency.format(amount),
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UnbilledAlert extends StatelessWidget {
  final int count;
  final VoidCallback onGenerateInvoice;

  const _UnbilledAlert({
    required this.count,
    required this.onGenerateInvoice,
  });

  @override
  Widget build(BuildContext context) {
    if (count <= 0) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: onGenerateInvoice,
          style: TextButton.styleFrom(
            foregroundColor: _accent,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
          child: const Text(
            '+ Generate Invoice',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      );
    }

    final noun = count == 1 ? 'tenant' : 'tenants';
    final verb = count == 1 ? "hasn't" : "haven't";

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF9C3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '⚠️ $count active $noun $verb been billed this month.',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
              height: 1.35,
            ),
          ),
          TextButton(
            onPressed: onGenerateInvoice,
            style: TextButton.styleFrom(
              foregroundColor: _accent,
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text(
              '+ Generate Invoice',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoiceTile extends ConsumerWidget {
  final _RecentInvoice invoice;
  final String propertyId;

  const _InvoiceTile({
    required this.invoice,
    required this.propertyId,
  });

  bool get _isMock => invoice.id.isEmpty;

  Future<void> _onTap(BuildContext context, WidgetRef ref) async {
    final action = await showDialog<InvoiceQuickAction>(
      context: context,
      builder: (ctx) => InvoiceQuickActionDialog(
        tenantName: invoice.tenantName,
      ),
    );
    if (action == null || !context.mounted) return;

    switch (action) {
      case InvoiceQuickAction.recordPayment:
        await _recordPayment(context, ref);
      case InvoiceQuickAction.sendReminder:
        await _sendReminder(context, ref);
      case InvoiceQuickAction.viewDetails:
        _viewDetails(context);
    }
  }

  Future<void> _recordPayment(BuildContext context, WidgetRef ref) async {
    if (_isMock) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Record payment is not available for this demo invoice')),
      );
      return;
    }
    if (invoice.remaining <= 0.009) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This invoice is already paid')),
      );
      return;
    }

    final controller =
        TextEditingController(text: invoice.remaining.toStringAsFixed(0));
    final amount = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Record Payment'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            prefixText: '₹ ',
            labelText: 'Amount received',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, double.tryParse(controller.text.trim())),
            style: FilledButton.styleFrom(backgroundColor: _accent),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (amount == null || amount <= 0 || !context.mounted) return;

    final pay =
        amount > invoice.remaining ? invoice.remaining : amount;
    try {
      await ref.read(billingRepositoryProvider).recordPayment(
            propertyId,
            invoice.id,
            pay,
            'cash',
          );
      ref.invalidate(invoicesProvider(propertyId));
      ref.invalidate(propertyDashboardProvider(propertyId));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Recorded ${_currency.format(pay)}'),
          backgroundColor: AppColors.positive,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not record payment: $e')),
      );
    }
  }

  Future<void> _sendReminder(BuildContext context, WidgetRef ref) async {
    if (!_isMock) {
      try {
        await ref
            .read(billingRepositoryProvider)
            .sendReminder(propertyId, invoice.id);
      } catch (_) {
        // Still confirm in the UI — reminder copy is the product action.
      }
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('WhatsApp reminder sent!')),
    );
  }

  void _viewDetails(BuildContext context) {
    if (_isMock) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invoice details are not available for this demo invoice')),
      );
      return;
    }
    final nav = Navigator.of(context, rootNavigator: true);
    Navigator.pop(context);
    nav.push(
      MaterialPageRoute(
        builder: (_) => InvoiceDetailScreen(
          propertyId: propertyId,
          invoiceId: invoice.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _onTap(context, ref),
        child: ListTile(
          dense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          title: Text(
            invoice.tenantName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
              fontSize: 14,
            ),
          ),
          subtitle: Text(
            _currency.format(invoice.amount),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.slate,
            ),
          ),
          trailing: _StatusChip(status: invoice.status),
        ),
      ),
    );
  }
}

enum InvoiceQuickAction { recordPayment, sendReminder, viewDetails }

class InvoiceQuickActionDialog extends StatelessWidget {
  final String tenantName;

  const InvoiceQuickActionDialog({
    super.key,
    required this.tenantName,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        'Manage Invoice - $tenantName',
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: AppColors.ink,
        ),
      ),
      contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.payment, color: AppColors.positive),
            title: const Text('Record Payment'),
            onTap: () =>
                Navigator.pop(context, InvoiceQuickAction.recordPayment),
          ),
          ListTile(
            leading: const Icon(Icons.message, color: _accent),
            title: const Text('Send Reminder'),
            onTap: () =>
                Navigator.pop(context, InvoiceQuickAction.sendReminder),
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long, color: AppColors.slate),
            title: const Text('View Details'),
            onTap: () =>
                Navigator.pop(context, InvoiceQuickAction.viewDetails),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final paid = status == 'paid';
    final partial = status == 'partial' || status == 'partially_paid';
    final overdue = status == 'overdue';
    final color = paid
        ? AppColors.positive
        : overdue
            ? AppColors.danger
            : _unpaidOrange;
    final bg = paid
        ? const Color(0xFFDCFCE7)
        : overdue
            ? const Color(0xFFFEE2E2)
            : const Color(0xFFFEF3C7);
    final label = paid
        ? 'Paid'
        : overdue
            ? 'Overdue'
            : partial
                ? 'Partial'
                : 'Pending';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _RecentInvoice {
  final String id;
  final String tenantName;
  final double amount;
  final double paidAmount;
  final double remaining;
  final String status;

  const _RecentInvoice({
    required this.id,
    required this.tenantName,
    required this.amount,
    required this.paidAmount,
    required this.remaining,
    required this.status,
  });

  bool get hasCollection => paidAmount > 0.009;

  bool get hasUnpaid => remaining > 0.009;
}

class _StatusSplit {
  final double collected;
  final double unpaid;
  const _StatusSplit({required this.collected, required this.unpaid});
}

bool _createdThisMonth(Map<String, dynamic> inv, DateTime month) {
  for (final key in ['created_at', 'createdAt']) {
    final raw = inv[key]?.toString().trim();
    if (raw == null || raw.isEmpty) continue;
    final d = DateTime.tryParse(raw)?.toLocal();
    if (d != null) {
      return d.year == month.year && d.month == month.month;
    }
  }
  return invoiceMatchesMonth(inv, month);
}

bool _invoiceInSheetMonth(Map<String, dynamic> inv, DateTime month) {
  return _createdThisMonth(inv, month) || invoiceMatchesMonth(inv, month);
}

List<_RecentInvoice> _recentInvoices(
  List<Map<String, dynamic>> invoices,
  DateTime month,
) {
  final monthInvoices = invoices
      .where((inv) => _invoiceInSheetMonth(inv, month))
      .map((inv) {
        final rawStatus = inv['status']?.toString() ?? '';
        final status = invoiceStatus(inv);
        final paid = invoicePaidAmount(inv);
        final remaining = invoiceRemaining(inv);
        final total = invoiceTotalAmount(inv);
        debugPrint(
          '[BillingInsights] id=${inv['id']} tenant=${tenantDisplayName(inv)} '
          'rawStatus="$rawStatus" status=$status total=$total '
          'paid=$paid remaining=$remaining',
        );
        return _RecentInvoice(
          id: (inv['id'] ?? '').toString(),
          tenantName: tenantDisplayName(inv),
          amount: total,
          paidAmount: paid,
          remaining: remaining,
          status: status,
        );
      })
      .toList();
  debugPrint(
    '[BillingInsights] month invoices=${monthInvoices.length} '
    'collected=${monthInvoices.fold<double>(0, (s, i) => s + i.paidAmount)} '
    'unpaid=${monthInvoices.fold<double>(0, (s, i) => s + i.remaining)}',
  );
  return monthInvoices;
}

int _unbilledCount({
  required List<Map<String, dynamic>> invoices,
  required List<Map<String, dynamic>> tenancies,
  required DateTime month,
  required bool invoicesReady,
  required bool tenanciesReady,
}) {
  if (!invoicesReady || !tenanciesReady) return 0;
  if (tenancies.isEmpty) return 0;

  final billedIds = <String>{};
  for (final inv in invoices) {
    if (!_invoiceInSheetMonth(inv, month)) continue;
    final id = (inv['tenancy_id'] ?? inv['tenancyId'])?.toString();
    if (id != null && id.isNotEmpty) billedIds.add(id);
  }

  var unbilled = 0;
  for (final t in tenancies) {
    final status = (t['status'] ?? 'active').toString().toLowerCase();
    if (status != 'active') continue;
    final id = (t['id'] ?? t['tenancy_id'] ?? t['tenancyId'])?.toString();
    if (id == null || id.isEmpty) continue;
    if (!billedIds.contains(id)) unbilled++;
  }
  return unbilled;
}
