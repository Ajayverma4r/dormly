// features/billing/presentation/create_invoice_screen.dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../dashboard/presentation/property_dashboard_provider.dart';
import '../data/billing_repository.dart';
import 'billing_providers.dart';

class CreateInvoiceScreen extends ConsumerStatefulWidget {
  final String propertyId;

  /// When set, edits this invoice instead of creating a new one.
  final String? invoiceId;

  /// Optional seed from list/ledger; full invoice with line items is fetched.
  final Map<String, dynamic>? invoice;

  /// Tenancy to pre-select in the tenant dropdown (onboarding after Add Tenant).
  final String? preSelectedTenantId;

  /// Display name used if the new tenancy is not in the list yet.
  final String? preSelectedTenantName;

  /// Room/unit id the new tenant was assigned to.
  final String? roomId;

  /// Room/unit label for the dropdown while the tenancy list catches up.
  final String? preSelectedRoomName;

  /// When true, Skip / successful create return to Room details.
  final bool isFromOnboarding;

  /// Kept for callers; past dues are no longer embedded in this form.
  final bool includePastRentArrears;

  const CreateInvoiceScreen({
    super.key,
    required this.propertyId,
    this.invoiceId,
    this.invoice,
    this.preSelectedTenantId,
    this.preSelectedTenantName,
    this.roomId,
    this.preSelectedRoomName,
    this.isFromOnboarding = false,
    this.includePastRentArrears = true,
  });

  bool get isEditMode => invoiceId != null && invoiceId!.isNotEmpty;

  @override
  ConsumerState<CreateInvoiceScreen> createState() =>
      _CreateInvoiceScreenState();
}

enum _ChargeBucket { rent, maintenance, electricity, water, other }

class _CreateInvoiceScreenState extends ConsumerState<CreateInvoiceScreen> {
  static const _dueDaysAfterPeriodStart = 5;

  List<Map<String, dynamic>> _tenancies = [];
  List<Map<String, dynamic>> _chargeTypes = [];
  String? _selectedTenancyId;

  /// Controllers only for variable charges (electricity / water / other).
  final Map<String, TextEditingController> _variableControllers = {};
  final _electricityFallbackController = TextEditingController();
  final _waterFallbackController = TextEditingController();
  final _otherFallbackController = TextEditingController();

  late DateTime _periodStart;
  late DateTime _periodEnd;
  late DateTime _dueDate;

  bool _loading = true;
  bool _saving = false;
  bool _loadingOutstanding = false;
  String? _error;

  /// Unpaid ledger balance shown in the helper note (not editable / not billed here).
  double _outstandingBalance = 0;

  static final _currency =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
  static final _dateFormat = DateFormat('d MMM yyyy');

  static const _openStatuses = {
    'pending',
    'overdue',
    'partial',
    'partially_paid',
  };

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _periodStart = DateTime(now.year, now.month, 1);
    _periodEnd = DateTime(now.year, now.month + 1, 0);
    _dueDate = _defaultDueDate(_periodStart);
    _electricityFallbackController.addListener(_onAmountChanged);
    _waterFallbackController.addListener(_onAmountChanged);
    _otherFallbackController.addListener(_onAmountChanged);
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _electricityFallbackController,
      _waterFallbackController,
      _otherFallbackController,
    ]) {
      c.removeListener(_onAmountChanged);
      c.dispose();
    }
    for (final c in _variableControllers.values) {
      c.removeListener(_onAmountChanged);
      c.dispose();
    }
    super.dispose();
  }

  void _onAmountChanged() => setState(() {});

  DateTime _defaultDueDate(DateTime periodStart) =>
      periodStart.add(const Duration(days: _dueDaysAfterPeriodStart));

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime _clampDay(int year, int month, int day) {
    final lastDay = DateTime(year, month + 1, 0).day;
    final safeDay = day < 1 ? 1 : (day > lastDay ? lastDay : day);
    return DateTime(year, month, safeDay);
  }

  DateTime? _readMoveInDate(Map<String, dynamic>? tenant) {
    if (tenant == null) return null;
    for (final key in [
      'move_in_at',
      'moveInAt',
      'move_in_date',
      'moveInDate',
    ]) {
      final raw = tenant[key];
      if (raw == null) continue;
      final parsed = DateTime.tryParse(raw.toString());
      if (parsed != null) return _dateOnly(parsed.toLocal());
    }
    return null;
  }

  DateTimeRange _anniversaryPeriod(DateTime moveIn, {DateTime? asOf}) {
    final now = asOf ?? DateTime.now();
    final start = _clampDay(now.year, now.month, moveIn.day);
    final nextStart = _clampDay(start.year, start.month + 1, moveIn.day);
    final end = nextStart.subtract(const Duration(days: 1));
    return DateTimeRange(start: start, end: end);
  }

  DateTimeRange _calendarMonthPeriod({DateTime? asOf}) {
    final now = asOf ?? DateTime.now();
    return DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: DateTime(now.year, now.month + 1, 0),
    );
  }

  void _applyPeriod(DateTimeRange range) {
    _periodStart = _dateOnly(range.start);
    _periodEnd = _dateOnly(range.end);
    _dueDate = _defaultDueDate(_periodStart);
  }

  void _applyAnniversaryPeriodForTenant(String tenancyId) {
    final moveIn = _readMoveInDate(_tenancyById(tenancyId));
    _applyPeriod(
      moveIn != null ? _anniversaryPeriod(moveIn) : _calendarMonthPeriod(),
    );
  }

  String _formatAmount(double amount) => amount == amount.roundToDouble()
      ? amount.toStringAsFixed(0)
      : amount.toStringAsFixed(2);

  _ChargeBucket? _bucketForName(String raw) {
    final name = raw.trim().toLowerCase();
    if (name.isEmpty) return null;
    if (name == 'rent' || name == 'base rent' || name == 'monthly rent') {
      return _ChargeBucket.rent;
    }
    if (name.contains('rent') && !name.contains('current')) {
      return _ChargeBucket.rent;
    }
    if (name.contains('maintenance') || name == 'cam') {
      return _ChargeBucket.maintenance;
    }
    if (name.contains('electric')) return _ChargeBucket.electricity;
    if (name == 'water' || name.contains('water')) return _ChargeBucket.water;
    if (name == 'other' || name.startsWith('other')) return _ChargeBucket.other;
    return null;
  }

  Map<String, dynamic>? _chargeFor(_ChargeBucket bucket) {
    for (final c in _chargeTypes) {
      final name = (c['name'] ?? '').toString();
      if (_bucketForName(name) == bucket) return c;
    }
    return null;
  }

  TextEditingController _controllerFor(_ChargeBucket bucket) {
    final charge = _chargeFor(bucket);
    final id = charge?['id']?.toString();
    if (id != null && _variableControllers.containsKey(id)) {
      return _variableControllers[id]!;
    }
    switch (bucket) {
      case _ChargeBucket.electricity:
        return _electricityFallbackController;
      case _ChargeBucket.water:
        return _waterFallbackController;
      case _ChargeBucket.other:
        return _otherFallbackController;
      case _ChargeBucket.rent:
      case _ChargeBucket.maintenance:
        return _otherFallbackController; // unused for fixed
    }
  }

  double? _readMonthlyRent(Map<String, dynamic>? tenant) {
    if (tenant == null) return null;
    for (final key in ['monthly_rent', 'monthlyRent']) {
      final raw = tenant[key];
      if (raw == null) continue;
      if (raw is num) return raw.toDouble();
      return double.tryParse(raw.toString());
    }
    return null;
  }

  double _defaultAmount(Map<String, dynamic>? charge) {
    if (charge == null) return 0;
    final raw = charge['default_amount'] ?? charge['defaultAmount'];
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '') ?? 0;
  }

  /// Locked fixed rent from the tenancy (not editable on this screen).
  double get _fixedRent {
    final fromTenancy = _readMonthlyRent(_tenancyById(_selectedTenancyId));
    if (fromTenancy != null && fromTenancy > 0) return fromTenancy;
    return _defaultAmount(_chargeFor(_ChargeBucket.rent));
  }

  /// Locked maintenance from charge-type default.
  double get _fixedMaintenance =>
      _defaultAmount(_chargeFor(_ChargeBucket.maintenance));

  double _variableAmount(_ChargeBucket bucket) {
    return double.tryParse(_controllerFor(bucket).text.trim()) ?? 0;
  }

  double _computedTotal() {
    var total = 0.0;
    if (_fixedRent > 0) total += _fixedRent;
    if (_fixedMaintenance > 0) total += _fixedMaintenance;
    for (final b in [
      _ChargeBucket.electricity,
      _ChargeBucket.water,
      _ChargeBucket.other,
    ]) {
      final v = _variableAmount(b);
      if (v > 0) total += v;
    }
    return total;
  }

  Map<String, dynamic>? _tenancyById(String? tenancyId) {
    if (tenancyId == null) return null;
    for (final t in _tenancies) {
      if (t['id']?.toString() == tenancyId) return t;
    }
    return null;
  }

  void _ensurePreselectedTenant() {
    final id = widget.preSelectedTenantId;
    if (id == null || id.isEmpty) return;
    if (_tenancyById(id) != null) return;
    _tenancies = [
      {
        'id': id,
        'full_name': widget.preSelectedTenantName ?? 'Tenant',
        'node_name': widget.preSelectedRoomName ?? '—',
        'node_id': widget.roomId,
        'nodeId': widget.roomId,
        'status': 'active',
      },
      ..._tenancies,
    ];
  }

  void _returnToRoomDetails() {
    ref.invalidate(invoicesProvider(widget.propertyId));
    ref.invalidate(propertyDashboardProvider(widget.propertyId));
    Navigator.of(context).popUntil((route) {
      return route.settings.name == 'node-detail' || route.isFirst;
    });
  }

  void _clearVariableAmounts() {
    for (final c in _variableControllers.values) {
      c.clear();
    }
    _electricityFallbackController.clear();
    _waterFallbackController.clear();
    _otherFallbackController.clear();
  }

  bool _isArrearsDescription(String description) {
    final d = description.toLowerCase();
    return d.contains('previous dues') ||
        d.contains('arrears') ||
        d.contains('prior dues');
  }

  Future<void> _load() async {
    try {
      final repo = ref.read(billingRepositoryProvider);
      final tenancies = await repo.listTenanciesForProperty(widget.propertyId);
      final chargeTypes = await repo.listChargeTypes(widget.propertyId);

      for (final c in chargeTypes) {
        final bucket = _bucketForName((c['name'] ?? '').toString());
        if (bucket == null ||
            bucket == _ChargeBucket.rent ||
            bucket == _ChargeBucket.maintenance) {
          continue;
        }
        final id = c['id']?.toString();
        if (id == null) continue;
        final controller = TextEditingController();
        controller.addListener(_onAmountChanged);
        _variableControllers[id] = controller;
      }

      _tenancies = tenancies.where((t) => t['status'] == 'active').toList();
      _chargeTypes = chargeTypes;

      if (widget.isEditMode) {
        await _loadExistingInvoice();
      } else {
        _ensurePreselectedTenant();
      }

      if (!mounted) return;
      setState(() => _loading = false);

      if (!widget.isEditMode && widget.preSelectedTenantId != null) {
        await _onTenantSelected(widget.preSelectedTenantId);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load: $e';
      });
    }
  }

  DateTime? _parseDateField(Map<String, dynamic> inv, List<String> keys) {
    for (final key in keys) {
      final raw = inv[key]?.toString();
      if (raw == null || raw.isEmpty) continue;
      final d = DateTime.tryParse(raw);
      if (d != null) return _dateOnly(d.toLocal());
    }
    return null;
  }

  void _applyLineItemsToForm(List<Map<String, dynamic>> lineItems) {
    _clearVariableAmounts();

    final chargeById = <String, Map<String, dynamic>>{};
    for (final c in _chargeTypes) {
      final id = c['id']?.toString();
      if (id != null) chargeById[id] = c;
    }

    var otherSum = 0.0;

    for (final li in lineItems) {
      final description =
          (li['description'] ?? li['name'] ?? '').toString().trim();
      if (description.isEmpty || _isArrearsDescription(description)) continue;

      final amount = double.tryParse(
            (li['amount'] ?? li['total'] ?? '').toString(),
          ) ??
          0;
      if (amount <= 0) continue;

      final chargeTypeId =
          (li['charge_type_id'] ?? li['chargeTypeId'])?.toString();
      Map<String, dynamic>? matched;
      if (chargeTypeId != null) matched = chargeById[chargeTypeId];

      final bucket = matched != null
          ? _bucketForName((matched['name'] ?? '').toString())
          : _bucketForName(description);

      if (bucket == _ChargeBucket.electricity ||
          bucket == _ChargeBucket.water) {
        final resolvedBucket = bucket == _ChargeBucket.electricity
            ? _ChargeBucket.electricity
            : _ChargeBucket.water;
        final id = matched?['id']?.toString() ??
            _chargeFor(resolvedBucket)?['id']?.toString();
        if (id != null && _variableControllers.containsKey(id)) {
          _variableControllers[id]!.text = _formatAmount(amount);
        } else {
          _controllerFor(resolvedBucket).text = _formatAmount(amount);
        }
      } else if (bucket == _ChargeBucket.other ||
          bucket == null ||
          (bucket != _ChargeBucket.rent &&
              bucket != _ChargeBucket.maintenance)) {
        otherSum += amount;
      }
      // rent / maintenance stay locked from tenancy defaults
    }

    if (otherSum > 0) {
      _controllerFor(_ChargeBucket.other).text = _formatAmount(otherSum);
    }
  }

  Future<void> _loadExistingInvoice() async {
    final repo = ref.read(billingRepositoryProvider);
    final id = widget.invoiceId!;
    final full = await repo.getInvoice(widget.propertyId, id);

    final tenancyId = (full['tenancy_id'] ??
            full['tenancyId'] ??
            widget.invoice?['tenancy_id'])
        ?.toString();

    final start = _parseDateField(full, ['period_start', 'periodStart']);
    final end = _parseDateField(full, ['period_end', 'periodEnd']);
    final due = _parseDateField(full, ['due_date', 'dueDate']);

    if (start != null && end != null) {
      _periodStart = start;
      _periodEnd = end;
      _dueDate = due ?? _defaultDueDate(start);
    }

    _selectedTenancyId = tenancyId;

    if (tenancyId != null && _tenancyById(tenancyId) == null) {
      final seed = widget.invoice;
      _tenancies = [
        {
          'id': tenancyId,
          'full_name': seed?['full_name'] ?? full['full_name'] ?? 'Tenant',
          'node_name': seed?['node_name'] ?? full['node_name'] ?? '—',
          'status': 'active',
          'monthly_rent': seed?['monthly_rent'] ?? full['monthly_rent'],
          'monthlyRent': seed?['monthlyRent'] ?? full['monthlyRent'],
          'move_in_at': seed?['move_in_at'] ?? full['move_in_at'],
          'moveInAt': seed?['moveInAt'] ?? full['moveInAt'],
        },
        ..._tenancies,
      ];
    }

    final rawItems = full['lineItems'] ?? full['line_items'];
    final lineItems = rawItems is List
        ? rawItems
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];

    _applyLineItemsToForm(lineItems);
    if (tenancyId != null) {
      await _refreshOutstanding(tenancyId);
    }
  }

  Future<void> _pickBillingPeriod() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: _periodStart, end: _periodEnd),
      helpText: 'Select billing period',
      saveText: 'Apply',
    );
    if (picked == null) return;
    setState(() => _applyPeriod(picked));
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _dueDate = _dateOnly(picked));
  }

  Future<double> _fetchOutstandingBalance(String tenancyId) async {
    final invoices =
        await ref.read(billingRepositoryProvider).listInvoices(widget.propertyId);
    final selectedId = tenancyId.trim().toLowerCase();
    var dues = 0.0;

    for (final inv in invoices) {
      if (widget.isEditMode) {
        final invId = (inv['id'] ?? inv['invoice_id'])?.toString();
        if (invId == widget.invoiceId) continue;
      }
      final tid = (inv['tenancy_id'] ?? inv['tenancyId'])
          ?.toString()
          .trim()
          .toLowerCase();
      if (tid != selectedId) continue;

      final status = inv['status']?.toString().toLowerCase().trim() ?? '';
      if (!_openStatuses.contains(status)) continue;

      final total = double.tryParse(
            (inv['total_amount'] ?? inv['totalAmount'])?.toString() ?? '',
          ) ??
          0;
      final paid = double.tryParse(
            (inv['paid_amount'] ?? inv['paidAmount'])?.toString() ?? '',
          ) ??
          0;
      final remaining = total - paid;
      if (remaining > 0) dues += remaining;
    }

    // Include unbilled past-rent preview so the note stays informative.
    try {
      final periodStart = _periodStart.toIso8601String().split('T').first;
      final preview = await ref.read(billingRepositoryProvider).arrearsPreview(
            widget.propertyId,
            tenancyId,
            periodStart: periodStart,
            monthlyRent: _fixedRent > 0 ? _fixedRent : null,
          );
      dues += double.tryParse(preview['amount']?.toString() ?? '') ?? 0;
    } catch (_) {
      /* note is best-effort */
    }

    return dues;
  }

  Future<void> _refreshOutstanding(String tenancyId) async {
    setState(() => _loadingOutstanding = true);
    try {
      final dues = await _fetchOutstandingBalance(tenancyId);
      if (!mounted || _selectedTenancyId != tenancyId) return;
      setState(() {
        _outstandingBalance = dues;
        _loadingOutstanding = false;
      });
    } catch (_) {
      if (!mounted || _selectedTenancyId != tenancyId) return;
      setState(() {
        _outstandingBalance = 0;
        _loadingOutstanding = false;
      });
    }
  }

  Future<void> _onTenantSelected(String? tenancyId) async {
    if (widget.isEditMode) return;

    setState(() {
      _selectedTenancyId = tenancyId;
      _outstandingBalance = 0;
      _clearVariableAmounts();
      if (tenancyId != null) {
        _applyAnniversaryPeriodForTenant(tenancyId);
      } else {
        _applyPeriod(_calendarMonthPeriod());
      }
    });

    if (tenancyId == null) return;
    await _refreshOutstanding(tenancyId);
  }

  Future<void> _save() async {
    if (_selectedTenancyId == null) {
      setState(() => _error = 'Select a tenant.');
      return;
    }

    final lineItems = <Map<String, dynamic>>[];

    void addFixed(_ChargeBucket bucket, double amount, String kind) {
      if (amount <= 0) return;
      final charge = _chargeFor(bucket);
      final desc = bucket == _ChargeBucket.rent
          ? '${DateFormat('MMM').format(_periodStart)} Rent'
          : (charge?['name'] ?? 'Maintenance').toString();
      lineItems.add({
        if (charge?['id'] != null) 'chargeTypeId': charge!['id'],
        'description': desc,
        'amount': amount,
        'chargeKind': kind,
      });
    }

    addFixed(_ChargeBucket.rent, _fixedRent, 'rent');
    addFixed(_ChargeBucket.maintenance, _fixedMaintenance, 'maintenance');

    for (final entry in {
      _ChargeBucket.electricity: 'electricity',
      _ChargeBucket.water: 'other',
      _ChargeBucket.other: 'other',
    }.entries) {
      final amount = _variableAmount(entry.key);
      if (amount <= 0) continue;
      final charge = _chargeFor(entry.key);
      final name = charge != null
          ? (charge['name'] ?? entry.key.name).toString()
          : (entry.key == _ChargeBucket.other
              ? 'Other'
              : entry.key.name[0].toUpperCase() + entry.key.name.substring(1));
      lineItems.add({
        if (charge?['id'] != null) 'chargeTypeId': charge!['id'],
        'description': name,
        'amount': amount,
        'chargeKind': entry.value,
      });
    }

    if (lineItems.isEmpty) {
      setState(() =>
          _error = 'Nothing to bill — set rent on the tenant, or enter a utility.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final periodStart = _periodStart.toIso8601String().split('T').first;
      final periodEnd = _periodEnd.toIso8601String().split('T').first;
      final dueDate = _dueDate.toIso8601String().split('T').first;
      final repo = ref.read(billingRepositoryProvider);

      if (widget.isEditMode) {
        await repo.updateInvoice(
          widget.propertyId,
          widget.invoiceId!,
          periodStart: periodStart,
          periodEnd: periodEnd,
          dueDate: dueDate,
          lineItems: lineItems,
        );
      } else {
        // Past dues stay on the tenant ledger (outstanding), not this invoice.
        await repo.createInvoice(
          widget.propertyId,
          tenancyId: _selectedTenancyId!,
          periodStart: periodStart,
          periodEnd: periodEnd,
          dueDate: dueDate,
          lineItems: lineItems,
          includeArrears: false,
          includePendingCharges: true,
        );
      }

      ref.invalidate(invoicesProvider(widget.propertyId));
      ref.invalidate(propertyDashboardProvider(widget.propertyId));

      if (!mounted) return;
      if (widget.isFromOnboarding) {
        _returnToRoomDetails();
      } else {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() => _error = _friendlySaveError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _friendlySaveError(Object e) {
    if (e is DioException) {
      final status = e.response?.statusCode;
      final data = e.response?.data;
      String? serverMsg;
      if (data is Map && data['error'] != null) {
        serverMsg = data['error'].toString();
      }
      if (status == 404) {
        return widget.isEditMode
            ? 'Update failed (404). Deploy the backend, then try again.'
            : (serverMsg ?? 'Could not create invoice (not found).');
      }
      if (serverMsg != null && serverMsg.isNotEmpty) {
        return widget.isEditMode
            ? 'Could not update invoice: $serverMsg'
            : 'Could not create invoice: $serverMsg';
      }
    }
    return widget.isEditMode
        ? 'Could not update invoice: $e'
        : 'Could not create invoice: $e';
  }

  Widget _fixedChargeRow(String label, double amount) {
    final hasAmount = amount > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
          Text(
            hasAmount ? _currency.format(amount) : 'Not set',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: hasAmount ? AppColors.ink : Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _variableChargeField({
    required String label,
    required TextEditingController controller,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          prefixText: '₹ ',
          hintText: 'Optional',
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.isEditMode;
    return PopScope(
      canPop: !widget.isFromOnboarding || isEdit,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !widget.isFromOnboarding) return;
        _returnToRoomDetails();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(isEdit ? 'Edit Invoice' : 'Add Utilities'),
          actions: [
            if (widget.isFromOnboarding && !isEdit)
              TextButton(
                onPressed: _returnToRoomDetails,
                child: Text(
                  'Skip',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                children: [
                  // Tenant
                  const Text(
                    'Tenant',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  if (_tenancies.isEmpty)
                    Text(
                      'No active tenants on this property yet.',
                      style: TextStyle(color: Colors.grey.shade600),
                    )
                  else
                    DropdownButtonFormField<String>(
                      initialValue: _selectedTenancyId,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        isDense: true,
                      ),
                      items: _tenancies
                          .map((t) {
                            final id = t['id']?.toString();
                            if (id == null || id.isEmpty) return null;
                            return DropdownMenuItem<String>(
                              value: id,
                              child: Text(
                                '${t['full_name']} — ${t['node_name']}',
                              ),
                            );
                          })
                          .whereType<DropdownMenuItem<String>>()
                          .toList(),
                      onChanged: isEdit ? null : _onTenantSelected,
                    ),

                  const SizedBox(height: 16),

                  // Compact period row
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: _pickBillingPeriod,
                          borderRadius: BorderRadius.circular(12),
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'Period',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                            child: Text(
                              '${_dateFormat.format(_periodStart)} → ${_dateFormat.format(_periodEnd)}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 120,
                        child: InkWell(
                          onTap: _pickDueDate,
                          borderRadius: BorderRadius.circular(12),
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'Due',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                            child: Text(
                              _dateFormat.format(_dueDate),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 22),

                  // Fixed charges (read-only)
                  const Text(
                    'Included this cycle',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'From the tenant profile — edit rent on Tenant Details.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      children: [
                        _fixedChargeRow('Rent', _fixedRent),
                        if (_chargeFor(_ChargeBucket.maintenance) != null ||
                            _fixedMaintenance > 0) ...[
                          Divider(height: 1, color: Colors.grey.shade200),
                          _fixedChargeRow('Maintenance', _fixedMaintenance),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 22),

                  // Variable utilities only
                  const Text(
                    'Utilities (optional)',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Leave blank to skip — empty or ₹0 is ignored.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 12),
                  _variableChargeField(
                    label: 'Electricity',
                    controller: _controllerFor(_ChargeBucket.electricity),
                  ),
                  _variableChargeField(
                    label: 'Water',
                    controller: _controllerFor(_ChargeBucket.water),
                  ),
                  _variableChargeField(
                    label: 'Other',
                    controller: _controllerFor(_ChargeBucket.other),
                  ),

                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'This invoice',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          _currency.format(_computedTotal()),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (_selectedTenancyId != null) ...[
                    const SizedBox(height: 16),
                    if (_loadingOutstanding)
                      Row(
                        children: [
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Checking past dues…',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        _outstandingBalance > 0
                            ? 'Note: Any unpaid past dues (e.g., ${_currency.format(_outstandingBalance)}) will be automatically added to the Tenant\'s Total Outstanding Balance.'
                            : 'Note: Any unpaid past dues will be automatically added to the Tenant\'s Total Outstanding Balance.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: Colors.grey.shade700,
                        ),
                      ),
                  ],

                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.blueprint,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(
                              isEdit ? 'Update Invoice' : 'Save Invoice',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
