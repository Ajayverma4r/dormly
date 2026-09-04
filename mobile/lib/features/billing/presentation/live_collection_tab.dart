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

const _accent = Color(0xFF7C3AED);

/// Action-oriented dues list: outstanding + received, tenants with pending only.
class LiveCollectionTab extends ConsumerStatefulWidget {
  final String propertyId;

  const LiveCollectionTab({super.key, required this.propertyId});

  @override
  ConsumerState<LiveCollectionTab> createState() => _LiveCollectionTabState();
}

class _LiveCollectionTabState extends ConsumerState<LiveCollectionTab> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

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

    final groups = map.values
        .where((g) => g.grandTotalPending > 0.009)
        .toList()
      ..sort((a, b) {
        final byPending =
            b.grandTotalPending.compareTo(a.grandTotalPending);
        if (byPending != 0) return byPending;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return groups;
  }

  List<_TenantPaymentGroup> _filterGroups(List<_TenantPaymentGroup> groups) {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return groups;
    return groups.where((g) {
      return g.name.toLowerCase().contains(q) ||
          g.room.toLowerCase().contains(q) ||
          g.grandTotalPending.toStringAsFixed(0).contains(q);
    }).toList();
  }

  double _totalOutstanding(List<Map<String, dynamic>> all) {
    var pending = 0.0;
    for (final inv in all) {
      if (!isOpenUnpaidInvoice(inv)) continue;
      pending += invoiceRemaining(inv);
    }
    return pending;
  }

  @override
  Widget build(BuildContext context) {
    final invoicesAsync = ref.watch(invoicesProvider(widget.propertyId));
    final receivedAsync =
        ref.watch(receivedThisMonthProvider(widget.propertyId));
    final baseUrl = ref.watch(tenancyRepositoryProvider).baseUrl;
    final receivedThisMonth = receivedAsync.maybeWhen(
      data: (v) => v,
      orElse: () => 0.0,
    );

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
        final outstanding = _totalOutstanding(invoices);
        final groups = _filterGroups(_groupByTenant(invoices));
        final hasAnyInvoices = invoices.isNotEmpty;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _CashflowCards(
                outstanding: outstanding,
                receivedThisMonth: receivedThisMonth,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: 'Search tenant, room or amount...',
                  hintStyle: TextStyle(
                    color: AppColors.slate.withValues(alpha: 0.8),
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: AppColors.slate,
                    size: 20,
                  ),
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
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: _TableHeaderRow(),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: groups.isNotEmpty
                    ? ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(top: 4, bottom: 16),
                        itemCount: groups.length,
                        separatorBuilder: (_, __) => const Divider(
                          height: 1,
                          thickness: 1,
                          color: AppColors.hairline,
                          indent: 12,
                          endIndent: 12,
                        ),
                        itemBuilder: (context, i) {
                          final g = groups[i];
                          return _TenantLedgerListRow(
                            group: g,
                            baseUrl: baseUrl,
                            onPay: () => _openLedger(g, invoices),
                            onRowTap: () => _openLedger(g, invoices),
                          );
                        },
                      )
                    : ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.35,
                            child: _EmptyLiveCollection(
                              onCreate: _openNewInvoice,
                              hasAnyInvoices: hasAnyInvoices,
                              searching: _searchQuery.trim().isNotEmpty,
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

class _CashflowCards extends StatelessWidget {
  final double outstanding;
  final double receivedThisMonth;

  const _CashflowCards({
    required this.outstanding,
    required this.receivedThisMonth,
  });

  @override
  Widget build(BuildContext context) {
    final nowLabel = DateFormat('MMMM').format(DateTime.now());
    return Row(
      children: [
        Expanded(
          child: _SummaryTile(
            label: 'Total Outstanding',
            value: billingCurrency.format(outstanding),
            subtitle: 'Unpaid across all invoices',
            valueColor:
                outstanding > 0 ? AppColors.danger : AppColors.positive,
            icon: Icons.warning_amber_rounded,
            iconColor: AppColors.danger,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SummaryTile(
            label: 'Received This Month',
            value: billingCurrency.format(receivedThisMonth),
            subtitle: nowLabel,
            valueColor: AppColors.positive,
            icon: Icons.payments_outlined,
            iconColor: AppColors.positive,
          ),
        ),
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final String value;
  final String subtitle;
  final Color valueColor;
  final IconData icon;
  final Color iconColor;

  const _SummaryTile({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.valueColor,
    required this.icon,
    required this.iconColor,
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
              Icon(icon, size: 16, color: iconColor),
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
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade600,
                  fontSize: 11,
                ),
          ),
        ],
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
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('Tenant', style: style)),
          Expanded(flex: 2, child: Text('Dues', style: style)),
          Expanded(flex: 2, child: Text('Amount', style: style)),
          Expanded(flex: 2, child: Text('Actions', style: style)),
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

  int get unpaidMonthCount {
    final months = <String>{};
    for (final inv in invoices) {
      if (invoiceStatus(inv) == 'paid') continue;
      if (invoiceRemaining(inv) <= 0.009) continue;
      final d = invoiceMonthDate(inv);
      if (d != null) {
        months.add(
          '${d.year}-${d.month.toString().padLeft(2, '0')}',
        );
      }
    }
    return months.isEmpty
        ? invoices.where((i) => invoiceStatus(i) != 'paid').length
        : months.length;
  }

  bool get hasOverdue =>
      invoices.any((i) => invoiceStatus(i) == 'overdue');

  String get displayStatus {
    if (hasOverdue) return 'overdue';
    if (grandTotalPending > 0) return 'pending';
    return 'pending';
  }

  String get duesSummary {
    final n = unpaidMonthCount;
    return '$n unpaid month${n == 1 ? '' : 's'}';
  }
}

class _TenantLedgerListRow extends StatelessWidget {
  final _TenantPaymentGroup group;
  final String baseUrl;
  final VoidCallback onPay;
  final VoidCallback onRowTap;

  const _TenantLedgerListRow({
    required this.group,
    required this.baseUrl,
    required this.onPay,
    required this.onRowTap,
  });

  @override
  Widget build(BuildContext context) {
    final photoUrl = resolvePhotoUrl(group.photoUrl, baseUrl);
    final initials = initialsFromName(group.name);

    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: onRowTap,
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
                  billingCurrency.format(group.grandTotalPending),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.danger,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: 'WhatsApp reminder',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      onPressed: () => sendWhatsAppReminder(
                        context,
                        phone: group.phone,
                        name: group.name,
                        amount: group.grandTotalPending,
                      ),
                      icon: const Icon(
                        Icons.chat,
                        size: 18,
                        color: whatsAppGreen,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Pay / ledger',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      onPressed: onPay,
                      icon: const Icon(
                        Icons.payments_outlined,
                        size: 18,
                        color: AppColors.blueprint,
                      ),
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
            : 'No outstanding dues';
    final subtitle = !hasAnyInvoices
        ? 'Create your first invoice to start collecting.'
        : searching
            ? 'Try a different search.'
            : 'All tenants are paid up.';

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
