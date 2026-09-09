// features/billing/presentation/collection_breakdown_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import 'billing_invoice_helpers.dart';
import 'billing_providers.dart';
import 'invoice_detail_screen.dart';
import 'whatsapp_reminder.dart';

const _accent = AppColors.primary;

final _dayFormat = DateFormat('d MMM');
final _fullDateFormat = DateFormat('d MMMM yyyy');

Future<void> showCollectionBreakdownSheet({
  required BuildContext context,
  required String propertyId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => CollectionBreakdownSheet(propertyId: propertyId),
  );
}

class CollectionBreakdownSheet extends ConsumerWidget {
  final String propertyId;

  const CollectionBreakdownSheet({super.key, required this.propertyId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(paymentsProvider(propertyId));
    final now = DateTime.now();
    final month = DateTime(now.year, now.month);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.68,
      minChildSize: 0.42,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        final payments = async.maybeWhen(
          data: (rows) => _paymentsForMonth(rows, month),
          orElse: () => const <_CollectionPayment>[],
        );
        final loading = async.isLoading;
        final loadError = async.hasError;

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
                    padding: EdgeInsets.fromLTRB(20, 14, 20, 4),
                    child: Text(
                      "This Month's Collections",
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
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                    child: _SplitSummaryRow(payments: payments),
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
                      'Recent transactions',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.slate,
                      ),
                    ),
                  ),
                ),
                if (loading)
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
                else if (loadError)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyCollections(
                      message: 'Could not load collections. Pull to close and try again.',
                    ),
                  )
                else if (payments.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyCollections(),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                    sliver: SliverList.builder(
                      itemCount: payments.length,
                      itemBuilder: (context, i) => _CollectionTile(
                        payment: payments[i],
                        propertyId: propertyId,
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

class _SplitSummaryRow extends StatelessWidget {
  final List<_CollectionPayment> payments;

  const _SplitSummaryRow({required this.payments});

  @override
  Widget build(BuildContext context) {
    var cash = 0.0;
    var online = 0.0;
    for (final p in payments) {
      if (p.isCash) {
        cash += p.amount;
      } else {
        online += p.amount;
      }
    }

    return Row(
      children: [
        Expanded(
          child: _SplitChip(
            label: 'Cash',
            amount: cash,
            color: AppColors.positive,
            bg: const Color(0xFFDCFCE7),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SplitChip(
            label: 'Online/UPI',
            amount: online,
            color: _accent,
            bg: AppColors.primarySoft,
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

  const _SplitChip({
    required this.label,
    required this.amount,
    required this.color,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            billingCurrency.format(amount),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _CollectionTile extends StatelessWidget {
  final _CollectionPayment payment;
  final String propertyId;

  const _CollectionTile({
    required this.payment,
    required this.propertyId,
  });

  void _sendReceipt(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Receipt sent to WhatsApp'),
        backgroundColor: whatsAppGreen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showTransactionDetailDialog(
          context,
          payment: payment,
          propertyId: propertyId,
        ),
        child: ListTile(
          dense: true,
          contentPadding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
          title: Text(
            payment.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
              fontSize: 14,
            ),
          ),
          subtitle: Text(
            '${_dayFormat.format(payment.paidAt)} · ${payment.paidViaLabel}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppColors.slate),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                billingCurrency.format(payment.amount),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppColors.positive,
                  fontSize: 14,
                ),
              ),
              IconButton(
                tooltip: 'Send rent receipt',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: () => _sendReceipt(context),
                icon: const Icon(Icons.chat, color: whatsAppGreen, size: 22),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showTransactionDetailDialog(
  BuildContext context, {
  required _CollectionPayment payment,
  required String propertyId,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _TransactionDetailDialog(
      payment: payment,
      propertyId: propertyId,
    ),
  );
}

class _TransactionDetailDialog extends ConsumerWidget {
  final _CollectionPayment payment;
  final String propertyId;

  const _TransactionDetailDialog({
    required this.payment,
    required this.propertyId,
  });

  void _close(BuildContext context) => Navigator.pop(context);

  void _viewInvoice(BuildContext context) {
    final id = payment.invoiceId;
    if (id == null || id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No invoice linked to this payment')),
      );
      return;
    }
    final nav = Navigator.of(context, rootNavigator: true);
    Navigator.pop(context);
    nav.push(
      MaterialPageRoute(
        builder: (_) => InvoiceDetailScreen(
          propertyId: propertyId,
          invoiceId: id,
          viewOnly: true,
        ),
      ),
    );
  }

  Future<void> _revertPayment(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revert this payment?'),
        content: const Text(
          'This will mark the collection as entered by mistake. '
          'This demo does not change saved records yet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Revert'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Payment reverted')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoiceId = payment.invoiceId;
    final invoiceAsync = invoiceId != null && invoiceId.isNotEmpty
        ? ref.watch(invoiceDetailProvider((propertyId, invoiceId)))
        : null;
    final loadingLines = invoiceAsync?.isLoading == true;
    final lines = invoiceAsync == null
        ? [_BreakdownLine('Payment', payment.amount)]
        : invoiceAsync.maybeWhen(
            data: (invoice) {
              final parsed = _linesFromInvoice(invoice);
              return parsed.isEmpty
                  ? [_BreakdownLine('Payment', payment.amount)]
                  : parsed;
            },
            orElse: () => const <_BreakdownLine>[],
          );

    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8, right: 8),
                    child: Text(
                      payment.tenantName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Revert payment',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _revertPayment(context),
                  icon: Icon(
                    Icons.undo_rounded,
                    size: 20,
                    color: AppColors.danger.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                billingCurrency.format(payment.amount),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.positive,
                ),
              ),
            ),
            if (payment.roomLabel.trim().isNotEmpty &&
                payment.roomLabel.trim() != '—') ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  payment.roomLabel,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.slate,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Text(
                'What this payment covers',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.slate,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: loadingLines
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _accent,
                          ),
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        for (final line in lines)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    line.label,
                                    style: const TextStyle(
                                      color: AppColors.ink,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Text(
                                  billingCurrency.format(line.amount),
                                  style: const TextStyle(
                                    color: AppColors.ink,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(0, 12, 8, 12),
              child: Divider(height: 1),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                payment.paidViaLabel,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                _fullDateFormat.format(payment.paidAt),
                style: const TextStyle(color: AppColors.slate),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(
                  onPressed: () => _viewInvoice(context),
                  style: TextButton.styleFrom(foregroundColor: _accent),
                  child: const Text('View Invoice'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => _close(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Close'),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class _BreakdownLine {
  final String label;
  final double amount;
  const _BreakdownLine(this.label, this.amount);
}

List<_BreakdownLine> _linesFromInvoice(Map<String, dynamic> invoice) {
  final raw = invoice['lineItems'] ?? invoice['line_items'];
  if (raw is! List) return const [];
  final lines = <_BreakdownLine>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final map = Map<String, dynamic>.from(item);
    final label =
        (map['description'] ?? map['name'] ?? map['title'] ?? '').toString();
    final amount = double.tryParse(
          (map['amount'] ?? map['total'] ?? 0).toString(),
        ) ??
        0;
    if (label.trim().isEmpty) continue;
    lines.add(_BreakdownLine(label, amount));
  }
  return lines;
}

class _EmptyCollections extends StatelessWidget {
  final String message;
  const _EmptyCollections({
    this.message = 'No collections recorded this month.',
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.slate),
        ),
      ),
    );
  }
}

class _CollectionPayment {
  final String id;
  final String? invoiceId;
  final String tenantName;
  final String roomLabel;
  final double amount;
  final DateTime paidAt;
  final String method;

  const _CollectionPayment({
    required this.id,
    this.invoiceId,
    required this.tenantName,
    required this.roomLabel,
    required this.amount,
    required this.paidAt,
    required this.method,
  });

  bool get isCash => method == 'cash';

  String get title {
    final room = roomLabel.trim();
    if (room.isEmpty || room == '—') return tenantName;
    return '$tenantName - $room';
  }

  String get paidViaLabel {
    switch (method) {
      case 'cash':
        return 'Paid via Cash';
      case 'upi':
        return 'Paid via UPI';
      case 'online':
        return 'Paid via Online';
      default:
        if (method.isEmpty) return 'Paid via Cash';
        final label = method[0].toUpperCase() + method.substring(1);
        return 'Paid via $label';
    }
  }
}

String _normalizeMethod(String? raw) {
  final m = (raw ?? '').toLowerCase().trim();
  if (m.isEmpty || m.contains('cash')) return 'cash';
  if (m.contains('upi')) return 'upi';
  if (m.contains('card') ||
      m.contains('online') ||
      m.contains('bank') ||
      m.contains('neft') ||
      m.contains('imps') ||
      m.contains('razor')) {
    return 'online';
  }
  return 'online';
}

List<_CollectionPayment> _paymentsForMonth(
  List<Map<String, dynamic>> rows,
  DateTime month,
) {
  final live = <_CollectionPayment>[];
  for (final row in rows) {
    final paidAt = parsePaymentDate(row);
    if (paidAt == null) continue;
    if (paidAt.year != month.year || paidAt.month != month.month) continue;
    final amount = paymentAmount(row);
    if (amount <= 0) continue;
    live.add(
      _CollectionPayment(
        id: (row['id'] ?? '${row['invoice_id']}-$paidAt').toString(),
        invoiceId: (row['invoice_id'] ?? row['invoiceId'])?.toString(),
        tenantName: tenantDisplayName(row),
        roomLabel: tenantRoomLabel(row),
        amount: amount,
        paidAt: paidAt,
        method: _normalizeMethod(
          (row['method'] ?? row['payment_method'] ?? row['paymentMethod'])
              ?.toString(),
        ),
      ),
    );
  }
  live.sort((a, b) => b.paidAt.compareTo(a.paidAt));
  return live;
}
