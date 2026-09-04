// features/billing/presentation/create_invoice_screen.dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../tenancies/data/tenancy_repository.dart';
import '../data/billing_repository.dart';

class CreateInvoiceScreen extends ConsumerStatefulWidget {
  final String propertyId;

  /// When set, edits this invoice instead of creating a new one.
  final String? invoiceId;

  /// Optional seed from list/ledger; full invoice with line items is fetched.
  final Map<String, dynamic>? invoice;

  const CreateInvoiceScreen({
    super.key,
    required this.propertyId,
    this.invoiceId,
    this.invoice,
  });

  bool get isEditMode => invoiceId != null && invoiceId!.isNotEmpty;

  @override
  ConsumerState<CreateInvoiceScreen> createState() =>
      _CreateInvoiceScreenState();
}

class _CreateInvoiceScreenState extends ConsumerState<CreateInvoiceScreen> {
  static const _dueDaysAfterPeriodStart = 5;

  List<Map<String, dynamic>> _tenancies = [];
  List<Map<String, dynamic>> _chargeTypes = [];
  String? _selectedTenancyId;
  final Map<String, bool> _chargeSelected = {};
  final Map<String, TextEditingController> _amountControllers = {};
  final List<_CustomChargeRow> _customCharges = [];

  late DateTime _periodStart;
  late DateTime _periodEnd;
  late DateTime _dueDate;

  bool _loading = true;
  bool _saving = false;
  bool _loadingDues = false;
  bool _loadingRollover = false;
  String? _error;

  /// Global unpaid ledger balance for the selected tenant (all months).
  final _previousDuesController = TextEditingController();

  static final _currency =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
  static final _dateFormat = DateFormat('d MMM yyyy');

  static const _openInvoiceStatuses = {
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
    _previousDuesController.addListener(_onChargeAmountChanged);
    _load();
  }

  @override
  void dispose() {
    _previousDuesController.removeListener(_onChargeAmountChanged);
    _previousDuesController.dispose();
    for (final controller in _amountControllers.values) {
      controller.removeListener(_onChargeAmountChanged);
      controller.dispose();
    }
    for (final row in _customCharges) {
      row.dispose(_onChargeAmountChanged);
    }
    super.dispose();
  }

  void _onChargeAmountChanged() => setState(() {});

  DateTime _defaultDueDate(DateTime periodStart) =>
      periodStart.add(const Duration(days: _dueDaysAfterPeriodStart));

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Clamp [day] into a valid calendar day for [year]/[month].
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

  /// Anniversary cycle for the current calendar month using move-in day.
  /// e.g. move-in 15 Aug → in September: 15 Sep → 14 Oct.
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

  double get _previousDues =>
      double.tryParse(_previousDuesController.text.trim()) ?? 0;

  void _setPreviousDues(double amount) {
    if (amount <= 0) {
      _previousDuesController.clear();
      return;
    }
    _previousDuesController.text = amount == amount.roundToDouble()
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(2);
  }

  String _formatAmount(double amount) => amount == amount.roundToDouble()
      ? amount.toStringAsFixed(0)
      : amount.toStringAsFixed(2);

  Future<void> _load() async {
    try {
      final repo = ref.read(billingRepositoryProvider);
      final tenancies = await repo.listTenanciesForProperty(widget.propertyId);
      final chargeTypes = await repo.listChargeTypes(widget.propertyId);
      for (final c in chargeTypes) {
        _chargeSelected[c['id']] = true;
        final controller = TextEditingController();
        controller.addListener(_onChargeAmountChanged);
        _amountControllers[c['id']] = controller;
      }

      _tenancies = tenancies.where((t) => t['status'] == 'active').toList();
      _chargeTypes = chargeTypes;

      if (widget.isEditMode) {
        await _loadExistingInvoice();
      }

      if (!mounted) return;
      setState(() => _loading = false);
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
    _clearAllChargeAmounts();
    _clearCustomCharges();
    _setPreviousDues(0);

    final chargeById = <String, Map<String, dynamic>>{};
    final chargeByName = <String, Map<String, dynamic>>{};
    for (final c in _chargeTypes) {
      final id = c['id']?.toString();
      if (id != null) chargeById[id] = c;
      final name = (c['name'] ?? '').toString().trim().toLowerCase();
      if (name.isNotEmpty) chargeByName[name] = c;
    }

    var arrears = 0.0;

    for (final li in lineItems) {
      final description =
          (li['description'] ?? li['name'] ?? '').toString().trim();
      if (description.isEmpty) continue;

      final amount = double.tryParse(
            (li['amount'] ?? li['total'] ?? '').toString(),
          ) ??
          0;
      if (amount <= 0) continue;

      if (_isArrearsDescription(description)) {
        arrears += amount;
        continue;
      }

      final chargeTypeId =
          (li['charge_type_id'] ?? li['chargeTypeId'])?.toString();
      Map<String, dynamic>? matched;
      if (chargeTypeId != null && chargeById.containsKey(chargeTypeId)) {
        matched = chargeById[chargeTypeId];
      } else {
        matched = chargeByName[description.toLowerCase()];
      }

      if (matched != null) {
        final id = matched['id']?.toString();
        if (id == null) continue;
        _chargeSelected[id] = true;
        _amountControllers[id]?.text = _formatAmount(amount);
      } else {
        final row = _CustomChargeRow();
        row.name.text = description;
        row.amount.text = _formatAmount(amount);
        row.attach(_onChargeAmountChanged);
        _customCharges.add(row);
      }
    }

    if (arrears > 0) _setPreviousDues(arrears);
  }

  Future<void> _loadExistingInvoice() async {
    final repo = ref.read(billingRepositoryProvider);
    final id = widget.invoiceId!;
    final full = await repo.getInvoice(widget.propertyId, id);

    final tenancyId =
        (full['tenancy_id'] ?? full['tenancyId'] ?? widget.invoice?['tenancy_id'])
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

    // Ensure selected tenancy appears even if status is no longer active.
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

  String? _rentChargeTypeId() {
    for (final c in _chargeTypes) {
      final name = (c['name'] ?? '').toString().toLowerCase();
      if (name == 'rent') return c['id']?.toString();
    }
    for (final c in _chargeTypes) {
      final name = (c['name'] ?? '').toString().toLowerCase();
      if (name.contains('rent')) return c['id']?.toString();
    }
    return null;
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

  Map<String, dynamic>? _tenancyById(String? tenancyId) {
    if (tenancyId == null) return null;
    for (final t in _tenancies) {
      if (t['id']?.toString() == tenancyId) return t;
    }
    return null;
  }

  String _hintForCharge(Map<String, dynamic> charge) {
    final name = (charge['name'] ?? '').toString().toLowerCase();
    if (name == 'electricity' || name == 'water') {
      return 'Enter amount';
    }
    return '0.00';
  }

  bool _isArrearsDescription(String description) {
    final d = description.toLowerCase();
    return d.contains('previous dues') ||
        d.contains('arrears') ||
        d.contains('prior dues');
  }

  double _computedTotal() {
    var total = _previousDues;
    for (final c in _chargeTypes) {
      if (_chargeSelected[c['id']] != true) continue;
      final id = c['id']?.toString();
      if (id == null) continue;
      total += double.tryParse(_amountControllers[id]?.text ?? '') ?? 0;
    }
    for (final row in _customCharges) {
      total += double.tryParse(row.amount.text.trim()) ?? 0;
    }
    return total;
  }

  Future<double> _fetchGlobalPreviousDues(String tenancyId) async {
    final invoices =
        await ref.read(billingRepositoryProvider).listInvoices(widget.propertyId);
    final selectedId = tenancyId.trim().toLowerCase();
    var dues = 0.0;

    for (final inv in invoices) {
      final tid = (inv['tenancy_id'] ?? inv['tenancyId'])
          ?.toString()
          .trim()
          .toLowerCase();
      if (tid != selectedId) continue;

      final status = inv['status']?.toString().toLowerCase().trim() ?? '';
      if (!_openInvoiceStatuses.contains(status)) continue;

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
    return dues;
  }

  DateTime? _invoiceSortDate(Map<String, dynamic> inv) {
    for (final key in [
      'period_end',
      'periodEnd',
      'period_start',
      'periodStart',
      'created_at',
      'createdAt',
      'due_date',
      'dueDate',
    ]) {
      final raw = inv[key]?.toString();
      if (raw == null || raw.isEmpty) continue;
      final d = DateTime.tryParse(raw);
      if (d != null) return d;
    }
    return null;
  }

  void _clearCustomCharges() {
    for (final row in _customCharges) {
      row.dispose(_onChargeAmountChanged);
    }
    _customCharges.clear();
  }

  void _applyRentOnlyFallback(String? tenancyId) {
    final rentChargeId = _rentChargeTypeId();
    final rent = _readMonthlyRent(_tenancyById(tenancyId));

    for (final c in _chargeTypes) {
      final id = c['id']?.toString();
      if (id == null) continue;
      final controller = _amountControllers[id];
      if (controller == null) continue;

      if (id == rentChargeId) {
        if (rent != null && rent > 0) {
          controller.text = _formatAmount(rent);
        } else {
          controller.clear();
        }
      } else {
        controller.clear();
      }
    }
  }

  void _clearAllChargeAmounts() {
    for (final controller in _amountControllers.values) {
      controller.clear();
    }
  }

  Future<void> _applySmartRollover(String tenancyId) async {
    final repo = ref.read(billingRepositoryProvider);
    final invoices = await repo.listInvoices(widget.propertyId);
    final selectedId = tenancyId.trim().toLowerCase();

    final tenantInvoices = invoices.where((inv) {
      final tid = (inv['tenancy_id'] ?? inv['tenancyId'])
          ?.toString()
          .trim()
          .toLowerCase();
      return tid == selectedId;
    }).toList()
      ..sort((a, b) {
        final da = _invoiceSortDate(a) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final db = _invoiceSortDate(b) ?? DateTime.fromMillisecondsSinceEpoch(0);
        return db.compareTo(da);
      });

    if (tenantInvoices.isEmpty) {
      _applyRentOnlyFallback(tenancyId);
      return;
    }

    final latestId =
        (tenantInvoices.first['id'] ?? tenantInvoices.first['invoice_id'])
            ?.toString();
    if (latestId == null || latestId.isEmpty) {
      _applyRentOnlyFallback(tenancyId);
      return;
    }

    final full = await repo.getInvoice(widget.propertyId, latestId);
    final rawItems = full['lineItems'] ?? full['line_items'];
    final lineItems = rawItems is List
        ? rawItems.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];

    if (lineItems.isEmpty) {
      _applyRentOnlyFallback(tenancyId);
      return;
    }

    _clearAllChargeAmounts();
    _clearCustomCharges();

    final chargeById = <String, Map<String, dynamic>>{};
    final chargeByName = <String, Map<String, dynamic>>{};
    for (final c in _chargeTypes) {
      final id = c['id']?.toString();
      if (id != null) chargeById[id] = c;
      final name = (c['name'] ?? '').toString().trim().toLowerCase();
      if (name.isNotEmpty) chargeByName[name] = c;
    }

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
      if (chargeTypeId != null && chargeById.containsKey(chargeTypeId)) {
        matched = chargeById[chargeTypeId];
      } else {
        matched = chargeByName[description.toLowerCase()];
      }

      if (matched != null) {
        final id = matched['id']?.toString();
        if (id == null) continue;
        _chargeSelected[id] = true;
        _amountControllers[id]?.text = _formatAmount(amount);
      } else {
        final row = _CustomChargeRow();
        row.name.text = description;
        row.amount.text = _formatAmount(amount);
        row.attach(_onChargeAmountChanged);
        _customCharges.add(row);
      }
    }

    // Ensure rent still has a value if last invoice had no rent line.
    final rentId = _rentChargeTypeId();
    if (rentId != null) {
      final rentText = _amountControllers[rentId]?.text.trim() ?? '';
      if (rentText.isEmpty) {
        final rent = _readMonthlyRent(_tenancyById(tenancyId));
        if (rent != null && rent > 0) {
          _amountControllers[rentId]?.text = _formatAmount(rent);
        }
      }
    }
  }

  Future<void> _onTenantSelected(String? tenancyId) async {
    if (widget.isEditMode) return;

    setState(() {
      _selectedTenancyId = tenancyId;
      _setPreviousDues(0);
      _loadingDues = tenancyId != null;
      _loadingRollover = tenancyId != null;
      _clearCustomCharges();
      _clearAllChargeAmounts();
      if (tenancyId != null) {
        _applyAnniversaryPeriodForTenant(tenancyId);
      } else {
        _applyPeriod(_calendarMonthPeriod());
      }
    });

    if (tenancyId == null) return;

    try {
      await _applySmartRollover(tenancyId);
      if (!mounted || _selectedTenancyId != tenancyId) return;
      setState(() => _loadingRollover = false);

      final dues = await _fetchGlobalPreviousDues(tenancyId);
      if (!mounted || _selectedTenancyId != tenancyId) return;
      setState(() {
        _setPreviousDues(dues);
        _loadingDues = false;
      });
    } catch (_) {
      if (!mounted || _selectedTenancyId != tenancyId) return;
      _applyRentOnlyFallback(tenancyId);
      setState(() {
        _setPreviousDues(0);
        _loadingDues = false;
        _loadingRollover = false;
      });
    }
  }

  void _addCustomCharge() {
    final row = _CustomChargeRow();
    row.attach(_onChargeAmountChanged);
    setState(() => _customCharges.add(row));
  }

  void _removeCustomCharge(int index) {
    if (index < 0 || index >= _customCharges.length) return;
    final row = _customCharges.removeAt(index);
    row.dispose(_onChargeAmountChanged);
    setState(() {});
  }

  double? _currentRentInput() {
    final rentId = _rentChargeTypeId();
    if (rentId == null) return null;
    if (_chargeSelected[rentId] != true) return null;
    return double.tryParse(_amountControllers[rentId]?.text.trim() ?? '');
  }

  Future<bool?> _askUpdateDefaultRent(double newRent) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update default rent?'),
        content: Text(
          'You changed the base rent. Do you want to permanently update this '
          'tenant\'s monthly rent to ${_currency.format(newRent)} for future invoices?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Only for this invoice'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Update Permanently'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_selectedTenancyId == null) {
      setState(() => _error = 'Select a tenant.');
      return;
    }

    final lineItems = <Map<String, dynamic>>[];

    for (final c in _chargeTypes) {
      if (_chargeSelected[c['id']] != true) continue;
      final amount =
          double.tryParse(_amountControllers[c['id']]!.text.trim()) ?? 0;
      if (amount <= 0) continue;
      lineItems.add({
        'chargeTypeId': c['id'],
        'description': c['name'],
        'amount': amount,
      });
    }

    for (final row in _customCharges) {
      final name = row.name.text.trim();
      final amount = double.tryParse(row.amount.text.trim()) ?? 0;
      if (amount <= 0) continue;
      if (name.isEmpty) {
        setState(() => _error = 'Give each custom charge a name.');
        return;
      }
      lineItems.add({
        'description': name,
        'amount': amount,
      });
    }

    if (_previousDues > 0) {
      lineItems.insert(0, {
        'description': 'Previous Dues (Arrears)',
        'amount': _previousDues,
      });
    }

    if (lineItems.isEmpty) {
      setState(() => _error = 'Add at least one charge with an amount above 0.');
      return;
    }

    final rentInput = _currentRentInput();
    final savedRent = _readMonthlyRent(_tenancyById(_selectedTenancyId));
    var updateRentPermanently = false;

    if (rentInput != null &&
        rentInput > 0 &&
        savedRent != null &&
        (rentInput - savedRent).abs() > 0.009) {
      final choice = await _askUpdateDefaultRent(rentInput);
      if (!mounted) return;
      if (choice == null) return; // dialog dismissed — abort save
      updateRentPermanently = choice == true;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      if (updateRentPermanently && rentInput != null) {
        await ref.read(tenancyRepositoryProvider).update(
              widget.propertyId,
              _selectedTenancyId!,
              monthlyRent: rentInput,
            );
        final t = _tenancyById(_selectedTenancyId);
        if (t != null) {
          t['monthly_rent'] = rentInput;
          t['monthlyRent'] = rentInput;
        }
      }

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
        await repo.createInvoice(
          widget.propertyId,
          tenancyId: _selectedTenancyId!,
          periodStart: periodStart,
          periodEnd: periodEnd,
          dueDate: dueDate,
          lineItems: lineItems,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
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
            ? 'Update failed (404). The invoice update API is not on the server yet — deploy the backend, then try again.'
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

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.isEditMode;
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit Invoice' : 'New Invoice')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text('Tenant',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                if (_tenancies.isEmpty)
                  Text(
                    'No active tenants on this property yet.',
                    style: TextStyle(color: Colors.grey.shade600),
                  )
                else
                  DropdownButtonFormField<String>(
                    value: _selectedTenancyId,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: _tenancies
                        .map(
                          (t) => DropdownMenuItem<String>(
                            value: t['id'],
                            child: Text(
                              '${t['full_name']} — ${t['node_name']}',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: isEdit ? null : _onTenantSelected,
                  ),
                if (_loadingRollover) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Loading last invoice…',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                const Text('Billing Period',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                InkWell(
                  onTap: _pickBillingPeriod,
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      suffixIcon: const Icon(Icons.date_range_outlined),
                      helperText: isEdit
                          ? 'Loaded from this invoice — tap to adjust'
                          : (_selectedTenancyId == null
                              ? 'Select a tenant to auto-align with move-in day'
                              : (_readMoveInDate(
                                          _tenancyById(_selectedTenancyId)) !=
                                      null
                                  ? 'Anniversary cycle from move-in day — tap to edit'
                                  : 'No move-in date — calendar month (editable)')),
                    ),
                    child: Text(
                      '${_dateFormat.format(_periodStart)} → ${_dateFormat.format(_periodEnd)}',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Due Date',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                InkWell(
                  onTap: _pickDueDate,
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      suffixIcon: const Icon(Icons.event_outlined),
                      helperText:
                          'Auto-set to $_dueDaysAfterPeriodStart days after period start',
                    ),
                    child: Text(_dateFormat.format(_dueDate)),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Charges',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                _PreviousDuesRow(
                  controller: _previousDuesController,
                  amount: _previousDues,
                  loading: _loadingDues,
                  visible: _selectedTenancyId != null,
                ),
                ..._chargeTypes.map((c) {
                  final selected = _chargeSelected[c['id']] ?? true;
                  final chargeName =
                      (c['name'] ?? '').toString().toLowerCase();
                  final isVariable =
                      chargeName == 'electricity' || chargeName == 'water';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: selected,
                          onChanged: (v) => setState(
                            () => _chargeSelected[c['id']] = v ?? false,
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c['name']),
                              if (isVariable)
                                Text(
                                  'Variable — enter this month\'s amount',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 110,
                          child: TextFormField(
                            controller: _amountControllers[c['id']],
                            enabled: selected,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              prefixText: '₹ ',
                              hintText: _hintForCharge(c),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                ...List.generate(_customCharges.length, (i) {
                  final row = _customCharges[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            controller: row.name,
                            decoration: const InputDecoration(
                              labelText: 'Charge name',
                              hintText: 'e.g. Repair',
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: row.amount,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              prefixText: '₹ ',
                              labelText: 'Amount',
                              isDense: true,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove',
                          onPressed: () => _removeCustomCharge(i),
                          icon: Icon(
                            Icons.delete_outline,
                            color: Colors.red.shade400,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _addCustomCharge,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Custom Charge'),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total Amount',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
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
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2B5CFF),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                            isEdit ? 'Update Invoice' : 'Create Invoice',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _CustomChargeRow {
  final TextEditingController name = TextEditingController();
  final TextEditingController amount = TextEditingController();

  void attach(VoidCallback onChanged) {
    name.addListener(onChanged);
    amount.addListener(onChanged);
  }

  void dispose(VoidCallback onChanged) {
    name.removeListener(onChanged);
    amount.removeListener(onChanged);
    name.dispose();
    amount.dispose();
  }
}

class _PreviousDuesRow extends StatelessWidget {
  final TextEditingController controller;
  final double amount;
  final bool loading;
  final bool visible;

  const _PreviousDuesRow({
    required this.controller,
    required this.amount,
    required this.loading,
    required this.visible,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child:
                    Icon(Icons.history, size: 18, color: Colors.orange.shade800),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Previous Dues',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'All unpaid invoices (any month) — editable',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              if (loading)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                SizedBox(
                  width: 110,
                  child: TextFormField(
                    controller: controller,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.orange.shade900,
                      fontSize: 13,
                    ),
                    decoration: InputDecoration(
                      prefixText: '₹ ',
                      hintText: '0',
                      isDense: true,
                      filled: true,
                      fillColor: Colors.orange.shade50,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.orange.shade200),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.orange.shade300),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (amount > 0) ...[
            const SizedBox(height: 6),
            Text(
              'Includes unpaid rent from previous months',
              style: TextStyle(
                fontSize: 11,
                color: Colors.red.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

