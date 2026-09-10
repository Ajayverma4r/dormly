// features/tenancies/presentation/add_tenant_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../billing/presentation/create_invoice_screen.dart';
import '../../structure/domain/hierarchy_level.dart';
import '../../structure/presentation/dynamic_dashboard/dynamic_dashboard_screen.dart'
    show hierarchyLevelsProvider;
import '../../structure/presentation/rooms/add_room_bottom_sheet.dart';
import '../data/tenancy_repository.dart';
import '../domain/assignable_unit.dart';
import 'assignable_units_provider.dart';
import 'utils/aadhaar_validation.dart';
import 'utils/tenancy_errors.dart';
import 'widgets/assignable_unit_search_field.dart';
import 'widgets/unit_selection_cascade.dart';

/// Result popped when the user chooses to create a room from the empty state.
const addTenantCreateRoomResult = 'create_room';

/// Opens Add Tenant; if the user taps "Create Room Now", opens the room sheet.
Future<void> openAddTenantFlow({
  required BuildContext context,
  required WidgetRef ref,
  required String propertyId,
  String? nodeId,
}) async {
  final result = await Navigator.of(context).push<Object?>(
    MaterialPageRoute(
      builder: (_) => AddTenantScreen(
        propertyId: propertyId,
        nodeId: nodeId,
      ),
    ),
  );
  if (result == addTenantCreateRoomResult && context.mounted) {
    await showAddRoomBottomSheet(
      context: context,
      ref: ref,
      propertyId: propertyId,
    );
    ref.invalidate(assignableUnitsProvider(propertyId));
  }
}

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
  final _formKey = GlobalKey<FormState>();
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
      initialDate: _moveInDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
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
    if (!_formKey.currentState!.validate()) return;
    if (_moveInDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '⚠️ Move-in Date is mandatory for billing purposes.',
          ),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final created = await ref.read(tenancyRepositoryProvider).create(
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
            moveInAt: _moveInDate!.toIso8601String(),
            securityDeposit: double.tryParse(_depositController.text.trim()),
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
          );
      if (!mounted) return;

      final tenancyId = created['id']?.toString() ?? '';
      final tenantName = _nameController.text.trim();
      final roomId = _selectedNodeId!;
      final units =
          ref.read(assignableUnitsProvider(widget.propertyId)).valueOrNull;
      final selectedUnit =
          units?.where((u) => u.nodeId == roomId).firstOrNull;

      ref.invalidate(assignableUnitsProvider(widget.propertyId));

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tenant added successfully')),
      );

      if (tenancyId.isEmpty) {
        Navigator.of(context).pop(true);
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CreateInvoiceScreen(
            propertyId: widget.propertyId,
            preSelectedTenantId: tenancyId,
            preSelectedTenantName: tenantName,
            roomId: roomId,
            preSelectedRoomName: selectedUnit?.pathLabel,
            isFromOnboarding: true,
          ),
        ),
      );
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
      {TextInputType? type,
      bool required = false,
      int? maxLength,
      String? Function(String?)? validator,
      List<TextInputFormatter>? inputFormatters}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        keyboardType: type,
        maxLength: maxLength,
        inputFormatters: inputFormatters,
        validator: validator ??
            (required
                ? (v) =>
                    (v == null || v.trim().isEmpty) ? '$label is required' : null
                : null),
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

  Widget _noRoomsEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.bedroom_parent_outlined,
              size: 60,
              color: AppColors.primary,
            ),
            const SizedBox(height: 20),
            const Text(
              'No Rooms Available',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              "You haven't created any rooms yet. Please create a room first to add a tenant.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: AppColors.slate,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () =>
                    Navigator.of(context).pop(addTenantCreateRoomResult),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.add),
                label: const Text(
                  'Create Room Now',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
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
          data: (units) {
            if (units.isEmpty) {
              return _noRoomsEmptyState();
            }
            return Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (widget.nodeId != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Adding tenant to a specific unit',
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 13),
                      ),
                    ),
                  _buildUnitSection(levels, units),
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 8),
                  _field('Full Name', _nameController, required: true),
                  _field('Mobile Number', _phoneController,
                      type: TextInputType.phone,
                      required: true,
                      maxLength: 10),
                  _field('Email', _emailController,
                      type: TextInputType.emailAddress),
                  _field('Address', _addressController),
                  _field('Company Name (Optional)', _companyController),
                  _field('Aadhaar Number', _aadhaarController,
                      type: TextInputType.number,
                      maxLength: 12,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      validator: (v) =>
                          validateAadhaarNumber(v, required: false)),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_moveInDate == null
                        ? 'Move-in Date *'
                        : 'Move-in: ${DateFormat('dd MMM yyyy').format(_moveInDate!)}'),
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
                        backgroundColor: AppColors.blueprint,
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
            );
          },
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
