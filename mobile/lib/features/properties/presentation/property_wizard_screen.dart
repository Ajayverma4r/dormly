// features/properties/presentation/property_wizard_screen.dart
//
// A 3-step property creation wizard: Basic Info -> Configure Structure
// (enable/disable/rename each suggested level) -> Preview -> Success.
// This is where the spec's "MOST IMPORTANT FEATURE" actually lives: nothing
// is created until the user has seen and adjusted the suggested structure.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import '../data/properties_repository.dart';
import '../domain/property_monetization.dart';
import '../../auth/data/auth_repository.dart';
import '../../subscription/presentation/subscription_provider.dart';
import '../../subscription/presentation/paywall_screen.dart';
import '../../../core/widgets/dynamic_icon.dart';
import '../../../core/widgets/step_indicator.dart';
import '../../../core/theme/app_theme.dart';

const _levelDescriptions = {
  'building': 'For multiple buildings or blocks',
  'tower': 'For multiple towers or wings',
  'floor': 'For different floors or levels',
  'room': 'For rooms where residents stay',
  'bed': 'For individual beds',
  'flat': 'For individual flats or units',
  'department': 'For departments or teams',
  'cabin': 'For individual cabins',
  'warehouse': 'For the overall warehouse',
  'zone': 'For storage zones',
  'rack': 'For individual racks',
  'villa': 'For the whole villa',
};

class PropertyWizardScreen extends ConsumerStatefulWidget {
  const PropertyWizardScreen({super.key});
  @override
  ConsumerState<PropertyWizardScreen> createState() => _PropertyWizardScreenState();
}

class _PropertyWizardScreenState extends ConsumerState<PropertyWizardScreen> {
  int _step = 0; // 0=basic info, 1=configure, 2=preview, 3=success

  final _nameController = TextEditingController();
  final _cityController = TextEditingController();

  List<dynamic> _propertyTypes = [];
  String? _selectedTypeKey;
  bool _loadingTypes = true;

  List<Map<String, dynamic>> _template = [];
  final Map<String, bool> _enabled = {};
  final Map<String, TextEditingController> _nameControllers = {};
  bool _loadingTemplate = false;

  bool _creating = false;
  String? _error;
  Map<String, dynamic>? _createdProperty;

  @override
  void initState() {
    super.initState();
    _loadTypes();
  }

  Future<void> _loadTypes() async {
    try {
      final types = await ref.read(propertiesRepositoryProvider).listTypes();
      setState(() { _propertyTypes = types; _loadingTypes = false; });
    } catch (e) {
      setState(() { _loadingTypes = false; _error = 'Could not load property types: $e'; });
    }
  }

  Future<void> _goToConfigureStep() async {
    if (_nameController.text.trim().isEmpty || _selectedTypeKey == null) {
      setState(() => _error = 'Enter a property name and choose a property type.');
      return;
    }

    // Client-side commercial limit check before loading the template.
    if (await _shouldOpenPaywallForType(_selectedTypeKey!)) {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PaywallScreen()),
      );
      return;
    }

    setState(() { _loadingTemplate = true; _error = null; });
    try {
      final template = await ref.read(propertiesRepositoryProvider).previewTemplate(_selectedTypeKey!);
      _enabled.clear();
      _nameControllers.clear();
      for (final row in template) {
        _enabled[row['internal_key']] = true;
        _nameControllers[row['internal_key']] = TextEditingController(text: row['display_name']);
      }
      setState(() { _template = template; _step = 1; _loadingTemplate = false; });
    } catch (e) {
      setState(() { _loadingTemplate = false; _error = 'Could not load structure template: $e'; });
    }
  }

  Future<bool> _shouldOpenPaywallForType(String typeKey) async {
    if (PropertyMonetization.isFreeResidential(typeKey)) return false;

    final sub = ref.read(subscriptionProvider).valueOrNull;
    final isPaid = PropertyMonetization.isPaidPlan(
      sub?.subscription.planSlug,
      sub?.subscription.status,
    );
    if (isPaid) return false;

    final orgId = await ref.read(authRepositoryProvider).getOrganizationId();
    if (orgId == null) return false;

    try {
      final properties = await ref.read(propertiesRepositoryProvider).list(orgId);
      final commercialCount = properties
          .where((p) => PropertyMonetization.isCommercial(p['property_type_key'] as String?))
          .length;
      return PropertyMonetization.requiresUpgradeForCreate(
        typeKey: typeKey,
        commercialCount: commercialCount,
        isPaid: false,
      );
    } catch (_) {
      return false; // let backend enforce if list fails
    }
  }

  List<Map<String, dynamic>> get _enabledLevelsInOrder =>
      _template.where((row) => _enabled[row['internal_key']] == true).toList();

  Future<void> _createProperty() async {
   if (_template.isNotEmpty && _enabledLevelsInOrder.isEmpty) {
  setState(() => _error = 'Enable at least one level.');
  return;
}
    if (_selectedTypeKey != null && await _shouldOpenPaywallForType(_selectedTypeKey!)) {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PaywallScreen()),
      );
      return;
    }

    setState(() { _creating = true; _error = null; });
    try {
      final orgId = await ref.read(authRepositoryProvider).getOrganizationId();
      final overrides = <String, dynamic>{};
      for (final row in _template) {
        final key = row['internal_key'];
        overrides[key] = {
          'enabled': _enabled[key] ?? true,
          'displayName': _nameControllers[key]?.text.trim(),
        };
      }

      final property = await ref.read(propertiesRepositoryProvider).create({
        'organizationId': orgId,
        'name': _nameController.text.trim(),
        'propertyTypeKey': _selectedTypeKey,
        'city': _cityController.text.trim(),
        'timezone': 'Asia/Kolkata',
        'currency': 'INR',
        'language': 'en',
        'levelOverrides': overrides,
      });

      setState(() { _createdProperty = property; _step = 3; });
    } on DioException catch (e) {
      final data = e.response?.data;
      final code = data is Map ? data['code'] : null;
      if (e.response?.statusCode == 403 && code == 'SUBSCRIPTION_REQUIRED') {
        if (mounted) {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PaywallScreen()),
          );
        }
        setState(() => _error = null);
      } else {
        setState(() => _error = 'Could not create property: ${data is Map ? data['error'] : e}');
      }
    } catch (e) {
      setState(() => _error = 'Could not create property: $e');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_step == 3 && _createdProperty != null) {
      return _SuccessScreen(
        property: _createdProperty!,
        enabledLevels: _enabledLevelsInOrder,
        nameControllers: _nameControllers,
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFFEDEBFB),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: Text(
          ['Property Information', 'Configure Your Property', 'Preview Structure'][_step],
          style: const TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _step == 0 ? context.pop() : setState(() => _step -= 1),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: StepIndicator(
              currentStep: _step,
              labels: const ['Property Info', 'Structure', 'Review'],
            ),
          ),
        ),
      ),
      body: _step == 0
          ? _buildBasicInfoStep()
          : _step == 1
              ? _buildConfigureStep()
              : _buildPreviewStep(),
    );
  }

  Widget _buildBasicInfoStep() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Property Name *', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: _nameController,
          decoration: InputDecoration(hintText: 'Green Valley Hostel', border: OutlineInputBorder(borderRadius: BorderRadius.circular(14))),
        ),
        const SizedBox(height: 20),
        const Text('Location *', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: _cityController,
          decoration: InputDecoration(
            hintText: 'Indore, Madhya Pradesh',
            prefixIcon: const Icon(Icons.location_on_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 20),
        const Text('Property Type *', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          'Rental, House & Villa stay free forever. Apartment is limited to 1 building + 20 rooms on Free.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 8),
        _loadingTypes
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: _propertyTypes.map((t) {
                  final key = t['key'] as String;
                  final selected = _selectedTypeKey == key;
                  final freeForever = PropertyMonetization.isFreeResidential(key);
                  final badge = (t['monetization'] is Map
                          ? t['monetization']['badge'] as String?
                          : null) ??
                      PropertyMonetization.badgeFor(key);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => setState(() => _selectedTypeKey = key),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: selected ? AppColors.blueprint : Colors.grey.shade300,
                            width: selected ? 2 : 1,
                          ),
                          color: selected
                              ? AppColors.blueprint.withOpacity(0.04)
                              : Colors.white,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              selected
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              color: selected ? AppColors.blueprint : Colors.grey,
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    t['display_name'] ?? key,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                  if (t['description'] != null)
                                    Text(
                                      t['description'],
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: freeForever
                                    ? AppColors.positive.withOpacity(0.12)
                                    : PropertyMonetization.isApartment(key)
                                        ? AppColors.blueprint.withOpacity(0.12)
                                        : AppColors.caution.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                badge,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: freeForever
                                      ? AppColors.positive
                                      : PropertyMonetization.isApartment(key)
                                          ? AppColors.blueprint
                                          : AppColors.caution,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 28),
        SizedBox(
          height: 54,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2B5CFF),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: _loadingTemplate ? null : _goToConfigureStep,
            child: _loadingTemplate
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text('Continue', style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

 Widget _buildConfigureStep() {
    // "Custom" (and any type with no seeded template) intentionally has
    // nothing to configure — skip straight to creating an empty structure,
    // which the user then builds from scratch via the Structure Editor.
    if (_template.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.auto_awesome_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('No suggested structure for this type',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              "That's fine — we'll create the property with an empty structure, "
              'and you can build your own levels afterwards from Structure Settings.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity, height: 54,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2B5CFF),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _creating ? null : _createProperty,
                child: _creating
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Create Property',
                        style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text(
            'Select the sections you want to manage in your property. You can rename them as per your preference.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: _template.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final row = _template[index];
              final key = row['internal_key'];
              final isEnabled = _enabled[key] ?? true;
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        DynamicIcon(name: row['icon'], size: 24),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(row['display_name'], style: const TextStyle(fontWeight: FontWeight.w700)),
                              Text(_levelDescriptions[key] ?? 'Configure this level',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                            ],
                          ),
                        ),
                        Switch(
                          value: isEnabled,
                          onChanged: (v) => setState(() => _enabled[key] = v),
                        ),
                      ],
                    ),
                    if (isEnabled) ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: _nameControllers[key],
                        decoration: InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
        if (_error != null)
          Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: const TextStyle(color: Colors.red))),
        Padding(
          padding: const EdgeInsets.all(20),
          child: SizedBox(
            height: 54,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2B5CFF),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: () => setState(() => _step = 2),
              child: const Text('Continue', style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewStep() {
    final levels = _enabledLevelsInOrder;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text("Here's how your property structure will look.",
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: levels.length,
            itemBuilder: (context, i) {
              final row = levels[i];
              final key = row['internal_key'];
              return Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F8FC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        DynamicIcon(name: row['icon'], size: 22),
                        const SizedBox(width: 10),
                        Text(_nameControllers[key]?.text ?? row['display_name'],
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  if (i != levels.length - 1)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Icon(Icons.arrow_downward, size: 18, color: Colors.grey),
                    ),
                ],
              );
            },
          ),
        ),
        if (_error != null)
          Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: const TextStyle(color: Colors.red))),
        Padding(
          padding: const EdgeInsets.all(20),
          child: SizedBox(
            height: 54,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2B5CFF),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _creating ? null : _createProperty,
              child: _creating
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Create Property', style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ],
    );
  }
}

class _SuccessScreen extends StatelessWidget {
  final Map<String, dynamic> property;
  final List<Map<String, dynamic>> enabledLevels;
  final Map<String, TextEditingController> nameControllers;

  const _SuccessScreen({
    required this.property,
    required this.enabledLevels,
    required this.nameControllers,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 90, height: 90,
                decoration: const BoxDecoration(color: Color(0xFFE6F7ED), shape: BoxShape.circle),
                child: const Icon(Icons.check, color: Color(0xFF2ECC71), size: 48),
              ),
              const SizedBox(height: 20),
              const Text('Property Created!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('Your property has been set up successfully.',
                  style: TextStyle(color: Colors.grey.shade600)),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade200),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(property['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    if (property['city'] != null)
                      Text(property['city'], style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                    const SizedBox(height: 12),
                    ...enabledLevels.map((row) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text('• ${nameControllers[row['internal_key']]?.text ?? row['display_name']}'),
                        )),
                  ],
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity, height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2B5CFF),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () => context.go('/dashboard/${property['id']}', extra: {'propertyName': property['name']}),
                  child: const Text('Go to Dashboard',
                      style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}