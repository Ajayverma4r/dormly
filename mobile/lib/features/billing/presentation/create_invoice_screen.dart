// features/billing/presentation/create_invoice_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/billing_repository.dart';

class CreateInvoiceScreen extends ConsumerStatefulWidget {
  final String propertyId;
  const CreateInvoiceScreen({super.key, required this.propertyId});

  @override
  ConsumerState<CreateInvoiceScreen> createState() => _CreateInvoiceScreenState();
}

class _CreateInvoiceScreenState extends ConsumerState<CreateInvoiceScreen> {
  List<Map<String, dynamic>> _tenancies = [];
  List<Map<String, dynamic>> _chargeTypes = [];
  String? _selectedTenancyId;
  final Map<String, bool> _chargeSelected = {};
  final Map<String, TextEditingController> _amountControllers = {};

  DateTime _periodStart = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _periodEnd = DateTime(DateTime.now().year, DateTime.now().month + 1, 0);
  DateTime _dueDate = DateTime.now().add(const Duration(days: 5));

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = ref.read(billingRepositoryProvider);
      final tenancies = await repo.listTenanciesForProperty(widget.propertyId);
      final chargeTypes = await repo.listChargeTypes(widget.propertyId);
      for (final c in chargeTypes) {
        _chargeSelected[c['id']] = true;
        _amountControllers[c['id']] = TextEditingController(text: c['default_amount'].toString());
      }
      setState(() {
        _tenancies = tenancies.where((t) => t['status'] == 'active').toList();
        _chargeTypes = chargeTypes;
        _loading = false;
      });
    } catch (e) {
      setState(() { _loading = false; _error = 'Could not load: $e'; });
    }
  }

  Future<void> _pickDate(DateTime initial, ValueChanged<DateTime> onPicked) async {
    final picked = await showDatePicker(
      context: context, initialDate: initial, firstDate: DateTime(2020), lastDate: DateTime(2100),
    );
    if (picked != null) onPicked(picked);
  }

  Future<void> _save() async {
    if (_selectedTenancyId == null) {
      setState(() => _error = 'Select a tenant.');
      return;
    }
    final lineItems = _chargeTypes
        .where((c) => _chargeSelected[c['id']] == true)
        .map((c) => {
              'chargeTypeId': c['id'],
              'description': c['name'],
              'amount': double.tryParse(_amountControllers[c['id']]!.text) ?? 0,
            })
        .where((li) => (li['amount'] as double) > 0)
        .toList();

    if (lineItems.isEmpty) {
      setState(() => _error = 'Add at least one charge with an amount above 0.');
      return;
    }

    setState(() { _saving = true; _error = null; });
    try {
      await ref.read(billingRepositoryProvider).createInvoice(
            widget.propertyId,
            tenancyId: _selectedTenancyId!,
            periodStart: _periodStart.toIso8601String().split('T').first,
            periodEnd: _periodEnd.toIso8601String().split('T').first,
            dueDate: _dueDate.toIso8601String().split('T').first,
            lineItems: lineItems,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = 'Could not create invoice: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Invoice')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text('Tenant', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                if (_tenancies.isEmpty)
                  Text('No active tenants on this property yet.', style: TextStyle(color: Colors.grey.shade600))
                else
                  DropdownButtonFormField<String>(
                    value: _selectedTenancyId,
                    decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                    items: _tenancies
                        .map((t) => DropdownMenuItem<String>(
                              value: t['id'],
                              child: Text('${t['full_name']} — ${t['node_name']}'),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedTenancyId = v),
                  ),
                const SizedBox(height: 20),
                const Text('Charges', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                ..._chargeTypes.map((c) {
                  final selected = _chargeSelected[c['id']] ?? true;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Checkbox(
                          value: selected,
                          onChanged: (v) => setState(() => _chargeSelected[c['id']] = v ?? false),
                        ),
                        Expanded(child: Text(c['name'])),
                        SizedBox(
                          width: 100,
                          child: TextField(
                            controller: _amountControllers[c['id']],
                            enabled: selected,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(prefixText: '₹', isDense: true),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Period: ${_periodStart.toString().split(' ').first} → ${_periodEnd.toString().split(' ').first}'),
                  trailing: const Icon(Icons.calendar_today_outlined),
                  onTap: () => _pickDate(_periodStart, (d) => setState(() => _periodStart = d)),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Due Date: ${_dueDate.toString().split(' ').first}'),
                  trailing: const Icon(Icons.event_outlined),
                  onTap: () => _pickDate(_dueDate, (d) => setState(() => _dueDate = d)),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Create Invoice', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
    );
  }
}