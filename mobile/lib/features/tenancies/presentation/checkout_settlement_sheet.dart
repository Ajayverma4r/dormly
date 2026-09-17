// features/tenancies/presentation/checkout_settlement_sheet.dart
//
// Module 2: Fraud-proof settlement & checkout modal with line items,
// meter calc, photo-backed damages, and WhatsApp NOC receipt.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/image_compress.dart';
import '../../billing/data/billing_repository.dart';
import '../../billing/presentation/whatsapp_reminder.dart';
import '../../structure/presentation/property_shell_screen.dart'
    show propertyDetailProvider;
import '../data/tenancy_repository.dart';
import '../domain/tenant_settlement.dart';
import 'tenancy_providers.dart';

final _currency =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _dateFmt = DateFormat('d MMM yyyy');

Future<bool> showCheckoutSettlementSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String propertyId,
  required Map<String, dynamic> tenancy,
  bool isEmergencyExit = false,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => CheckoutSettlementSheet(
      propertyId: propertyId,
      tenancy: tenancy,
      isEmergencyExit: isEmergencyExit,
    ),
  );
  return result == true;
}

class CheckoutSettlementSheet extends ConsumerStatefulWidget {
  final String propertyId;
  final Map<String, dynamic> tenancy;
  final bool isEmergencyExit;

  const CheckoutSettlementSheet({
    super.key,
    required this.propertyId,
    required this.tenancy,
    this.isEmergencyExit = false,
  });

  @override
  ConsumerState<CheckoutSettlementSheet> createState() =>
      _CheckoutSettlementSheetState();
}

class _CheckoutSettlementSheetState
    extends ConsumerState<CheckoutSettlementSheet> {
  final _startCtrl = TextEditingController();
  final _endCtrl = TextEditingController();
  final _rateCtrl = TextEditingController(text: '10');
  final _directElecCtrl = TextEditingController();
  final _cleaningCtrl = TextEditingController(text: '500');
  final _txnCtrl = TextEditingController();
  final _picker = ImagePicker();

  bool _loadingDues = true;
  bool _submitting = false;
  bool _cleaningOn = true;
  bool _waiveNoticePenalty = false;
  ElectricityInputMode _elecMode = ElectricityInputMode.byMeterUnits;
  String? _error;
  String _paymentMode = 'UPI';
  double _pendingRent = 0;
  final List<SettlementDamageItem> _damages = [];

  String get _tenancyId => widget.tenancy['id']?.toString() ?? '';
  String get _nodeId =>
      (widget.tenancy['node_id'] ?? widget.tenancy['nodeId'])?.toString() ?? '';

  double get _deposit {
    final raw = widget.tenancy['security_deposit'] ??
        widget.tenancy['securityDeposit'];
    return double.tryParse(raw?.toString() ?? '') ?? 0;
  }

  TenantSettlement get _draft {
    return TenantSettlement(
      originalDeposit: _deposit,
      pendingRent: _pendingRent,
      electricityMode: _elecMode,
      meterStartReading: double.tryParse(_startCtrl.text.trim()),
      meterEndReading: double.tryParse(_endCtrl.text.trim()),
      perUnitRate: double.tryParse(_rateCtrl.text.trim()),
      directElectricityAmount: double.tryParse(_directElecCtrl.text.trim()),
      standardCleaningCharge:
          double.tryParse(_cleaningCtrl.text.trim()) ?? 500,
      cleaningApplied: _cleaningOn,
      customDeductions: List.unmodifiable(_damages),
      paymentMode: _paymentMode,
      txnReferenceId: _txnCtrl.text.trim().isEmpty ? null : _txnCtrl.text.trim(),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadPendingRent();
  }

  @override
  void dispose() {
    _startCtrl.dispose();
    _endCtrl.dispose();
    _rateCtrl.dispose();
    _directElecCtrl.dispose();
    _cleaningCtrl.dispose();
    _txnCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPendingRent() async {
    setState(() {
      _loadingDues = true;
      _error = null;
    });
    try {
      final invoices = await ref
          .read(billingRepositoryProvider)
          .listInvoices(widget.propertyId);
      var dues = 0.0;
      for (final inv in invoices) {
        final tid =
            (inv['tenancy_id'] ?? inv['tenancyId'])?.toString() ?? '';
        if (tid != _tenancyId) continue;
        final status = inv['status']?.toString().toLowerCase() ?? '';
        if (!{'pending', 'partial', 'overdue'}.contains(status)) continue;
        final total = double.tryParse(
              inv['total_amount']?.toString() ??
                  inv['totalAmount']?.toString() ??
                  '',
            ) ??
            0;
        final paid = double.tryParse(
              inv['paid_amount']?.toString() ??
                  inv['paidAmount']?.toString() ??
                  '',
            ) ??
            0;
        final balance = total - paid;
        if (balance > 0) dues += balance;
      }
      if (mounted) {
        setState(() {
          _pendingRent = dues;
          _loadingDues = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingDues = false;
          _error = 'Could not load pending rent: $e';
        });
      }
    }
  }

  Future<void> _addDamage() async {
    final titleCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String? photoPath;

    final item = await showDialog<SettlementDamageItem>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Add damage charge'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Damage title *',
                        hintText: 'e.g. Broken wardrobe handle',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: amountCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Cost (₹) *',
                        prefixText: '₹ ',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Note (optional)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final picked = await _picker.pickImage(
                                source: ImageSource.camera,
                                imageQuality: 85,
                              );
                              if (picked == null) return;
                              final compressed =
                                  await compressKycImage(File(picked.path));
                              setLocal(() {
                                photoPath = compressed.file?.path ?? picked.path;
                              });
                            },
                            icon: const Icon(Icons.camera_alt_outlined),
                            label: Text(
                              photoPath == null ? 'Add photo proof' : 'Retake photo',
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (photoPath != null) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(photoPath!),
                          height: 96,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final title = titleCtrl.text.trim();
                    final amount =
                        double.tryParse(amountCtrl.text.trim()) ?? 0;
                    if (title.isEmpty || amount <= 0) return;
                    Navigator.pop(
                      ctx,
                      SettlementDamageItem(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        title: title,
                        amount: amount,
                        photoPath: photoPath,
                        note: noteCtrl.text.trim().isEmpty
                            ? null
                            : noteCtrl.text.trim(),
                      ),
                    );
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );

    titleCtrl.dispose();
    amountCtrl.dispose();
    noteCtrl.dispose();

    if (item != null && mounted) {
      setState(() => _damages.add(item));
    }
  }

  Future<void> _confirm() async {
    if (_tenancyId.isEmpty) return;
    final draft = _draft;
    setState(() {
      _submitting = true;
      _error = null;
    });

    final settled = draft.copyWith(
      settlementStatus:
          draft.isRefund ? SettlementStatus.refunded : SettlementStatus.collected,
      settledAt: DateTime.now(),
      paymentMode: _paymentMode,
      txnReferenceId:
          _txnCtrl.text.trim().isEmpty ? null : _txnCtrl.text.trim(),
    );

    final existing = widget.tenancy['notes']?.toString().trim();
    final notes = [
      if (existing != null && existing.isNotEmpty) existing,
      '---',
      settled.toNotesBlock(),
      if (_waiveNoticePenalty) 'Waive notice period penalty: YES (emergency)',
    ].join('\n');

    try {
      if (widget.isEmergencyExit && _waiveNoticePenalty) {
        try {
          await ref.read(tenancyRepositoryProvider).reviewMoveOutRequest(
                widget.propertyId,
                _tenancyId,
                action: 'approve',
                waiveNoticePenalty: true,
              );
        } catch (_) {
          // Non-fatal if no prior move-out request exists.
        }
      }
      await ref.read(tenancyRepositoryProvider).endTenancy(
            widget.propertyId,
            _tenancyId,
            nodeId: _nodeId.isEmpty ? null : _nodeId,
            settlementNotes: notes,
          );
      ref.invalidate(propertyResidentsProvider(widget.propertyId));

      if (!mounted) return;
      Navigator.of(context).pop(true);

      final propertyName = await _propertyName();
      if (!mounted) return;
      await showSettlementReceiptDialog(
        context: context,
        tenancy: widget.tenancy,
        settlement: settled,
        propertyName: propertyName,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = 'Settlement failed: $e';
        });
      }
    }
  }

  Future<String> _propertyName() async {
    try {
      final p = await ref.read(propertyDetailProvider(widget.propertyId).future);
      return p['name']?.toString() ?? 'Property';
    } catch (_) {
      return 'Property';
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final draft = _draft;
    final name = widget.tenancy['full_name']?.toString() ?? 'Tenant';
    final room =
        (widget.tenancy['node_name'] ?? widget.tenancy['nodeName'])
                ?.toString() ??
            'Room';
    final net = draft.netAmount;
    final isRefund = draft.isRefund;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      minChildSize: 0.55,
      maxChildSize: 0.98,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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
              Text(
                'Final Settlement',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                '$name · $room',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),

              // a. Base Pool
              _SectionLabel('Base pool'),
              _MoneyTile(
                label: 'Original security deposit',
                value: '+${_currency.format(draft.originalDeposit)}',
                valueColor: AppColors.positive,
              ),
              const SizedBox(height: 16),

              // b. Automated deductions
              _SectionLabel('Automated deductions'),
              _MoneyTile(
                label: 'Pending rent (from ledger)',
                value: _loadingDues
                    ? '…'
                    : '-${_currency.format(draft.pendingRent)}',
                valueColor: AppColors.danger,
              ),
              const SizedBox(height: 10),
              Text(
                'Final electricity',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              SegmentedButton<ElectricityInputMode>(
                segments: const [
                  ButtonSegment(
                    value: ElectricityInputMode.byMeterUnits,
                    label: Text('By Meter Units'),
                    icon: Icon(Icons.speed, size: 16),
                  ),
                  ButtonSegment(
                    value: ElectricityInputMode.directAmount,
                    label: Text('Direct Amount (₹)'),
                    icon: Icon(Icons.currency_rupee, size: 16),
                  ),
                ],
                selected: {_elecMode},
                onSelectionChanged: (s) {
                  setState(() => _elecMode = s.first);
                },
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  textStyle: WidgetStateProperty.all(
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (_elecMode == ElectricityInputMode.byMeterUnits)
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _startCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                        ],
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Start reading',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _endCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                        ],
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'End reading',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _rateCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                        ],
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: '₹ / unit',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                )
              else
                TextFormField(
                  controller: _directElecCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                  ],
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Direct electricity bill amount (₹)',
                    prefixText: '₹ ',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              const SizedBox(height: 8),
              _MoneyTile(
                label: _elecMode == ElectricityInputMode.byMeterUnits
                    ? 'Electricity (${draft.electricityUnits.toStringAsFixed(0)} units)'
                    : 'Electricity',
                value: '-${_currency.format(draft.electricityCharge)}',
                valueColor: AppColors.danger,
              ),
              const SizedBox(height: 16),

              // c. Standard contract charges
              _SectionLabel('Standard contract charges'),
              if (widget.isEmergencyExit) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Waive Notice Period Penalty'),
                  subtitle: const Text(
                    'Forgive notice shortfall for a genuine emergency',
                  ),
                  value: _waiveNoticePenalty,
                  activeThumbColor: AppColors.caution,
                  onChanged: (v) => setState(() => _waiveNoticePenalty = v),
                ),
                const SizedBox(height: 4),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Room cleaning / sanitization'),
                subtitle: Text(
                  _cleaningOn
                      ? 'Charge applied'
                      : 'Waived for this checkout',
                ),
                value: _cleaningOn,
                activeThumbColor: AppColors.blueprint,
                onChanged: (v) => setState(() => _cleaningOn = v),
              ),
              if (_cleaningOn)
                TextField(
                  controller: _cleaningCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                  ],
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Cleaning charge',
                    prefixText: '₹ ',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              const SizedBox(height: 8),
              _MoneyTile(
                label: 'Cleaning fee',
                value: '-${_currency.format(draft.cleaningCharge)}',
                valueColor: AppColors.danger,
              ),
              const SizedBox(height: 16),

              // d. Damage deductions
              _SectionLabel('Damage & repair deductions'),
              ..._damages.map((d) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: d.photoPath != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.file(
                              File(d.photoPath!),
                              width: 44,
                              height: 44,
                              fit: BoxFit.cover,
                            ),
                          )
                        : const Icon(Icons.broken_image_outlined,
                            color: AppColors.slate),
                    title: Text(d.title),
                    subtitle: Text(
                      [
                        _currency.format(d.amount),
                        if (d.note != null && d.note!.isNotEmpty) d.note!,
                      ].join(' · '),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: AppColors.danger),
                      onPressed: () =>
                          setState(() => _damages.removeWhere((x) => x.id == d.id)),
                    ),
                  ),
                );
              }),
              OutlinedButton.icon(
                onPressed: _addDamage,
                icon: const Icon(Icons.add),
                label: const Text('Add damage charge'),
              ),
              const SizedBox(height: 8),
              _MoneyTile(
                label: 'Repairs / damages total',
                value: '-${_currency.format(draft.damagesTotal)}',
                valueColor: AppColors.danger,
              ),
              const SizedBox(height: 16),

              // e. Real-time summary
              _SectionLabel('Settlement summary'),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.canvas,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Deposit − (Pending Rent + Utility + Cleaning + Damages)',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontSize: 11,
                            color: AppColors.slate,
                          ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      isRefund
                          ? 'Net Refund to Tenant'
                          : 'Tenant Dues to Collect',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _currency.format(net.abs()),
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: isRefund
                            ? AppColors.positive
                            : AppColors.danger,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // f. Transaction details
              _SectionLabel('Transaction details'),
              Wrap(
                spacing: 8,
                children: ['UPI', 'Cash', 'Bank Transfer'].map((m) {
                  final selected = _paymentMode == m;
                  return ChoiceChip(
                    label: Text(m),
                    selected: selected,
                    selectedColor: AppColors.blueprint.withValues(alpha: 0.15),
                    labelStyle: TextStyle(
                      color: selected ? AppColors.blueprint : AppColors.ink,
                      fontWeight: FontWeight.w600,
                    ),
                    onSelected: (_) => setState(() => _paymentMode = m),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _txnCtrl,
                decoration: const InputDecoration(
                  labelText: 'Reference / UTR number',
                  hintText: 'Optional for Cash',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppColors.danger)),
              ],
              const SizedBox(height: 20),
              SizedBox(
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: isRefund
                        ? AppColors.positive
                        : AppColors.blueprint,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _submitting || _loadingDues ? null : _confirm,
                  child: _submitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          isRefund
                              ? 'Confirm & Refund ${_currency.format(net.abs())}'
                              : 'Collect Balance ${_currency.format(net.abs())}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: AppColors.ink,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _MoneyTile extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _MoneyTile({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: valueColor ?? AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showSettlementReceiptDialog({
  required BuildContext context,
  required Map<String, dynamic> tenancy,
  required TenantSettlement settlement,
  required String propertyName,
}) {
  return showDialog(
    context: context,
    builder: (ctx) => _SettlementReceiptDialog(
      tenancy: tenancy,
      settlement: settlement,
      propertyName: propertyName,
    ),
  );
}

class _SettlementReceiptDialog extends StatelessWidget {
  final Map<String, dynamic> tenancy;
  final TenantSettlement settlement;
  final String propertyName;

  const _SettlementReceiptDialog({
    required this.tenancy,
    required this.settlement,
    required this.propertyName,
  });

  String get _message {
    final name = tenancy['full_name']?.toString() ?? 'Tenant';
    final room =
        (tenancy['node_name'] ?? tenancy['nodeName'])?.toString() ?? '—';
    final moveIn = _fmt(tenancy['move_in_at'] ?? tenancy['moveInAt']);
    final moveOut = settlement.settledAt != null
        ? _dateFmt.format(settlement.settledAt!.toLocal())
        : _fmt(tenancy['move_out_at'] ?? tenancy['moveOutAt']);
    final netLabel = settlement.isRefund ? 'Refund' : 'Paid';
    final mode = settlement.paymentMode ?? '—';
    final refId = settlement.txnReferenceId?.trim();
    final refPart =
        (refId == null || refId.isEmpty) ? '' : ' (Ref: $refId)';

    return '''
*Dormly - Final Settlement Summary & NOC*
Property: $propertyName
Tenant: $name | Room: $room
Move-in: ${moveIn ?? '—'} | Move-out: ${moveOut ?? '—'}
--------------------------------
Security Deposit: ${_currency.format(settlement.originalDeposit)}
Deductions:
- Pending Rent: -${_currency.format(settlement.pendingRent)}
- Electricity Units: -${_currency.format(settlement.electricityCharge)}
- Cleaning Fee: -${_currency.format(settlement.cleaningCharge)}
- Repairs / Damages: -${_currency.format(settlement.damagesTotal)}
--------------------------------
*Final Net $netLabel: ${_currency.format(settlement.netAmount.abs())}*
Status: Settled via $mode$refPart

All room keys received & accounts cleared.
'''.trim();
  }

  static String? _fmt(dynamic raw) {
    if (raw == null || raw.toString().trim().isEmpty) return null;
    final d = DateTime.tryParse(raw.toString());
    if (d == null) return null;
    return _dateFmt.format(d.toLocal());
  }

  Future<void> _shareWhatsApp(BuildContext context) async {
    final phone = normalizeWhatsAppPhone(tenancy['phone']?.toString());
    final encoded = Uri.encodeComponent(_message);
    final uris = <Uri>[
      if (phone != null)
        Uri.parse('whatsapp://send?phone=$phone&text=$encoded'),
      if (phone != null) Uri.parse('https://wa.me/$phone?text=$encoded'),
      Uri.parse('https://wa.me/?text=$encoded'),
    ];

    for (final uri in uris) {
      try {
        if (await canLaunchUrl(uri)) {
          final ok =
              await launchUrl(uri, mode: LaunchMode.externalApplication);
          if (ok) return;
        }
      } catch (_) {}
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open WhatsApp.'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Settlement complete'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Generate Settlement Receipt / NOC and share with the tenant.',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.canvas,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _message,
                style: const TextStyle(fontSize: 12, height: 1.35),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: whatsAppGreen,
            foregroundColor: Colors.white,
          ),
          onPressed: () => _shareWhatsApp(context),
          icon: const Icon(Icons.chat),
          label: const Text('Share via WhatsApp'),
        ),
      ],
    );
  }
}
