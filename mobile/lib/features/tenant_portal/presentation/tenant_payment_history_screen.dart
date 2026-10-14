// features/tenant_portal/presentation/tenant_payment_history_screen.dart
//
// Payment History & Statements: actual recorded payments across the tenant's
// current and past stays, property/date filters and a PDF statement.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../auth/data/auth_repository.dart';
import '../../billing/presentation/billing_invoice_helpers.dart'
    show billingCurrency;
import '../data/tenant_portal_repository.dart';
import '../domain/payment_history.dart';
import 'tenant_portal_providers.dart';
import 'widgets/tenant_load_error.dart';

const _brand = Color(0xFF5218D1);
const _brandTint = Color(0xFFF3EEFF);
const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _border = Color(0xFFE5E7EB);
const _surface = Color(0xFFF8FAFC);
const _green = Color(0xFF059669);
const _red = Color(0xFFDC2626);

final _day = DateFormat('d MMM yyyy');
final _month = DateFormat('MMM yyyy');

String _rangeLabel(StatementFilter f) {
  if (f.from == null && f.to == null) return 'All dates';
  final from = f.from == null ? 'Start' : _day.format(f.from!);
  final to = f.to == null ? 'Today' : _day.format(f.to!);
  return '$from – $to';
}

String _periodLabel(StatementPayment p) {
  final start = p.periodStart;
  if (start == null) return 'Bill';
  final end = p.periodEnd;
  if (end == null || (end.year == start.year && end.month == start.month)) {
    return '${_month.format(start)} bill';
  }
  return '${_day.format(start)} – ${_day.format(end)}';
}

class TenantPaymentHistoryScreen extends ConsumerStatefulWidget {
  /// 0 = History, 1 = PDF Statement.
  final int initialTab;

  const TenantPaymentHistoryScreen({super.key, this.initialTab = 0});

  @override
  ConsumerState<TenantPaymentHistoryScreen> createState() =>
      _TenantPaymentHistoryScreenState();
}

class _TenantPaymentHistoryScreenState
    extends ConsumerState<TenantPaymentHistoryScreen> {
  StatementFilter _draft = StatementFilter.all;
  StatementFilter _applied = StatementFilter.all;

  void _apply() {
    if (_draft.validationError != null) return;
    setState(() => _applied = _draft);
  }

  void _reset() {
    setState(() {
      _draft = StatementFilter.all;
      _applied = StatementFilter.all;
    });
  }

  void _selectProperty(String propertyId) {
    setState(() {
      _draft = _draft.copyWith(propertyId: () => propertyId);
      if (_draft.validationError == null) _applied = _draft;
    });
  }

  @override
  Widget build(BuildContext context) {
    final filterCard = _FilterCard(
      draft: _draft,
      applied: _applied,
      onChanged: (f) => setState(() => _draft = f),
      onApply: _apply,
      onReset: _reset,
    );

    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTab,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          foregroundColor: _ink,
          elevation: 0,
          centerTitle: true,
          title: const Text(
            'Payment History',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(52),
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _border),
              ),
              child: TabBar(
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: _brandTint,
                  borderRadius: BorderRadius.circular(9),
                ),
                labelColor: _brand,
                unselectedLabelColor: _muted,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
                tabs: const [
                  Tab(height: 34, text: 'History'),
                  Tab(height: 34, text: 'PDF Statement'),
                ],
              ),
            ),
          ),
        ),
        body: TabBarView(
          children: [
            _HistoryTab(
              filterCard: filterCard,
              applied: _applied,
              onSelectProperty: _selectProperty,
            ),
            _StatementTab(filterCard: filterCard, applied: _applied),
          ],
        ),
      ),
    );
  }
}

// ─── Filters ────────────────────────────────────────────────────────────────

class _FilterCard extends ConsumerWidget {
  final StatementFilter draft;
  final StatementFilter applied;
  final ValueChanged<StatementFilter> onChanged;
  final VoidCallback onApply;
  final VoidCallback onReset;

  const _FilterCard({
    required this.draft,
    required this.applied,
    required this.onChanged,
    required this.onApply,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staysAsync = ref.watch(tenantStaysProvider);
    final properties = stayProperties(staysAsync.valueOrNull ?? const []);
    final knownIds = properties.map((p) => p.propertyId).toSet();
    final selected =
        knownIds.contains(draft.propertyId) ? draft.propertyId : null;
    final error = draft.validationError;
    final dirty = draft != applied;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Filter Payments',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: _ink,
                  ),
                ),
              ),
              TextButton(
                key: const Key('reset-filters'),
                onPressed: draft.isDefault && applied.isDefault ? null : onReset,
                style: TextButton.styleFrom(
                  foregroundColor: _brand,
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Reset',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const _FieldLabel('Property'),
          DropdownButtonFormField<String?>(
            key: ValueKey('property-filter-$selected-${properties.length}'),
            initialValue: selected,
            isExpanded: true,
            decoration: _inputDecoration(),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text("All properties I've stayed at"),
              ),
              for (final p in properties)
                DropdownMenuItem<String?>(
                  value: p.propertyId,
                  child: Text(
                    '${p.name} · ${p.isCurrent ? 'Current' : 'Past stay'}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) => onChanged(draft.copyWith(propertyId: () => v)),
          ),
          if (staysAsync.hasError && !staysAsync.hasValue)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      "Couldn't load your stays.",
                      style: TextStyle(fontSize: 12, color: _muted),
                    ),
                  ),
                  TextButton(
                    onPressed: () => ref.invalidate(tenantStaysProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _DateField(
                  key: const Key('from-date'),
                  label: 'From date',
                  value: draft.from,
                  onPicked: (d) => onChanged(draft.copyWith(from: () => d)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DateField(
                  key: const Key('to-date'),
                  label: 'To date',
                  value: draft.to,
                  onPicked: (d) => onChanged(draft.copyWith(to: () => d)),
                ),
              ),
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                error,
                key: const Key('filter-error'),
                style: const TextStyle(color: _red, fontSize: 12),
              ),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('apply-filters'),
              onPressed: error == null && dirty ? onApply : null,
              style: FilledButton.styleFrom(
                backgroundColor: _brand,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Apply Filters',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

InputDecoration _inputDecoration() => InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _border),
      ),
    );

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text, style: const TextStyle(fontSize: 12, color: _muted)),
      );
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onPicked;

  const _DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onPicked,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label),
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: value ?? now,
              firstDate: DateTime(2015),
              lastDate: DateTime(now.year + 1, 12, 31),
            );
            if (picked != null) {
              onPicked(DateTime(picked.year, picked.month, picked.day));
            }
          },
          child: InputDecorator(
            decoration: _inputDecoration().copyWith(
              suffixIcon: value == null
                  ? const Icon(Icons.calendar_today_outlined, size: 16)
                  : IconButton(
                      tooltip: 'Clear $label',
                      icon: const Icon(Icons.close_rounded, size: 16),
                      onPressed: () => onPicked(null),
                    ),
            ),
            child: Text(
              value == null ? 'Any' : _day.format(value!),
              style: TextStyle(
                fontSize: 13,
                color: value == null ? _muted : _ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── History tab ────────────────────────────────────────────────────────────

class _HistoryTab extends ConsumerWidget {
  final Widget filterCard;
  final StatementFilter applied;
  final ValueChanged<String> onSelectProperty;

  const _HistoryTab({
    required this.filterCard,
    required this.applied,
    required this.onSelectProperty,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(paymentHistoryProvider(applied));
    return RefreshIndicator(
      color: _brand,
      onRefresh: () async {
        ref.invalidate(tenantStaysProvider);
        ref.invalidate(paymentHistoryProvider(applied));
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          filterCard,
          const SizedBox(height: 18),
          _StaysSection(
            selectedPropertyId: applied.propertyId,
            onSelect: onSelectProperty,
          ),
          const SizedBox(height: 18),
          ..._historyBody(context, ref, history),
        ],
      ),
    );
  }

  List<Widget> _historyBody(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<PaymentHistory> history,
  ) {
    return history.when(
      loading: () => [
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: CircularProgressIndicator(key: Key('history-loading')),
          ),
        ),
      ],
      error: (e, _) => [
        TenantLoadError(
          title: "Couldn't load your payments",
          error: e,
          compact: true,
          onRetry: () => ref.invalidate(paymentHistoryProvider(applied)),
        ),
      ],
      data: (h) => [
        _SummaryCard(history: h, filter: applied),
        const SizedBox(height: 18),
        Text(
          'Payments (${h.payments.length})',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            color: _ink,
          ),
        ),
        const SizedBox(height: 8),
        if (h.payments.isEmpty)
          const _EmptyNote(
            key: Key('history-empty'),
            text: 'No payments found for this selection. '
                'Try another property or date range.',
          )
        else
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _border),
            ),
            child: Column(
              children: [
                for (var i = 0; i < h.payments.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, indent: 60, color: _border),
                  _PaymentRow(payment: h.payments[i]),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _StaysSection extends ConsumerWidget {
  final String? selectedPropertyId;
  final ValueChanged<String> onSelect;

  const _StaysSection({
    required this.selectedPropertyId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(tenantStaysProvider);
    final stays = async.valueOrNull;
    if (stays == null || stays.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your Properties (${stays.length})',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            color: _ink,
          ),
        ),
        const SizedBox(height: 8),
        for (final s in stays) ...[
          _StayCard(
            stay: s,
            selected: s.propertyId == selectedPropertyId,
            onTap: () => onSelect(s.propertyId),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _StayCard extends StatelessWidget {
  final TenantStay stay;
  final bool selected;
  final VoidCallback onTap;

  const _StayCard({
    required this.stay,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final details = [
      if (stay.unitLabel != null) stay.unitLabel!,
      if (stay.city != null && stay.city!.trim().isNotEmpty) stay.city!,
    ].join(' · ');
    final dates = stay.moveIn == null
        ? null
        : '${_day.format(stay.moveIn!)} – '
            '${stay.isCurrent || stay.moveOut == null ? (stay.isCurrent ? 'Present' : '—') : _day.format(stay.moveOut!)}';

    return Material(
      color: selected ? _brandTint : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? _brand : _border),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _brandTint,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.apartment_rounded,
                    color: _brand, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stay.propertyName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        color: _ink,
                      ),
                    ),
                    if (details.isNotEmpty)
                      Text(
                        details,
                        style: const TextStyle(fontSize: 12, color: _muted),
                      ),
                    if (dates != null)
                      Text(
                        dates,
                        style: const TextStyle(fontSize: 11.5, color: _muted),
                      ),
                  ],
                ),
              ),
              _Pill(
                label: stay.isCurrent ? 'Current Stay' : 'Past Stay',
                color: stay.isCurrent ? _green : const Color(0xFFEA580C),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final PaymentHistory history;
  final StatementFilter filter;

  const _SummaryCard({required this.history, required this.filter});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('payments-summary'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Payments Summary',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: _ink,
            ),
          ),
          Text(
            _rangeLabel(filter),
            style: const TextStyle(fontSize: 12, color: _muted),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  label: 'Total paid',
                  value: billingCurrency.format(history.totalReceived),
                  valueKey: const Key('summary-total'),
                  big: true,
                ),
              ),
              Expanded(
                child: _Stat(
                  label: 'Payments',
                  value: '${history.paymentCount}',
                ),
              ),
              Expanded(
                child: _Stat(
                  label: 'Bills covered',
                  value: '${history.invoiceCount}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: _border),
          const SizedBox(height: 10),
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current outstanding',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                    Text(
                      'Owed today for this property scope; not limited to '
                      'the dates above.',
                      style: TextStyle(fontSize: 11, color: _muted),
                    ),
                  ],
                ),
              ),
              Text(
                billingCurrency.format(history.currentOutstanding),
                key: const Key('summary-outstanding'),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: history.currentOutstanding > 0.009 ? _red : _green,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Key? valueKey;
  final bool big;

  const _Stat({
    required this.label,
    required this.value,
    this.valueKey,
    this.big = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11.5, color: _muted)),
        const SizedBox(height: 2),
        Text(
          value,
          key: valueKey,
          style: TextStyle(
            fontSize: big ? 20 : 16,
            fontWeight: FontWeight.w800,
            color: big ? _brand : _ink,
          ),
        ),
      ],
    );
  }
}

class _PaymentRow extends StatelessWidget {
  final StatementPayment payment;

  const _PaymentRow({required this.payment});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TenantPaymentDetailScreen(payment: payment),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: _green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.payments_outlined,
                  color: _green, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    billingCurrency.format(payment.amount),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: _ink,
                    ),
                  ),
                  Text(
                    '${_periodLabel(payment)} · ${payment.propertyName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: _muted),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const _Pill(label: 'Received', color: _green),
                const SizedBox(height: 3),
                Text(
                  _day.format(payment.paidOn),
                  style: const TextStyle(fontSize: 11.5, color: _muted),
                ),
              ],
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, color: _muted, size: 20),
          ],
        ),
      ),
    );
  }
}

// ─── PDF Statement tab ──────────────────────────────────────────────────────

class _StatementTab extends ConsumerStatefulWidget {
  final Widget filterCard;
  final StatementFilter applied;

  const _StatementTab({required this.filterCard, required this.applied});

  @override
  ConsumerState<_StatementTab> createState() => _StatementTabState();
}

class _StatementTabState extends ConsumerState<_StatementTab> {
  bool _opening = false;

  Future<void> _download() async {
    setState(() => _opening = true);
    try {
      final token = await ref.read(authRepositoryProvider).getAccessToken();
      if (token == null || token.isEmpty) {
        _snack('Please sign in again to download your statement.');
        return;
      }
      final url = ref
          .read(tenantPortalRepositoryProvider)
          .paymentStatementUrl(widget.applied.toQuery(), token);
      final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!ok) _snack("We couldn't open the statement. Please try again.");
    } catch (_) {
      _snack("We couldn't open the statement. Please try again.");
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(paymentHistoryProvider(widget.applied));
    final hasPayments = history.valueOrNull?.payments.isNotEmpty ?? false;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const Text(
          'Generate PDF Statement',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            color: _ink,
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'Download a statement of your recorded payments with property '
          'details and a summary.',
          style: TextStyle(fontSize: 12.5, color: _muted),
        ),
        const SizedBox(height: 12),
        widget.filterCard,
        const SizedBox(height: 16),
        ...history.when(
          loading: () => [
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
          error: (e, _) => [
            TenantLoadError(
              title: "Couldn't prepare your statement",
              error: e,
              compact: true,
              onRetry: () =>
                  ref.invalidate(paymentHistoryProvider(widget.applied)),
            ),
          ],
          data: (h) => [
            _SummaryCard(history: h, filter: widget.applied),
            const SizedBox(height: 10),
            if (h.payments.isEmpty)
              const _EmptyNote(
                key: Key('statement-empty'),
                text: 'There are no payments in this selection, so there is '
                    'nothing to download yet.',
              )
            else
              Text(
                '${h.payments.length} '
                '${h.payments.length == 1 ? 'payment' : 'payments'} '
                'will be included in the statement.',
                style: const TextStyle(fontSize: 12.5, color: _muted),
              ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const Key('download-pdf'),
            onPressed: hasPayments && !_opening ? _download : null,
            icon: _opening
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.download_rounded, size: 18),
            label: const Text(
              'Download PDF',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: _brand,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'The statement opens in your PDF viewer, where you can save or '
          'share it.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11.5, color: _muted),
        ),
      ],
    );
  }
}

// ─── Payment detail ─────────────────────────────────────────────────────────

class TenantPaymentDetailScreen extends StatelessWidget {
  final StatementPayment payment;

  const TenantPaymentDetailScreen({super.key, required this.payment});

  @override
  Widget build(BuildContext context) {
    final p = payment;
    final rows = <(String, String)>[
      ('Payment date', _day.format(p.paidOn)),
      ('Property', p.propertyName),
      ('Bill period', _periodLabel(p)),
      ('Payment method', p.methodLabel),
      (
        'Payment reference',
        p.id.length > 8 ? p.id.substring(0, 8).toUpperCase() : p.id
      ),
      ('Bill total', billingCurrency.format(p.invoiceTotal)),
      (
        'Bill status now',
        p.invoiceFullyPaid
            ? 'Paid in full'
            : '${billingCurrency.format(p.invoiceBalance)} still due'
      ),
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        foregroundColor: _ink,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Payment Details',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _border),
            ),
            child: Column(
              children: [
                const _Pill(label: 'Received', color: _green),
                const SizedBox(height: 8),
                Text(
                  billingCurrency.format(p.amount),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
                Text(
                  'Received on ${_day.format(p.paidOn)}',
                  style: const TextStyle(fontSize: 12.5, color: _muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _border),
            ),
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) const Divider(height: 1, color: _border),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            rows[i].$1,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: _muted,
                            ),
                          ),
                        ),
                        Flexible(
                          child: Text(
                            rows[i].$2,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Shared bits ────────────────────────────────────────────────────────────

class _Pill extends StatelessWidget {
  final String label;
  final Color color;

  const _Pill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  final String text;

  const _EmptyNote({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          const Icon(Icons.receipt_long_outlined, color: _muted, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12.5, color: _muted),
            ),
          ),
        ],
      ),
    );
  }
}
