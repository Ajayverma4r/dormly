// features/tenancies/presentation/add_tenant_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../structure/domain/hierarchy_level.dart';
import '../../structure/presentation/dynamic_dashboard/dynamic_dashboard_screen.dart'
    show hierarchyLevelsProvider;
import '../data/tenancy_repository.dart';
import '../domain/assignable_unit.dart';
import 'assignable_units_provider.dart';
import 'utils/tenancy_errors.dart';
import 'widgets/assignable_unit_search_field.dart';
import 'widgets/unit_selection_cascade.dart';

class AddTenantScreen extends ConsumerStatefulWidget {
  final String propertyId;

  /// When opened from a specific room/bed card, pre-select that unit.
  final String? nodeId;

  const AddTenantScreen({
    super.key,
    required this.propertyId,
    this.nodeId,
  });

  @override
  ConsumerState<AddTenantScreen> createState() => _AddTenantScreenState();
}

class _AddTenantScreenState extends ConsumerState<AddTenantScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _companyController = TextEditingController();
  final _aadhaarController = TextEditingController();
  final _depositController = TextEditingController();
  final _notesController = TextEditingController();
  DateTime? _moveInDate;
  bool _saving = false;
  String? _error;
  String? _selectedNodeId;
  bool _useSearchPicker = false;

  @override
  void initState() {
    super.initState();
    _selectedNodeId = widget.nodeId;
  }

  Future<void> _pickMoveInDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _moveInDate = picked);
  }

  String _normalizePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10) return '+91$digits';
    if (digits.length == 12 && digits.startsWith('91')) return '+$digits';
    if (raw.startsWith('+')) return raw;
    return '+$digits';
  }

  Future<void> _save() async {
    if (_selectedNodeId == null || _selectedNodeId!.isEmpty) {
      setState(() =>
          _error = 'Select a unit (bed, flat, shop, room…) before saving.');
      return;
    }
    if (_nameController.text.trim().isEmpty ||
        _phoneController.text.trim().isEmpty) {
      setState(() => _error = 'Name and phone number are required.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await ref.read(tenancyRepositoryProvider).create(
            widget.propertyId,
            nodeId: _selectedNodeId!,
            phone: _normalizePhone(_phoneController.text.trim()),
            fullName: _nameController.text.trim(),
            email: _emailController.text.trim().isEmpty
                ? null
                : _emailController.text.trim(),
            address: _addressController.text.trim().isEmpty
                ? null
                : _addressController.text.trim(),
            companyName: _companyController.text.trim().isEmpty
                ? null
                : _companyController.text.trim(),
            aadhaarNumber: _aadhaarController.text.trim().isEmpty
                ? null
                : _aadhaarController.text.trim(),
            moveInAt: _moveInDate?.toIso8601String(),
            securityDeposit: double.tryParse(_depositController.text.trim()),
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tenant added successfully')),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      final message = tenancyErrorMessage(e);
      setState(() => _error = message);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(String label, TextEditingController controller,
      {TextInputType? type, bool required = false, int? maxLength}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        keyboardType: type,
        maxLength: maxLength,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          counterText: maxLength != null ? '' : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildUnitSection(
      List<HierarchyLevel> levels, List<AssignableUnit> units) {
    if (units.isEmpty) {
      return Card(
        color: Colors.orange.shade50,
        child: const Padding(
          padding: EdgeInsets.all(14),
          child: Text(
            'No assignable units found. Add beds, flats, or rooms in Structure Settings first.',
          ),
        ),
      );
    }

    final selectedUnit =
        units.where((u) => u.nodeId == _selectedNodeId).firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Assign to unit',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
            TextButton(
              onPressed: () =>
                  setState(() => _useSearchPicker = !_useSearchPicker),
              child: Text(_useSearchPicker ? 'Use step picker' : 'Search units'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_useSearchPicker)
          AssignableUnitSearchField(
            units: units,
            selectedNodeId: _selectedNodeId,
            onSelected: (u) => setState(() => _selectedNodeId = u?.nodeId),
          )
        else
          UnitSelectionCascade(
            propertyId: widget.propertyId,
            levels: levels,
            initialNodeId: widget.nodeId,
            onNodeSelected: (id) => setState(() => _selectedNodeId = id),
          ),
        if (selectedUnit != null) ...[
          const SizedBox(height: 8),
          Text(
            selectedUnit.occupied
                ? 'Warning: ${selectedUnit.pathLabel} already has a tenant.'
                : 'Selected: ${selectedUnit.pathLabel}',
            style: TextStyle(
              fontSize: 12,
              color: selectedUnit.occupied ? Colors.red : Colors.green.shade700,
            ),
          ),
        ] else if (_selectedNodeId == null) ...[
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Select the exact bed, flat, or shop for this tenant.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final levelsAsync = ref.watch(hierarchyLevelsProvider(widget.propertyId));
    final unitsAsync = ref.watch(assignableUnitsProvider(widget.propertyId));

    final canSave = !_saving &&
        _selectedNodeId != null &&
        _nameController.text.trim().isNotEmpty &&
        _phoneController.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Add Tenant')),
      body: levelsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load structure: $e')),
        data: (levels) => unitsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Could not load units: $e')),
          data: (units) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (widget.nodeId != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Adding tenant to a specific unit',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                ),
              _buildUnitSection(levels, units),
              const SizedBox(height: 8),
              const Divider(),
              const SizedBox(height: 8),
              _field('Full Name', _nameController, required: true),
              _field('Mobile Number', _phoneController,
                  type: TextInputType.phone, required: true, maxLength: 10),
              _field('Email', _emailController,
                  type: TextInputType.emailAddress),
              _field('Address', _addressController),
              _field('Company Name (Optional)', _companyController),
              _field('Aadhaar Number', _aadhaarController),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_moveInDate == null
                    ? 'Move-in Date'
                    : 'Move-in: ${_moveInDate!.toLocal().toString().split(' ').first}'),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: _pickMoveInDate,
              ),
              const SizedBox(height: 14),
              _field('Security Deposit', _depositController,
                  type: TextInputType.number),
              _field('Notes', _notesController),
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
                    disabledBackgroundColor: Colors.grey.shade300,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: canSave ? _save : null,
                  child: _saving
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Save Tenant',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
