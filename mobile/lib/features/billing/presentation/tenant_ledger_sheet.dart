// features/billing/presentation/tenant_ledger_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../data/billing_repository.dart';
import 'create_invoice_screen.dart';
import 'invoices_list_screen.dart' show invoicesProvider;
import 'whatsapp_reminder.dart';

const _accent = Color(0xFF7C3AED);

Future<void> showTenantLedgerSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String propertyId,
  required String tenancyId,
  required String tenantName,
  required String roomLabel,
  required List<Map<String, dynamic>> allInvoices,
  String? phone,
}) {
  // Prefer explicit phone; else pick from any invoice row for this tenancy.
  var resolvedPhone = phone;
  if (resolvedPhone == null || resolvedPhone.trim().isEmpty) {
    for (final inv in allInvoices) {
      final tid =
          (inv['tenancy_id'] ?? inv['tenancyId'])?.toString().toLowerCase();
      if (tid != tenancyId.toLowerCase()) continue;
      final p = (inv['phone'] ?? inv['mobile'])?.toString();
      if (p != null && p.trim().isNotEmpty) {
        resolvedPhone = p;
        break;
      }
    }
  }

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => TenantLedgerSheet(
      propertyId: propertyId,
      tenancyId: tenancyId,
      tenantName: tenantName,
      roomLabel: roomLabel,
      phone: resolvedPhone,
      allInvoices: allInvoices,
    ),
  );
}

class TenantLedgerSheet extends ConsumerStatefulWidget {
  final String propertyId;
  final String tenancyId;
  final String tenantName;
  final String roomLabel;
  final String? phone;
  final List<Map<String, dynamic>> allInvoices;

  const TenantLedgerSheet({
    super.key,
    required this.propertyId,
    required this.tenancyId,
    required this.tenantName,
    required this.roomLabel,
    required this.allInvoices,
    this.phone,
  });

  @override
  ConsumerState<TenantLedgerSheet> createState() => _TenantLedgerSheetState();
}

class _TenantLedgerSheetState extends ConsumerState<TenantLedgerSheet> {
  static final _currency =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
  static final _monthFormat = DateFormat('MMMM yyyy');

  bool _loading = true;
  String? _error;
  String? _busyInvoiceId;
  List<_LedgerMonthGroup> _groups = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  double _asAmount(dynamic raw) =>
      double.tryParse(raw?.toString() ?? '') ?? 0;

  String _status(Map<String, dynamic> inv) =>
      inv['status']?.toString().toLowerCase().trim() ?? 'pending';

  bool _isOpen(Map<String, dynamic> inv) {
    final s = _status(inv);
    if (!{'pending', 'overdue', 'partial', 'partially_paid'}.contains(s)) {
      return false;
    }
    final remaining = _asAmount(inv['total_amount'] ?? inv['totalAmount']) -
        _asAmount(inv['paid_amount'] ?? inv['paidAmount']);
    return remaining > 0.009;
  }

  DateTime? _invoiceMonth(Map<String, dynamic> inv) {
    for (final key in [
      'period_start',
      'periodStart',
      'due_date',
      'dueDate',
      'created_at',
    ]) {
      final raw = inv[key]?.toString().trim();
      if (raw == null || raw.isEmpty) continue;
      final match = RegExp(r'^(\d{4})-(\d{2})').firstMatch(raw);
      if (match != null) {
        final y = int.tryParse(match.group(1)!);
        final m = int.tryParse(match.group(2)!);
        if (y != null && m != null) return DateTime(y, m, 1);
      }
      final d = DateTime.tryParse(raw);
      if (d != null) return DateTime(d.toLocal().year, d.toLocal().month, 1);
    }
    return null;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final repo = ref.read(billingRepositoryProvider);
      final open = widget.allInvoices.where((inv) {
        final tid =
            (inv['tenancy_id'] ?? inv['tenancyId'])?.toString().toLowerCase();
        return tid == widget.tenancyId.toLowerCase() && _isOpen(inv);
      }).toList();

      final details = <Map<String, dynamic>>[];
      for (final inv in open) {
        final id = inv['id']?.toString();
        if (id == null || id.isEmpty) continue;
        try {
          final full = await repo.getInvoice(widget.propertyId, id);
          details.add({...inv, ...full});
        } catch (_) {
          details.add(inv);
        }
      }

      final byMonth = <String, _LedgerMonthGroup>{};
      for (final inv in details) {
        final month = _invoiceMonth(inv) ?? DateTime(1970, 1, 1);
        final key = '${month.year}-${month.month.toString().padLeft(2, '0')}';
        final group = byMonth.putIfAbsent(
          key,
          () => _LedgerMonthGroup(month: month, invoices: []),
        );
        group.invoices.add(inv);
      }

      final groups = byMonth.values.toList()
        ..sort((a, b) => b.month.compareTo(a.month));

      if (!mounted) return;
      setState(() {
        _groups = groups;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load ledger: $e';
      });
    }
  }

  double get _totalRemaining {
    var sum = 0.0;
    for (final g in _groups) {
      for (final inv in g.invoices) {
        sum += (_asAmount(inv['total_amount'] ?? inv['totalAmount']) -
                _asAmount(inv['paid_amount'] ?? inv['paidAmount']))
            .clamp(0.0, double.infinity);
      }
    }
    return sum;
  }

  List<Map<String, dynamic>> _lineItems(Map<String, dynamic> inv) {
    final raw = inv['lineItems'] ?? inv['line_items'];
    if (raw is! List) return const [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> _editInvoice(Map<String, dynamic> inv) async {
    final id = inv['id']?.toString();
    if (id == null || id.isEmpty) return;
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateInvoiceScreen(
          propertyId: widget.propertyId,
          invoiceId: id,
          invoice: inv,
        ),
      ),
    );
    if (updated == true) {
      ref.invalidate(invoicesProvider(widget.propertyId));
    }
    await _load();
  }

  Future<void> _recordPaymentForInvoice(Map<String, dynamic> inv) async {
    final id = inv['id']?.toString();
    if (id == null) return;

    final total = _asAmount(inv['total_amount'] ?? inv['totalAmount']);
    final paid = _asAmount(inv['paid_amount'] ?? inv['paidAmount']);
    final remaining = (total - paid).clamp(0.0, double.infinity);
    if (remaining <= 0) return;

    final month = _invoiceMonth(inv);
    final monthLabel =
        month != null ? _monthFormat.format(month) : 'this invoice';

    final controller =
        TextEditingController(text: remaining.toStringAsFixed(0));
    final amount = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Record Payment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              monthLabel,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Outstanding for this month: ${_currency.format(remaining)}',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
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
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, double.tryParse(controller.text.trim())),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (amount == null || amount <= 0) return;

    setState(() => _busyInvoiceId = id);
    try {
      final pay = amount > remaining ? remaining : amount;
      await ref.read(billingRepositoryProvider).recordPayment(
            widget.propertyId,
            id,
            pay,
            'cash',
          );
      ref.invalidate(invoicesProvider(widget.propertyId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Recorded ${_currency.format(pay)} for $monthLabel'),
            backgroundColor: AppColors.positive,
          ),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not record payment: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busyInvoiceId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.88;

    return SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.hairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(widget.tenantName,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '${widget.roomLabel} · Month-by-month dues',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.caution.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.caution.withValues(alpha: 0.25)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total Outstanding',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    _currency.format(_totalRemaining),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: AppColors.caution,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text(_error!))
                      : _groups.isEmpty
                          ? const Center(child: Text('No unpaid invoices'))
                          : ListView.builder(
                              itemCount: _groups.length,
                              itemBuilder: (context, i) {
                                final group = _groups[i];
                                return _MonthSection(
                                  title: _monthFormat.format(group.month),
                                  invoices: group.invoices,
                                  currency: _currency,
                                  lineItemsOf: _lineItems,
                                  amountOf: _asAmount,
                                  busyInvoiceId: _busyInvoiceId,
                                  onEdit: _editInvoice,
                                  onRecordPayment: _recordPaymentForInvoice,
                                );
                              },
                            ),
            ),
            if (_totalRemaining > 0.009) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => sendWhatsAppReminder(
                  context,
                  phone: widget.phone,
                  name: widget.tenantName,
                  amount: _totalRemaining,
                ),
                icon: const Icon(Icons.chat, color: whatsAppGreen),
                label: const Text(
                  'Send WhatsApp Reminder',
                  style: TextStyle(
                    color: whatsAppGreen,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: whatsAppGreen),
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LedgerMonthGroup {
  final DateTime month;
  final List<Map<String, dynamic>> invoices;

  _LedgerMonthGroup({required this.month, required this.invoices});
}

class _MonthSection extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> invoices;
  final NumberFormat currency;
  final List<Map<String, dynamic>> Function(Map<String, dynamic>) lineItemsOf;
  final double Function(dynamic) amountOf;
  final String? busyInvoiceId;
  final Future<void> Function(Map<String, dynamic>) onEdit;
  final Future<void> Function(Map<String, dynamic>) onRecordPayment;

  const _MonthSection({
    required this.title,
    required this.invoices,
    required this.currency,
    required this.lineItemsOf,
    required this.amountOf,
    required this.busyInvoiceId,
    required this.onEdit,
    required this.onRecordPayment,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: _accent,
            ),
          ),
          const SizedBox(height: 8),
          ...invoices.map((inv) {
            final id = inv['id']?.toString();
            final total =
                amountOf(inv['total_amount'] ?? inv['totalAmount']);
            final paid =
                amountOf(inv['paid_amount'] ?? inv['paidAmount']);
            final remaining = (total - paid).clamp(0.0, double.infinity);
            final items = lineItemsOf(inv);
            final status =
                inv['status']?.toString().toUpperCase() ?? 'PENDING';
            final busy = id != null && id == busyInvoiceId;

            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: busy ? null : () => onEdit(inv),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.hairline),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              status,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: status == 'OVERDUE'
                                    ? AppColors.danger
                                    : AppColors.caution,
                              ),
                            ),
                          ),
                          Text(
                            currency.format(remaining),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (items.isEmpty)
                        Text(
                          'Invoice total ${currency.format(total)}'
                          '${paid > 0 ? ' · Paid ${currency.format(paid)}' : ''}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        )
                      else
                        ...items.map((li) {
                          final desc =
                              li['description']?.toString() ?? 'Charge';
                          final amt = amountOf(li['amount']);
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    desc,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                                Text(
                                  currency.format(amt),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: busy ? null : () => onEdit(inv),
                              icon: const Icon(Icons.edit_outlined, size: 16),
                              label: const Text('Edit'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.positive,
                              ),
                              onPressed:
                                  busy ? null : () => onRecordPayment(inv),
                              icon: busy
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.payments_outlined,
                                      size: 16),
                              label: const Text('Record Payment'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
