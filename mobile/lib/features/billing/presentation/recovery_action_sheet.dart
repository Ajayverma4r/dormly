// features/billing/presentation/recovery_action_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../dashboard/presentation/property_dashboard_provider.dart';
import '../../tenancies/presentation/residents_list_screen.dart'
    show propertyResidentsProvider;
import '../data/billing_repository.dart';
import 'billing_invoice_helpers.dart';
import 'billing_providers.dart';
import 'whatsapp_reminder.dart';

const _accent = AppColors.primary;
const _debtOrange = Color(0xFFD97706);

final _invoiceMonthFormat = DateFormat('MMMM yyyy');

Future<void> showRecoveryActionSheet({
  required BuildContext context,
  required String propertyId,
  double pendingFallback = 0,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => RecoveryActionSheet(
      propertyId: propertyId,
      pendingFallback: pendingFallback,
    ),
  );
}

class RecoveryActionSheet extends ConsumerWidget {
  final String propertyId;
  final double pendingFallback;

  const RecoveryActionSheet({
    super.key,
    required this.propertyId,
    this.pendingFallback = 0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoicesAsync = ref.watch(invoicesProvider(propertyId));
    final tenanciesAsync = ref.watch(propertyResidentsProvider(propertyId));

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      builder: (context, scrollController) {
        final invoices = invoicesAsync.maybeWhen(
          data: (rows) => rows,
          orElse: () => const <Map<String, dynamic>>[],
        );
        final tenancies = tenanciesAsync.maybeWhen(
          data: (rows) => rows,
          orElse: () => const <Map<String, dynamic>>[],
        );
        final defaulters = _groupDefaulters(invoices, tenancies);
        final totalOutstanding = invoicesAsync.hasValue
            ? defaulters.fold<double>(0, (s, d) => s + d.amountOwed)
            : pendingFallback;

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
                      'Pending Dues Recovery',
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
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Text(
                      '${billingCurrency.format(totalOutstanding)} Total Outstanding',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.danger,
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    child: SizedBox(
                      height: 48,
                      child: FilledButton(
                        onPressed: invoicesAsync.isLoading
                            ? null
                            : () => _sendRemindersToAll(context, defaulters),
                        style: FilledButton.styleFrom(
                          backgroundColor: _accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          '🔔 Send Reminders to All',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
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
                      'Tenants with dues',
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
                else if (invoicesAsync.hasError)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Could not load pending dues.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.slate),
                        ),
                      ),
                    ),
                  )
                else if (defaulters.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No pending dues — all caught up!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.slate),
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                    sliver: SliverList.builder(
                      itemCount: defaulters.length,
                      itemBuilder: (context, i) => _DefaulterTile(
                        defaulter: defaulters[i],
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

void _sendRemindersToAll(
  BuildContext context,
  List<_Defaulter> defaulters,
) {
  final count = defaulters.length;
  final label = count == 1 ? '1 tenant' : '$count tenants';
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Reminders sent to $label')),
  );
}

class _DefaulterTile extends ConsumerWidget {
  final _Defaulter defaulter;
  final String propertyId;

  const _DefaulterTile({
    required this.defaulter,
    required this.propertyId,
  });

  Future<void> _call(BuildContext context) async {
    final phone = defaulter.phone?.trim();
    if (phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number on file for this tenant')),
      );
      return;
    }
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      return;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the phone dialer')),
      );
    }
  }

  Future<void> _recordPayment(BuildContext context, WidgetRef ref) async {
    final invoice = defaulter.invoices.isEmpty ? null : defaulter.invoices.first;
    if (invoice == null || invoice.id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pending invoice to record against')),
      );
      return;
    }

    final controller =
        TextEditingController(text: invoice.remaining.toStringAsFixed(0));
    final amount = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Record Payment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              invoice.label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Outstanding: ${billingCurrency.format(invoice.remaining)}',
              style: const TextStyle(color: AppColors.slate, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                prefixText: '₹ ',
                labelText: 'Amount received',
                border: OutlineInputBorder(),
              ),
            ),
          ],
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

    final pay = amount > invoice.remaining ? invoice.remaining : amount;
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
          content: Text('Recorded ${billingCurrency.format(pay)}'),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoiceLabel = defaulter.invoiceCount == 1
        ? '1 Invoice'
        : '${defaulter.invoiceCount} Invoices';

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 12, 8),
        controlAffinity: ListTileControlAffinity.leading,
        iconColor: _accent,
        collapsedIconColor: AppColors.slate,
        title: Text(
          defaulter.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          'Owes ${billingCurrency.format(defaulter.amountOwed)} • $invoiceLabel',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.danger,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Call tenant',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: () => _call(context),
              icon: const Icon(Icons.phone, color: _debtOrange, size: 20),
            ),
            IconButton(
              tooltip: 'WhatsApp reminder',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: () => sendWhatsAppReminder(
                context,
                phone: defaulter.phone,
                name: defaulter.name,
                amount: defaulter.amountOwed,
              ),
              icon: const Icon(Icons.chat, color: whatsAppGreen, size: 20),
            ),
          ],
        ),
        children: [
          for (final invoice in defaulter.invoices)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      invoice.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    billingCurrency.format(invoice.remaining),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.danger,
                    ),
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _recordPayment(context, ref),
              style: TextButton.styleFrom(foregroundColor: _accent),
              child: const Text(
                'Record Payment',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingInvoice {
  final String id;
  final String label;
  final double remaining;
  final DateTime? month;

  const _PendingInvoice({
    required this.id,
    required this.label,
    required this.remaining,
    this.month,
  });
}

class _Defaulter {
  final String tenancyId;
  final String name;
  final String room;
  final double amountOwed;
  final int invoiceCount;
  final String? phone;
  final List<_PendingInvoice> invoices;

  const _Defaulter({
    required this.tenancyId,
    required this.name,
    required this.room,
    required this.amountOwed,
    required this.invoiceCount,
    required this.invoices,
    this.phone,
  });

  String get title {
    final roomLabel = room.trim();
    if (roomLabel.isEmpty || roomLabel == '—') return name;
    return '$name - $roomLabel';
  }
}

String _invoiceLabel(Map<String, dynamic> inv) {
  final month = invoiceMonthDate(inv);
  if (month == null) return 'Outstanding invoice';
  return '${_invoiceMonthFormat.format(month)} Rent';
}

List<_Defaulter> _groupDefaulters(
  List<Map<String, dynamic>> invoices,
  List<Map<String, dynamic>> tenancies,
) {
  final phoneByTenancy = <String, String>{};
  for (final t in tenancies) {
    final id = (t['id'] ?? t['tenancy_id'] ?? t['tenancyId'])?.toString();
    if (id == null || id.isEmpty) continue;
    final phone = (t['phone'] ?? t['mobile'])?.toString().trim();
    if (phone != null && phone.isNotEmpty) phoneByTenancy[id] = phone;
  }

  final map = <String, _DefaulterAcc>{};
  for (final inv in invoices) {
    if (invoiceRemaining(inv) <= 0.009) continue;

    final tenancyId =
        (inv['tenancy_id'] ?? inv['tenancyId'])?.toString() ?? '';
    if (tenancyId.isEmpty) continue;

    final acc = map.putIfAbsent(
      tenancyId,
      () => _DefaulterAcc(
        tenancyId: tenancyId,
        name: tenantDisplayName(inv),
        room: tenantRoomLabel(inv),
        phone: tenantPhone(inv) ?? phoneByTenancy[tenancyId],
      ),
    );
    acc.amountOwed += invoiceRemaining(inv);
    acc.invoices.add(
      _PendingInvoice(
        id: (inv['id'] ?? '').toString(),
        label: _invoiceLabel(inv),
        remaining: invoiceRemaining(inv),
        month: invoiceMonthDate(inv),
      ),
    );
    final phone = tenantPhone(inv) ?? phoneByTenancy[tenancyId];
    if ((acc.phone == null || acc.phone!.trim().isEmpty) &&
        phone != null &&
        phone.trim().isNotEmpty) {
      acc.phone = phone;
    }
  }

  final list = map.values.map((a) {
    a.invoices.sort((x, y) {
      final xm = x.month ?? DateTime(1970);
      final ym = y.month ?? DateTime(1970);
      return xm.compareTo(ym);
    });
    return _Defaulter(
      tenancyId: a.tenancyId,
      name: a.name,
      room: a.room,
      amountOwed: a.amountOwed,
      invoiceCount: a.invoices.length,
      invoices: a.invoices,
      phone: a.phone,
    );
  }).toList()
    ..sort((a, b) => b.amountOwed.compareTo(a.amountOwed));
  return list;
}

class _DefaulterAcc {
  final String tenancyId;
  final String name;
  final String room;
  String? phone;
  double amountOwed = 0;
  final List<_PendingInvoice> invoices = [];

  _DefaulterAcc({
    required this.tenancyId,
    required this.name,
    required this.room,
    this.phone,
  });
}

