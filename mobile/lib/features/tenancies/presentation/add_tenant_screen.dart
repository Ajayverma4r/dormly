// features/tenancies/presentation/add_tenant_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../billing/presentation/create_invoice_screen.dart';
import '../../properties/data/properties_repository.dart';
import '../../properties/domain/property_archetype.dart';
import '../../structure/domain/hierarchy_level.dart';
import '../../structure/presentation/dynamic_dashboard/dynamic_dashboard_screen.dart'
    show hierarchyLevelsProvider;
import '../../structure/presentation/rooms/add_room_bottom_sheet.dart';
import '../data/tenancy_repository.dart';
import '../domain/assignable_unit.dart';
import 'assignable_units_provider.dart';
import 'create_space_screen.dart';
import 'tenant_profile_screen.dart';
import 'utils/aadhaar_validation.dart';
import 'utils/tenancy_errors.dart';
import 'widgets/assignable_unit_search_field.dart';
import 'widgets/unit_selection_cascade.dart';

/// Result popped when the user chooses to create a room from the empty state.
const addTenantCreateRoomResult = 'create_room';

/// Prefill for Re-Admit / Assign New Room from a past tenancy.
class TenantPrefill {
  final String? fullName;
  final String? phone;
  final String? email;
  final String? address;
  final String? companyName;
  final String? aadhaarNumber;
  final String? notes;

  const TenantPrefill({
    this.fullName,
    this.phone,
    this.email,
    this.address,
    this.companyName,
    this.aadhaarNumber,
    this.notes,
  });

  factory TenantPrefill.fromTenancy(Map<String, dynamic> t) {
    return TenantPrefill(
      fullName: t['full_name']?.toString(),
      phone: t['phone']?.toString(),
      email: t['email']?.toString(),
      address: t['address']?.toString(),
      companyName: (t['company_name'] ?? t['companyName'])?.toString(),
      aadhaarNumber: (t['aadhaar_number'] ?? t['aadhaarNumber'])?.toString(),
      notes: t['notes']?.toString(),
    );
  }
}

/// Opens Add Tenant; if the user taps "Create Room Now", opens the room sheet.
Future<void> openAddTenantFlow({
  required BuildContext context,
  required WidgetRef ref,
  required String propertyId,
  String? nodeId,
  TenantPrefill? prefill,
}) async {
  final result = await Navigator.of(context).push<Object?>(
    MaterialPageRoute(
      builder: (_) => AddTenantScreen(
        propertyId: propertyId,
        nodeId: nodeId,
        prefill: prefill,
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

  /// When re-admitting a checked-out guest, pre-fill identity fields.
  final TenantPrefill? prefill;

  const AddTenantScreen({
    super.key,
    required this.propertyId,
    this.nodeId,
    this.prefill,
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
  final _rentController = TextEditingController();
  final _notesController = TextEditingController();
  DateTime? _moveInDate;
  bool _saving = false;
  String? _error;
  String? _selectedNodeId;
  /// When set, submit creates this space on the fly (rental empty / new space).
  String? _newSpaceName;
  /// Display label for a space just created on CreateSpaceScreen.
  String? _selectedSpaceLabel;
  bool _addingNewSpace = false;
  bool _useSearchPicker = false;
  /// Default true — roll unbilled months into the first invoice.
  bool _includePastRentArrears = true;
  PropertyArchetype? _archetype;
  bool _loadingArchetype = true;

  bool get _isRentalHouse =>
      _archetype == PropertyArchetype.individualLease;

  /// Progressive disclosure: tenant fields appear only after a space is ready.
  bool get _rentalSpaceReady {
    if (_selectedNodeId != null && _selectedNodeId!.isNotEmpty) return true;
    final name = _newSpaceName?.trim() ?? '';
    return name.isNotEmpty;
  }

  String? get _rentalSpaceDisplayLabel {
    if (_newSpaceName != null && _newSpaceName!.trim().isNotEmpty) {
      return _newSpaceName!.trim();
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _selectedNodeId = widget.nodeId;
    final p = widget.prefill;
    if (p != null) {
      if (p.fullName != null) _nameController.text = p.fullName!;
      if (p.phone != null) {
        final digits = p.phone!.replaceAll(RegExp(r'\D'), '');
        _phoneController.text = digits.length > 10
            ? digits.substring(digits.length - 10)
            : digits;
      }
      if (p.email != null) _emailController.text = p.email!;
      if (p.address != null) _addressController.text = p.address!;
      if (p.companyName != null) _companyController.text = p.companyName!;
      if (p.aadhaarNumber != null) {
        _aadhaarController.text = p.aadhaarNumber!;
      }
      if (p.notes != null) _notesController.text = p.notes!;
    }
    _loadArchetype();
  }

  Future<void> _loadArchetype() async {
    try {
      final property =
          await ref.read(propertiesRepositoryProvider).getById(widget.propertyId);
      if (!mounted) return;
      setState(() {
        _archetype = propertyArchetypeFromProperty(property);
        _loadingArchetype = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _archetype = PropertyArchetype.sharedLiving;
        _loadingArchetype = false;
      });
    }
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

  bool get _moveInIsBackdated {
    if (_moveInDate == null) return false;
    final now = DateTime.now();
    final moveMonth = DateTime(_moveInDate!.year, _moveInDate!.month);
    final currentMonth = DateTime(now.year, now.month);
    return moveMonth.isBefore(currentMonth);
  }

  Future<void> _save() async {
    if (_isRentalHouse) {
      final creatingNew =
          _addingNewSpace || (_selectedNodeId == null || _selectedNodeId!.isEmpty);
      final newName = _newSpaceName?.trim() ?? '';
      if (creatingNew && newName.isEmpty) {
        setState(() => _error = 'Select a space or enter a new space name.');
        return;
      }
      if (!creatingNew &&
          (_selectedNodeId == null || _selectedNodeId!.isEmpty)) {
        setState(() => _error = 'Select a space before saving.');
        return;
      }
      if (double.tryParse(_rentController.text.trim()) == null) {
        setState(() => _error = 'Enter a valid rent amount.');
        return;
      }
    } else if (_selectedNodeId == null || _selectedNodeId!.isEmpty) {
      setState(() =>
          _error = 'Select a space (bed, flat, shop, room…) before saving.');
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
      final creatingNewSpace = _isRentalHouse &&
          (_addingNewSpace ||
              _selectedNodeId == null ||
              _selectedNodeId!.isEmpty);

      final created = await ref.read(tenancyRepositoryProvider).create(
            widget.propertyId,
            nodeId: creatingNewSpace ? null : _selectedNodeId,
            unitName: creatingNewSpace ? _newSpaceName!.trim() : null,
            phone: _normalizePhone(_phoneController.text.trim()),
            fullName: _nameController.text.trim(),
            email: _isRentalHouse
                ? null
                : (_emailController.text.trim().isEmpty
                    ? null
                    : _emailController.text.trim()),
            address: _isRentalHouse
                ? null
                : (_addressController.text.trim().isEmpty
                    ? null
                    : _addressController.text.trim()),
            companyName: _isRentalHouse
                ? null
                : (_companyController.text.trim().isEmpty
                    ? null
                    : _companyController.text.trim()),
            aadhaarNumber: _isRentalHouse
                ? null
                : (_aadhaarController.text.trim().isEmpty
                    ? null
                    : _aadhaarController.text.trim()),
            moveInAt: _moveInDate!.toIso8601String(),
            securityDeposit: double.tryParse(_depositController.text.trim()),
            monthlyRent: double.tryParse(_rentController.text.trim()),
            notes: _isRentalHouse
                ? null
                : (_notesController.text.trim().isEmpty
                    ? null
                    : _notesController.text.trim()),
            includePastRentArrears:
                _isRentalHouse ? true : _includePastRentArrears,
          );
      if (!mounted) return;

      final tenancyId = created['id']?.toString() ?? '';
      ref.invalidate(assignableUnitsProvider(widget.propertyId));

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tenant added successfully ✅')),
      );

      if (tenancyId.isEmpty) {
        Navigator.of(context).pop(true);
        return;
      }

      if (_isRentalHouse) {
        Navigator.of(context).pushReplacement(
          TenantProfileScreen.route(
            propertyId: widget.propertyId,
            tenancyId: tenancyId,
            initialTenancy: created,
          ),
        );
        return;
      }

      final tenantName = _nameController.text.trim();
      final roomId = created['node_id']?.toString() ??
          created['nodeId']?.toString() ??
          _selectedNodeId ??
          '';
      final units =
          ref.read(assignableUnitsProvider(widget.propertyId)).valueOrNull;
      final selectedUnit =
          units?.where((u) => u.nodeId == roomId).firstOrNull;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CreateInvoiceScreen(
            propertyId: widget.propertyId,
            preSelectedTenantId: tenancyId,
            preSelectedTenantName: tenantName,
            roomId: roomId.isEmpty ? null : roomId,
            preSelectedRoomName: selectedUnit?.pathLabel,
            isFromOnboarding: true,
            includePastRentArrears: _includePastRentArrears,
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

  Future<void> _openCreateSpaceSheet() async {
    final result = await openCreateSpaceScreen(
      context: context,
      propertyId: widget.propertyId,
    );
    if (result == null || !mounted) return;
    ref.invalidate(assignableUnitsProvider(widget.propertyId));
    setState(() {
      _addingNewSpace = false;
      _newSpaceName = null;
      _selectedNodeId = result.nodeId;
      _selectedSpaceLabel = result.name;
      if (result.monthlyRent != null) {
        _rentController.text = _formatAmount(result.monthlyRent!);
      }
      if (result.securityDeposit != null) {
        _depositController.text = _formatAmount(result.securityDeposit!);
      }
      _error = null;
    });
  }

  String _formatAmount(double value) {
    if (value == value.roundToDouble()) return value.round().toString();
    return value.toString();
  }

  void _clearRentalSpaceAssignment() {
    setState(() {
      _addingNewSpace = false;
      _newSpaceName = null;
      _selectedNodeId = null;
      _selectedSpaceLabel = null;
    });
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
                'Assign to space',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
            TextButton(
              onPressed: () =>
                  setState(() => _useSearchPicker = !_useSearchPicker),
              child:
                  Text(_useSearchPicker ? 'Use step picker' : 'Search spaces'),
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

  Widget _stepCard({
    required String step,
    required String title,
    required IconData icon,
    required Widget child,
    bool complete = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: complete
              ? AppColors.primary.withValues(alpha: 0.35)
              : AppColors.hairline,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: complete
                      ? AppColors.primary
                      : AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  complete ? Icons.check_rounded : icon,
                  size: 20,
                  color: complete ? Colors.white : AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                        color: complete
                            ? AppColors.primary
                            : AppColors.slate,
                      ),
                    ),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildRentalAssignSpaceCard(List<AssignableUnit> units) {
    final hasExisting = units.isNotEmpty;
    final draftName = _rentalSpaceDisplayLabel;
    final selectedExisting = units
        .where((u) => u.nodeId == _selectedNodeId)
        .firstOrNull;
    final selectedLabel = selectedExisting?.pathLabel ??
        _selectedSpaceLabel ??
        draftName;

    Widget selectedBanner({
      required String label,
      required VoidCallback onChange,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.primarySoft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Space ready',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryDark,
                    ),
                  ),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: onChange,
              child: const Text('Change'),
            ),
          ],
        ),
      );
    }

    // Pending draft name (legacy create-on-save path).
    if (_addingNewSpace && draftName != null) {
      return _stepCard(
        step: 'STEP 1',
        title: 'Assign Space',
        icon: Icons.home_work_outlined,
        complete: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            selectedBanner(
              label: draftName,
              onChange: () {
                if (hasExisting) {
                  _clearRentalSpaceAssignment();
                } else {
                  _openCreateSpaceSheet();
                }
              },
            ),
            const SizedBox(height: 6),
            Text(
              'This space will be created when you save the tenant.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    // Just created / selected — show confirmation even before list refresh.
    if (_selectedNodeId != null &&
        selectedLabel != null &&
        selectedExisting == null &&
        !hasExisting) {
      return _stepCard(
        step: 'STEP 1',
        title: 'Assign Space',
        icon: Icons.home_work_outlined,
        complete: true,
        child: selectedBanner(
          label: selectedLabel,
          onChange: _openCreateSpaceSheet,
        ),
      );
    }

    if (!hasExisting) {
      return _stepCard(
        step: 'STEP 1',
        title: 'Which space are they renting?',
        icon: Icons.home_work_outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'No rental spaces yet',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Create a space first, then add this tenant to it.',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _openCreateSpaceSheet,
                icon: const Icon(Icons.add_home_outlined),
                label: const Text(
                  '+ Create Space',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Existing spaces — dropdown + create new.
    return _stepCard(
      step: 'STEP 1',
      title: 'Which space are they renting?',
      icon: Icons.home_work_outlined,
      complete: _selectedNodeId != null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            value: units.any((u) => u.nodeId == _selectedNodeId)
                ? _selectedNodeId
                : null,
            decoration: InputDecoration(
              labelText: 'Space',
              prefixIcon: const Icon(Icons.apartment_outlined),
              filled: true,
              fillColor: AppColors.canvas,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.hairline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: AppColors.primary,
                  width: 1.5,
                ),
              ),
            ),
            items: units
                .map(
                  (u) => DropdownMenuItem(
                    value: u.nodeId,
                    child: Text(
                      u.occupied
                          ? '${u.pathLabel} (occupied)'
                          : u.pathLabel,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (id) => setState(() {
              _selectedNodeId = id;
              _addingNewSpace = false;
              _newSpaceName = null;
              final match =
                  units.where((u) => u.nodeId == id).firstOrNull;
              _selectedSpaceLabel = match?.pathLabel;
              if (match?.monthlyRent != null) {
                _rentController.text = _formatAmount(match!.monthlyRent!);
              }
              if (match?.securityDeposit != null) {
                _depositController.text =
                    _formatAmount(match!.securityDeposit!);
              }
              _error = null;
            }),
          ),
          if (selectedExisting?.occupied == true) ...[
            const SizedBox(height: 8),
            Text(
              'This space already has a tenant.',
              style: TextStyle(fontSize: 12, color: Colors.red.shade700),
            ),
          ],
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _openCreateSpaceSheet,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('+ Create Space'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRentalForm(List<AssignableUnit> units) {
    final spaceReady = _rentalSpaceReady;
    final canSave = !_saving &&
        spaceReady &&
        _nameController.text.trim().isNotEmpty &&
        _phoneController.text.trim().isNotEmpty &&
        _moveInDate != null &&
        double.tryParse(_rentController.text.trim()) != null;

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          _buildRentalAssignSpaceCard(units),
          AnimatedSize(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: spaceReady
                ? Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: _stepCard(
                      step: 'STEP 2',
                      title: 'Tenant Details',
                      icon: Icons.person_outline_rounded,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _field('Full Name', _nameController, required: true),
                          _field('Mobile Number', _phoneController,
                              type: TextInputType.phone,
                              required: true,
                              maxLength: 10),
                          Material(
                            color: AppColors.canvas,
                            borderRadius: BorderRadius.circular(12),
                            child: ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: const BorderSide(
                                  color: AppColors.hairline,
                                ),
                              ),
                              title: Text(
                                _moveInDate == null
                                    ? 'Move-in Date *'
                                    : 'Move-in: ${DateFormat('dd MMM yyyy').format(_moveInDate!)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: _moveInDate == null
                                      ? AppColors.slate
                                      : AppColors.ink,
                                ),
                              ),
                              trailing: const Icon(
                                Icons.calendar_today_outlined,
                                color: AppColors.primary,
                              ),
                              onTap: _pickMoveInDate,
                            ),
                          ),
                          const SizedBox(height: 14),
                          _field('Rent Amount', _rentController,
                              type: TextInputType.number, required: true),
                          _field('Security Deposit', _depositController,
                              type: TextInputType.number),
                          if (_error != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              _error!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ],
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 54,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                disabledBackgroundColor: Colors.grey.shade300,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: canSave ? _save : null,
                              child: _saving
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'Add Tenant',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          if (!spaceReady) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                Icon(Icons.lock_outline, size: 16, color: Colors.grey.shade500),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tenant details unlock after you assign a space.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
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
        !_loadingArchetype &&
        _selectedNodeId != null &&
        _nameController.text.trim().isNotEmpty &&
        _phoneController.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.prefill != null ? 'Re-Admit Guest' : 'Add Tenant',
        ),
      ),
      body: _loadingArchetype
          ? const Center(child: CircularProgressIndicator())
          : levelsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  Center(child: Text('Could not load structure: $e')),
              data: (levels) => unitsAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) =>
                    Center(child: Text('Could not load spaces: $e')),
                data: (units) {
                  if (units.isEmpty && !_isRentalHouse) {
                    return _noRoomsEmptyState();
                  }

                  // Rental: always show the slim form — create a space on save if needed.
                  if (_isRentalHouse) {
                    return _buildRentalForm(units);
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
                              'Adding tenant to a specific space',
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
                        if (_moveInIsBackdated) ...[
                          const SizedBox(height: 4),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _includePastRentArrears,
                            onChanged: (v) => setState(
                              () => _includePastRentArrears = v ?? true,
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                            title: const Text(
                              'Add unbilled past rent to the first invoice?',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              'Unbilled months since move-in will appear as Previous Dues on the first invoice.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        _field('Rent Amount', _rentController,
                            type: TextInputType.number),
                        _field('Security Deposit', _depositController,
                            type: TextInputType.number),
                        _field('Notes', _notesController),
                        if (_error != null) ...[
                          const SizedBox(height: 8),
                          Text(_error!,
                              style: const TextStyle(color: Colors.red)),
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
                                ? const CircularProgressIndicator(
                                    color: Colors.white)
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
