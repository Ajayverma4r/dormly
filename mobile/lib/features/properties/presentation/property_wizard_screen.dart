// features/properties/presentation/property_wizard_screen.dart
//
// Progressive property onboarding:
// Details → Structure → Buildings → Rooms → Beds (optional) → Review
// Local state lives in [propertySetupProvider] until the final create call.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/step_indicator.dart';
import '../../auth/data/auth_repository.dart';
import '../../structure/data/structure_repository.dart';
import '../../structure/domain/hierarchy_level.dart';
import '../../subscription/presentation/paywall_screen.dart';
import '../../subscription/presentation/subscription_provider.dart';
import '../data/properties_repository.dart';
import '../domain/property_archetype.dart';
import '../domain/property_monetization.dart';
import '../domain/property_setup_state.dart';

class PropertyWizardScreen extends ConsumerStatefulWidget {
  const PropertyWizardScreen({super.key});
  @override
  ConsumerState<PropertyWizardScreen> createState() =>
      _PropertyWizardScreenState();
}

class _PropertyWizardScreenState extends ConsumerState<PropertyWizardScreen> {
  /// 0 Details · 1 Structure · 2 Buildings · 3 Rooms · 4 Beds · 5 Review
  int _step = 0;

  final _nameController = TextEditingController();
  final _cityController = TextEditingController();

  String? _selectedTypeKey;
  bool _loadingTypes = true;

  bool _creating = false;
  String? _error;
  /// Set after a rental-house property is created (success step).
  Map<String, dynamic>? _createdRentalProperty;

  /// Inline space-details editor inside Step 2 (never navigates to CreateSpaceScreen).
  RentalSpaceType? _draftSpaceType;
  String? _draftSpaceId;
  final _draftNameCtrl = TextEditingController();
  final _draftRentCtrl = TextEditingController();
  final _draftDepositCtrl = TextEditingController();
  final List<String> _draftFloors = [
    'Ground Floor',
    '1st Floor',
    '2nd Floor',
    '3rd Floor',
    'Roof',
  ];
  String? _draftFloorLabel;

  @override
  void initState() {
    super.initState();
    // Fresh create only — never resume leftover setup as if editing an
    // existing property.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(propertySetupProvider.notifier).reset();
    });
    _loadTypes();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cityController.dispose();
    _draftNameCtrl.dispose();
    _draftRentCtrl.dispose();
    _draftDepositCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTypes() async {
    try {
      await ref.read(propertiesRepositoryProvider).listTypes();
    } catch (_) {
      // Archetype cards use fixed catalog keys; types load is best-effort.
    }
    if (mounted) setState(() => _loadingTypes = false);
  }

  int get _indicatorStep {
    if (_step == 0) return 0;
    if (_step == 6) return 2; // Rental success → Review complete
    if (_step == 7) return 1; // Spaces setup
    if (_step <= 4) return 1;
    return 2;
  }

  String get _appBarTitle {
    final setup = ref.read(propertySetupProvider);
    switch (_step) {
      case 0:
        return 'Property Information';
      case 1:
        return 'How is it organized?';
      case 2:
        return setup.isApartment
            ? 'Set up your towers'
            : 'Set up your buildings';
      case 3:
        return setup.isApartment ? 'Add flats' : 'Add rooms';
      case 4:
        return 'Your rooms are ready 🎉';
      case 5:
        return 'Review your property';
      case 6:
        return 'You\'re all set';
      case 7:
        return 'Set up your spaces';
      default:
        return 'Create Property';
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
      final properties =
          await ref.read(propertiesRepositoryProvider).list(orgId);
      final commercialCount = properties
          .where((p) =>
              PropertyMonetization.isCommercial(p['property_type_key'] as String?))
          .length;
      return PropertyMonetization.requiresUpgradeForCreate(
        typeKey: typeKey,
        commercialCount: commercialCount,
        isPaid: false,
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> _goFromDetails() async {
    if (_nameController.text.trim().isEmpty || _selectedTypeKey == null) {
      setState(
        () => _error = 'Enter a property name and choose a property type.',
      );
      return;
    }

    if (await _shouldOpenPaywallForType(_selectedTypeKey!)) {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PaywallScreen()),
      );
      return;
    }

    final notifier = ref.read(propertySetupProvider.notifier);
    notifier.setDetails(
      name: _nameController.text.trim(),
      city: _cityController.text.trim(),
      propertyTypeKey: _selectedTypeKey!,
    );

    final archetype = propertyArchetypeFromKey(_selectedTypeKey);

    if (archetype == PropertyArchetype.individualLease) {
      // 2-step rental: Details → Set up spaces → create → success.
      notifier.initRentalSpacesFlow();
      setState(() {
        _error = null;
        _step = 7;
      });
      return;
    }

    late final int nextStep;
    switch (archetype) {
      case PropertyArchetype.gatedCommunity:
        notifier.initApartmentFlow();
        nextStep = 2;
      case PropertyArchetype.sharedLiving:
        nextStep = 1;
      case PropertyArchetype.individualLease:
        // Handled above — create + success.
        return;
    }

    setState(() {
      _error = null;
      _step = nextStep;
    });
  }

  /// Creates a rental house and seeds planned spaces, then shows success.
  Future<void> _createRentalPropertyAndShowSuccess() async {
    final setup = ref.read(propertySetupProvider);
    final typeKey = setup.propertyTypeKey ?? _selectedTypeKey;
    if (typeKey == null || setup.propertyName.trim().isEmpty) {
      setState(() => _error = 'Enter a property name and choose a property type.');
      return;
    }
    // Spaces are optional — user may skip setup and add them later from Dashboard.

    setState(() {
      _creating = true;
      _error = null;
    });

    try {
      final authRepo = ref.read(authRepositoryProvider);
      final ctx = await authRepo.ensureOwnerWorkspace();
      final orgId = ctx['id']?.toString() ?? await authRepo.getOrganizationId();
      if (orgId == null || orgId.isEmpty) {
        throw Exception('Could not establish a workspace. Please sign in again.');
      }

      final property = await ref.read(propertiesRepositoryProvider).create({
        'organizationId': orgId,
        'name': setup.propertyName.trim(),
        'propertyTypeKey': typeKey,
        'city': setup.city.trim(),
        'timezone': 'Asia/Kolkata',
        'currency': 'INR',
        'language': 'en',
        'levelOverrides': setup.levelOverridesForApi(),
      });

      final propertyId = property['id']?.toString();
      if (propertyId == null || propertyId.isEmpty) {
        throw Exception('Property created but no id returned.');
      }

      await _seedRentalSpaces(propertyId: propertyId, setup: setup);

      ref.read(propertySetupProvider.notifier).reset();

      if (!mounted) return;
      setState(() {
        _createdRentalProperty = property;
        _step = 6;
      });
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
        setState(
          () => _error =
              'Could not create property: ${data is Map ? data['error'] : e}',
        );
      }
    } catch (e) {
      setState(() => _error = 'Could not create property: $e');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _seedRentalSpaces({
    required String propertyId,
    required PropertySetupState setup,
  }) async {
    final repo = ref.read(structureRepositoryProvider);
    final levels = await repo.listLevels(propertyId);
    final enabled = levels.where((l) => l.isEnabled).toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

    final propertyLevel = _firstLevelOf(enabled, const ['property']);
    final unitLevel = _firstLevelOf(enabled, const ['unit', 'room', 'flat']);
    if (unitLevel == null) return;

    String? propertyRootId;
    if (propertyLevel != null) {
      final root = await repo.createNode(
        propertyId,
        levelId: propertyLevel.id,
        parentNodeId: null,
        name: setup.propertyName.trim().isEmpty
            ? 'Main Property'
            : setup.propertyName.trim(),
      );
      propertyRootId = root['id']?.toString();
    }

    // Parents first (floors), then children (rooms).
    final localToRemote = <String, String>{};
    final ordered = [
      ...setup.rentalSpaces.where((s) => s.parentId == null),
      ...setup.rentalSpaces.where((s) => s.parentId != null),
    ];

    for (final space in ordered) {
      String? parentRemote = propertyRootId;

      // Create/reuse a floor container when this space has a floor label.
      final floorLabel = space.floorLabel?.trim();
      if (floorLabel != null && floorLabel.isNotEmpty) {
        final floorKey = 'floor:${floorLabel.toLowerCase()}';
        if (localToRemote.containsKey(floorKey)) {
          parentRemote = localToRemote[floorKey];
        } else {
          final floorNode = await repo.createNode(
            propertyId,
            levelId: unitLevel.id,
            parentNodeId: propertyRootId,
            name: floorLabel,
            metadata: {'space_type': RentalSpaceType.floor.apiValue},
          );
          final floorId = floorNode['id']?.toString();
          if (floorId != null) {
            localToRemote[floorKey] = floorId;
            parentRemote = floorId;
          }
        }
      } else if (space.parentId != null) {
        parentRemote = localToRemote[space.parentId] ?? propertyRootId;
      }

      final created = await repo.createNode(
        propertyId,
        levelId: unitLevel.id,
        parentNodeId: parentRemote,
        name: space.name,
        monthlyRent: space.monthlyRent,
        securityDeposit: space.securityDeposit,
        metadata: {
          'space_type': space.type.apiValue,
        },
      );
      final remoteId = created['id']?.toString();
      if (remoteId != null) localToRemote[space.id] = remoteId;
    }
  }

  void _continueFromRentalSpaces() {
    final setup = ref.read(propertySetupProvider);
    // Spaces are optional. Only validate spaces the user already added.
    for (final s in setup.assignableRentalSpaces) {
      if (s.name.trim().isEmpty) {
        setState(() => _error = 'Every space needs a name.');
        return;
      }
      if (s.monthlyRent == null || s.monthlyRent! <= 0) {
        setState(() => _error = 'Every space needs a monthly rent.');
        return;
      }
    }
    // Stay in the property wizard — go to Review (never CreateSpaceScreen).
    setState(() {
      _error = null;
      _draftSpaceType = null;
      _draftSpaceId = null;
      _step = 5;
    });
  }

  /// Create the property now; spaces can be added later from Dashboard → Spaces.
  void _skipRentalSpaceSetup() {
    setState(() {
      _error = null;
      _draftSpaceType = null;
      _draftSpaceId = null;
      _step = 5;
    });
  }

  void _goBack() {
    if (_step == 0 || _step == 6) {
      if (_step == 6 && _createdRentalProperty != null) {
        _goToCreatedDashboard();
        return;
      }
      context.pop();
      return;
    }
    final setup = ref.read(propertySetupProvider);
    var prev = _step - 1;

    if (_step == 7) {
      if (_draftSpaceType != null) {
        setState(() {
          _error = null;
          _draftSpaceType = null;
          _draftSpaceId = null;
        });
        return;
      }
      prev = 0; // Spaces → Details
    } else if (_step == 5 && setup.isRentalHouse) {
      prev = 7; // Review → Spaces
    } else if (setup.isApartment) {
      if (_step == 2) {
        prev = 0;
      } else if (_step == 3) {
        prev = 2;
      } else if (_step == 5) {
        prev = 3;
      }
    } else {
      if (_step == 3 &&
          (setup.structurePreset == OrgStructurePreset.roomsAndBeds ||
              setup.structurePreset == OrgStructurePreset.singleBuilding)) {
        prev = 1;
      } else if (_step == 5 && setup.addBedsNow == false) {
        prev = 4;
      }
    }

    setState(() {
      _error = null;
      _step = prev;
    });
  }

  void _goToCreatedDashboard() {
    final property = _createdRentalProperty;
    if (property == null) {
      context.pop();
      return;
    }
    final id = property['id']?.toString();
    if (id == null || id.isEmpty) {
      context.pop();
      return;
    }
    context.go(
      '/dashboard/$id',
      extra: {'propertyName': property['name']},
    );
  }

  void _continueFromStructure() {
    final setup = ref.read(propertySetupProvider);
    final preset = setup.structurePreset;
    if (preset == null) {
      setState(() => _error = 'Choose how your property is organized.');
      return;
    }

    if (preset == OrgStructurePreset.singleBuilding ||
        preset == OrgStructurePreset.roomsAndBeds) {
      ref.read(propertySetupProvider.notifier).setStructurePreset(preset);
    }

    setState(() {
      _error = null;
      _step = preset == OrgStructurePreset.multipleBuildings ? 2 : 3;
    });
  }

  void _continueFromBuildings() {
    final setup = ref.read(propertySetupProvider);
    if (setup.buildings.isEmpty) {
      setState(() => _error = setup.isApartment
          ? 'Add at least one tower to continue.'
          : 'Add at least one building to continue.');
      return;
    }
    for (final b in setup.buildings) {
      if (b.name.trim().isEmpty || b.floorCount < 1) {
        setState(() => _error = setup.isApartment
            ? 'Each tower needs a name and at least 1 floor.'
            : 'Each building needs a name and at least 1 floor.');
        return;
      }
    }
    setState(() {
      _error = null;
      _step = 3;
    });
  }

  void _continueFromRooms() {
    final setup = ref.read(propertySetupProvider);
    if (setup.totalRooms < 1) {
      setState(() => _error = setup.isApartment
          ? 'Add at least one flat to continue.'
          : 'Add at least one room to continue.');
      return;
    }

    // Apartment never configures beds — go straight to review.
    if (setup.isApartment) {
      ref.read(propertySetupProvider.notifier).setAddBedsNow(false);
      setState(() {
        _error = null;
        _step = 5;
      });
      return;
    }

    setState(() {
      _error = null;
      _step = 4;
    });
  }

  void _continueFromBeds() {
    final setup = ref.read(propertySetupProvider);
    if (setup.addBedsNow == null) {
      setState(() => _error = 'Choose whether to add beds now or later.');
      return;
    }
    setState(() {
      _error = null;
      _step = 5;
    });
  }

  HierarchyLevel? _firstLevelOf(
    List<HierarchyLevel> levels,
    List<String> keys,
  ) {
    for (final k in keys) {
      for (final l in levels) {
        if (l.isEnabled && l.internalKey == k) return l;
      }
    }
    return null;
  }

  Future<void> _seedHierarchyNodes({
    required String propertyId,
    required PropertySetupState setup,
  }) async {
    final repo = ref.read(structureRepositoryProvider);
    final levels = await repo.listLevels(propertyId);
    final enabled = levels.where((l) => l.isEnabled).toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

    if (setup.isRentalHouse) {
      // Tenant-first: hierarchy nodes are created when adding tenants.
      return;
    }

    final buildingLevel =
        _firstLevelOf(enabled, const ['building', 'tower', 'property']);
    final floorLevel = _firstLevelOf(enabled, const ['floor']);
    final roomLevel =
        _firstLevelOf(enabled, const ['room', 'flat', 'unit']);
    final bedLevel = _firstLevelOf(enabled, const ['bed']);

    if (roomLevel == null) return;

    final preset = setup.structurePreset ?? OrgStructurePreset.multipleBuildings;

    Future<void> seedRoomsUnder({
      required String? parentNodeId,
      required SetupFloorPlan plan,
    }) async {
      for (var r = 0; r < plan.roomCount; r++) {
        final roomName = plan.roomNameAt(r, setup.roomNaming);
        final roomNode = await repo.createNode(
          propertyId,
          levelId: roomLevel.id,
          parentNodeId: parentNodeId,
          name: roomName,
        );
        final roomId = roomNode['id']?.toString();
        if (setup.addBedsNow == true && bedLevel != null && roomId != null) {
          final beds = plan.bedsAt(
            r,
            addBedsNow: true,
            defaultBeds: setup.defaultBedsPerRoom,
          );
          for (var b = 1; b <= beds; b++) {
            await repo.createNode(
              propertyId,
              levelId: bedLevel.id,
              parentNodeId: roomId,
              name: 'Bed $b',
            );
          }
        }
      }
    }

    if (preset == OrgStructurePreset.roomsAndBeds) {
      for (final b in setup.buildings) {
        for (var f = 0; f < b.floorCount; f++) {
          final plan = setup.floorPlans['${b.id}:$f'];
          if (plan == null || plan.roomCount < 1) continue;
          await seedRoomsUnder(parentNodeId: null, plan: plan);
        }
      }
      return;
    }

    for (final building in setup.buildings) {
      String? floorParentId;

      if (preset == OrgStructurePreset.multipleBuildings &&
          buildingLevel != null) {
        final node = await repo.createNode(
          propertyId,
          levelId: buildingLevel.id,
          parentNodeId: null,
          name: building.name,
        );
        floorParentId = node['id']?.toString();
      }

      for (var f = 0; f < building.floorCount; f++) {
        final plan = setup.floorPlans['${building.id}:$f'] ??
            SetupFloorPlan(
              buildingId: building.id,
              floorIndex: f,
              roomCount: 0,
            );
        if (plan.roomCount < 1) continue;

        String? roomParentId = floorParentId;

        if (floorLevel != null) {
          final floorNode = await repo.createNode(
            propertyId,
            levelId: floorLevel.id,
            parentNodeId: floorParentId,
            name: building.floorLabel(f),
          );
          roomParentId = floorNode['id']?.toString();
        }

        await seedRoomsUnder(parentNodeId: roomParentId, plan: plan);
      }
    }
  }

  Future<void> _createProperty() async {
    final setup = ref.read(propertySetupProvider);
    final typeKey = setup.propertyTypeKey ?? _selectedTypeKey;
    if (typeKey == null || setup.propertyName.trim().isEmpty) {
      setState(() => _error = 'Missing property details. Go back to Details.');
      return;
    }
    if (setup.isRentalHouse) {
      await _createRentalPropertyAndShowSuccess();
      return;
    } else if (setup.buildings.isEmpty || setup.totalRooms < 1) {
      setState(() => _error = 'Add buildings and rooms before creating.');
      return;
    }

    if (await _shouldOpenPaywallForType(typeKey)) {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PaywallScreen()),
      );
      return;
    }

    setState(() {
      _creating = true;
      _error = null;
    });

    try {
      final authRepo = ref.read(authRepositoryProvider);
      final ctx = await authRepo.ensureOwnerWorkspace();
      final orgId = ctx['id']?.toString() ?? await authRepo.getOrganizationId();
      if (orgId == null || orgId.isEmpty) {
        throw Exception('Could not establish a workspace. Please sign in again.');
      }

      final property = await ref.read(propertiesRepositoryProvider).create({
        'organizationId': orgId,
        'name': setup.propertyName.trim(),
        'propertyTypeKey': typeKey,
        'city': setup.city.trim(),
        'timezone': 'Asia/Kolkata',
        'currency': 'INR',
        'language': 'en',
        'levelOverrides': setup.levelOverridesForApi(),
      });

      final propertyId = property['id']?.toString();
      if (propertyId == null || propertyId.isEmpty) {
        throw Exception('Property created but no id returned.');
      }

      await _seedHierarchyNodes(propertyId: propertyId, setup: setup);

      ref.read(propertySetupProvider.notifier).reset();

      if (!mounted) return;
      context.go(
        '/dashboard/$propertyId',
        extra: {'propertyName': property['name'] ?? setup.propertyName},
      );
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
        setState(
          () => _error =
              'Could not create property: ${data is Map ? data['error'] : e}',
        );
      }
    } catch (e) {
      setState(() => _error = 'Could not create property: $e');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFFEDEBFB),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: Text(
          _appBarTitle,
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _creating ? null : _goBack,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: StepIndicator(
              currentStep: _indicatorStep,
              labels: const ['Details', 'Setup', 'Review'],
            ),
          ),
        ),
      ),
      body: switch (_step) {
        0 => _buildDetailsStep(),
        1 => _buildStructureStep(),
        2 => _buildBuildingsStep(),
        3 => _buildRoomsStep(),
        4 => _buildBedsStep(),
        6 => _buildRentalSuccessStep(),
        7 => _buildRentalSpacesStep(),
        _ => _buildReviewStep(),
      },
    );
  }

  // ─── Step 0: Details ───────────────────────────────────────────────────────

  Widget _buildDetailsStep() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Property Name *', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: _nameController,
          decoration: InputDecoration(
            hintText: 'Your Property name',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
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
        const Text('Property Type *',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          'Choose one of three property models. Rental House stays free forever.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 8),
        _loadingTypes
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: const [
                  PropertyArchetype.individualLease,
                  PropertyArchetype.sharedLiving,
                  PropertyArchetype.gatedCommunity,
                ].map((archetype) {
                  final key = archetype.catalogKey;
                  final selected = _selectedTypeKey == key;
                  final freeForever =
                      PropertyMonetization.isFreeResidential(key);
                  final badge = PropertyMonetization.badgeFor(key);
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
                            color: selected
                                ? AppColors.blueprint
                                : Colors.grey.shade300,
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
                              color: selected
                                  ? AppColors.blueprint
                                  : Colors.grey,
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Icon(
                              archetype == PropertyArchetype.sharedLiving
                                  ? Icons.bed_outlined
                                  : archetype ==
                                          PropertyArchetype.gatedCommunity
                                      ? Icons.apartment_outlined
                                      : Icons.home_outlined,
                              color: selected
                                  ? AppColors.blueprint
                                  : Colors.grey.shade700,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    archetype.label,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                  Text(
                                    archetype.subtitle,
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
        _primaryButton(
          label: 'Continue',
          onPressed: _creating ? null : _goFromDetails,
          loading: _creating,
        ),
      ],
    );
  }

  // ─── Rental success (tenant-first) ─────────────────────────────────────────

  Widget _buildRentalSuccessStep() {
    final name = _createdRentalProperty?['name']?.toString() ?? 'Your property';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            const Spacer(),
            Container(
              width: 90,
              height: 90,
              decoration: const BoxDecoration(
                color: Color(0xFFE6F7ED),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, color: Color(0xFF2ECC71), size: 48),
            ),
            const SizedBox(height: 20),
            const Text(
              'You\'re all set! 🎉',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              '$name is ready. You can add tenants to your spaces whenever you\'re ready.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                height: 1.4,
                color: Colors.grey.shade600,
              ),
            ),
            const Spacer(),
            _primaryButton(
              label: 'Go to Dashboard',
              onPressed: _goToCreatedDashboard,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Rental spaces setup (all details stay inside Step 2) ─────────────────

  RentalSpaceType _typeForMode(RentalDivisionMode mode) {
    switch (mode) {
      case RentalDivisionMode.entireProperty:
        return RentalSpaceType.entireProperty;
      case RentalDivisionMode.floorPortion:
        return RentalSpaceType.portion;
      case RentalDivisionMode.room:
        return RentalSpaceType.room;
      case RentalDivisionMode.commercial:
        return RentalSpaceType.shop;
    }
  }

  String _emojiForType(RentalSpaceType type) {
    switch (type) {
      case RentalSpaceType.entireProperty:
        return '🏠';
      case RentalSpaceType.floor:
      case RentalSpaceType.portion:
        return '🏢';
      case RentalSpaceType.room:
        return '🚪';
      case RentalSpaceType.shop:
        return '🏪';
    }
  }

  String _nameHintForType(RentalSpaceType type) {
    switch (type) {
      case RentalSpaceType.entireProperty:
        return 'e.g., Entire House';
      case RentalSpaceType.floor:
      case RentalSpaceType.portion:
        return 'e.g., Ground Floor Portion';
      case RentalSpaceType.room:
        return 'e.g., Room 1, Back Room';
      case RentalSpaceType.shop:
        return 'e.g., Front Shop';
    }
  }

  bool _typeNeedsFloor(RentalSpaceType type) =>
      type != RentalSpaceType.entireProperty;

  void _openSpaceEditor({
    required RentalSpaceType type,
    SetupRentalSpace? existing,
  }) {
    // Collect floors already used in this wizard session.
    final setup = ref.read(propertySetupProvider);
    final known = <String>{
      ..._draftFloors,
      for (final s in setup.rentalSpaces)
        if (s.floorLabel != null && s.floorLabel!.trim().isNotEmpty)
          s.floorLabel!.trim(),
    };
    _draftFloors
      ..clear()
      ..addAll(known);
    _draftFloors.sort();

    _draftNameCtrl.text = existing?.name ??
        (type == RentalSpaceType.entireProperty ? 'Entire House' : '');
    _draftRentCtrl.text = existing?.monthlyRent != null
        ? existing!.monthlyRent!.toStringAsFixed(0)
        : '';
    _draftDepositCtrl.text = existing?.securityDeposit != null
        ? existing!.securityDeposit!.toStringAsFixed(0)
        : '';
    _draftFloorLabel = existing?.floorLabel;
    setState(() {
      _error = null;
      _draftSpaceType = type;
      _draftSpaceId = existing?.id;
    });
  }

  void _closeSpaceEditor() {
    setState(() {
      _error = null;
      _draftSpaceType = null;
      _draftSpaceId = null;
    });
  }

  void _saveDraftSpace() {
    final type = _draftSpaceType;
    if (type == null) return;
    final name = _draftNameCtrl.text.trim();
    final rent = double.tryParse(_draftRentCtrl.text.trim());
    final deposit = double.tryParse(_draftDepositCtrl.text.trim());

    if (name.isEmpty) {
      setState(() => _error = 'Enter a space name.');
      return;
    }
    if (_typeNeedsFloor(type) &&
        (_draftFloorLabel == null || _draftFloorLabel!.trim().isEmpty)) {
      setState(() => _error = 'Select a floor location.');
      return;
    }
    if (rent == null || rent <= 0) {
      setState(() => _error = 'Enter a valid monthly rent.');
      return;
    }

    ref.read(propertySetupProvider.notifier).upsertRentalSpace(
          id: _draftSpaceId,
          name: name,
          type: type,
          floorLabel: _typeNeedsFloor(type) ? _draftFloorLabel!.trim() : null,
          monthlyRent: rent,
          securityDeposit: deposit,
        );
    _closeSpaceEditor();
  }

  Future<void> _promptAddWizardFloor() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add floor'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Floor name',
            hintText: 'e.g., Basement, Mezzanine',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final v = controller.text.trim();
              if (v.isNotEmpty) Navigator.pop(ctx, v);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    setState(() {
      if (!_draftFloors.any((f) => f.toLowerCase() == name.toLowerCase())) {
        _draftFloors.add(name);
        _draftFloors.sort();
      }
      _draftFloorLabel = name;
    });
  }

  Widget _buildRentalSpacesStep() {
    final setup = ref.watch(propertySetupProvider);
    final draftType = _draftSpaceType;

    // Editing a space — stay inside Step 2 (do NOT open CreateSpaceScreen).
    if (draftType != null) {
      return _buildWizardSpaceDetailsEditor(draftType);
    }

    const options = <(RentalDivisionMode, String, String, String)>[
      (
        RentalDivisionMode.entireProperty,
        '🏠',
        'Entire Property',
        'Rent the whole house',
      ),
      (
        RentalDivisionMode.floorPortion,
        '🏢',
        'Floor / Portion',
        'Rent a separate part of the house',
      ),
      (
        RentalDivisionMode.room,
        '🚪',
        'Room',
        'Rent an individual room',
      ),
      (
        RentalDivisionMode.commercial,
        '🏪',
        'Commercial Space',
        'Shop, office, etc.',
      ),
    ];

    final spaces = setup.assignableRentalSpaces;
    final currency = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            children: [
              const Text(
                'Set up your spaces',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'What will you rent out? You can add more spaces later.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 16),
              ...options.map((opt) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _openSpaceEditor(
                        type: _typeForMode(opt.$1),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          children: [
                            Text(opt.$2, style: const TextStyle(fontSize: 28)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    opt.$3,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    opt.$4,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right,
                              color: Colors.grey.shade500,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
              if (spaces.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                const Text(
                  'Your spaces',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 10),
                ...spaces.map((s) {
                  final rent = s.monthlyRent;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          Text(
                            _emojiForType(s.type),
                            style: const TextStyle(fontSize: 20),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '✓ ${s.name}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  [
                                    s.typeLabel,
                                    if (rent != null)
                                      '${currency.format(rent)}/month',
                                  ].join(' · '),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () => _openSpaceEditor(
                              type: s.type,
                              existing: s,
                            ),
                            child: const Text('Edit'),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: () => ref
                                .read(propertySetupProvider.notifier)
                                .removeRentalSpace(s.id),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ] else
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Optional — tap a type to add a space, or skip and add later.',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _primaryButton(
                  label: 'Continue',
                  trailing: '→',
                  onPressed: _continueFromRentalSpaces,
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: _skipRentalSpaceSetup,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.slate,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text(
                    'Skip setup for now',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWizardSpaceDetailsEditor(RentalSpaceType type) {
    final needsFloor = _typeNeedsFloor(type);
    final canSave = _draftNameCtrl.text.trim().isNotEmpty &&
        (!needsFloor ||
            (_draftFloorLabel != null && _draftFloorLabel!.trim().isNotEmpty)) &&
        double.tryParse(_draftRentCtrl.text.trim()) != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            children: [
              const Text(
                'Space details',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.blueprint.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Text(
                      _emojiForType(type),
                      style: const TextStyle(fontSize: 22),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        SetupRentalSpace(
                          id: '',
                          name: '',
                          type: type,
                        ).typeLabel,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.blueprint,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _closeSpaceEditor,
                      child: const Text('Change'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text('Space Name',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _draftNameCtrl,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: _nameHintForType(type),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              if (needsFloor) ...[
                const SizedBox(height: 18),
                const Text('Floor Location',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _draftFloors.contains(_draftFloorLabel)
                      ? _draftFloorLabel
                      : null,
                  decoration: InputDecoration(
                    hintText: 'Select a floor',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: _draftFloors
                      .map(
                        (f) => DropdownMenuItem(value: f, child: Text(f)),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _draftFloorLabel = v),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _promptAddWizardFloor,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('+ Add Floor'),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              const Text('Monthly Rent',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _draftRentCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                ],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'e.g., 15000',
                  prefixText: '₹ ',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text('Security Deposit',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _draftDepositCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                ],
                decoration: InputDecoration(
                  hintText: 'Optional',
                  prefixText: '₹ ',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: SizedBox(
            height: 54,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    canSave ? AppColors.blueprint : Colors.grey.shade300,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: canSave ? _saveDraftSpace : null,
              child: const Text(
                'Save Space',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Step 1: Structure ─────────────────────────────────────────────────────

  Widget _buildStructureStep() {
    final setup = ref.watch(propertySetupProvider);
    final selected = setup.structurePreset;

    const options = <_StructureOption>[
      _StructureOption(
        preset: OrgStructurePreset.multipleBuildings,
        title: 'Multiple Buildings',
        hierarchy: 'Building → Floor → Room',
        footer: 'For properties with multiple buildings',
        icon: Icons.apartment_outlined,
      ),
      _StructureOption(
        preset: OrgStructurePreset.singleBuilding,
        title: 'Single Building',
        hierarchy: 'Floor → Room',
        footer: 'Best for apartments & PGs',
        icon: Icons.home_work_outlined,
      ),
      _StructureOption(
        preset: OrgStructurePreset.roomsAndBeds,
        title: 'Rooms & Beds',
        hierarchy: 'Room → Bed',
        footer: 'Simple property setup',
        icon: Icons.meeting_room_outlined,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            children: [
              const Text(
                'How is your property organized?',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose the setup that best matches your property.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 20),
              ...options.map((opt) {
                final isSelected = selected == opt.preset;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => ref
                          .read(propertySetupProvider.notifier)
                          .setStructurePreset(opt.preset),
                      child: Stack(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: double.infinity,
                            padding:
                                const EdgeInsets.fromLTRB(16, 16, 16, 14),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.blueprint
                                    : Colors.grey.shade300,
                                width: isSelected ? 2 : 1,
                              ),
                              color: isSelected
                                  ? AppColors.blueprint.withOpacity(0.03)
                                  : Colors.white,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      opt.icon,
                                      size: 28,
                                      color: isSelected
                                          ? AppColors.blueprint
                                          : Colors.grey.shade700,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            opt.title,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 16,
                                              color: AppColors.ink,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            opt.hierarchy,
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey.shade600,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Divider(
                                    height: 1, color: Colors.grey.shade200),
                                const SizedBox(height: 10),
                                Text(
                                  opt.footer,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: CustomPaint(
                                size: const Size(28, 28),
                                painter: _CornerCheckPainter(
                                  color: AppColors.blueprint,
                                ),
                                child: const SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: Align(
                                    alignment: Alignment(0.45, 0.45),
                                    child: Icon(
                                      Icons.check,
                                      size: 12,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: _primaryButton(
            label: 'Continue',
            trailing: '→',
            onPressed: _continueFromStructure,
          ),
        ),
      ],
    );
  }

  // ─── Step 2: Buildings / Towers ────────────────────────────────────────────

  Widget _buildBuildingsStep() {
    final setup = ref.watch(propertySetupProvider);
    final notifier = ref.read(propertySetupProvider.notifier);
    final isApt = setup.isApartment;
    final noun = isApt ? 'tower' : 'building';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            children: [
              Text(
                isApt ? 'Set up your towers' : 'Set up your buildings',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isApt
                    ? 'Add the towers or blocks that belong to this apartment.'
                    : 'Add the buildings or blocks that belong to this property.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 20),
              if (setup.buildings.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Column(
                    children: [
                      Icon(Icons.apartment_outlined,
                          size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text(
                        'No ${noun}s yet',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                )
              else
                ...setup.buildings.map((b) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          const Text('🏢', style: TextStyle(fontSize: 22)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  b.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                                Text(
                                  '${b.floorCount} floor${b.floorCount == 1 ? '' : 's'}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () => _showBuildingSheet(existing: b),
                            child: const Text('Edit'),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_outline,
                                color: Colors.grey.shade500),
                            onPressed: setup.buildings.length > 1 ||
                                    setup.structurePreset ==
                                        OrgStructurePreset.multipleBuildings
                                ? () => notifier.removeBuilding(b.id)
                                : null,
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _showBuildingSheet(),
                icon: const Icon(Icons.add),
                label: Text('+ Add another $noun'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.blueprint,
                  side: const BorderSide(color: AppColors.blueprint),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: _primaryButton(
            label: 'Continue',
            trailing: '→',
            onPressed: _continueFromBuildings,
          ),
        ),
      ],
    );
  }

  Future<void> _showBuildingSheet({SetupBuilding? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    var floors = existing?.floorCount ?? 1;
    final isApt = ref.read(propertySetupProvider).isApartment;
    final noun = isApt ? 'tower' : 'building';

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    existing == null ? 'Add $noun' : 'Edit $noun',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isApt ? 'Tower name' : 'Building name',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: isApt ? 'Tower A' : 'Main Building',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('How many floors?',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  _StepperRow(
                    value: floors,
                    min: 1,
                    max: 50,
                    onChanged: (v) => setModal(() => floors = v),
                  ),
                  const SizedBox(height: 20),
                  _primaryButton(
                    label: existing == null ? 'Add $noun' : 'Save',
                    onPressed: () {
                      if (nameCtrl.text.trim().isEmpty) return;
                      Navigator.of(ctx).pop(true);
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (saved == true && nameCtrl.text.trim().isNotEmpty) {
      ref.read(propertySetupProvider.notifier).upsertBuilding(
            id: existing?.id,
            name: nameCtrl.text.trim(),
            floors: floors,
          );
    }
    nameCtrl.dispose();
  }

  // ─── Step 3: Rooms ─────────────────────────────────────────────────────────

  Widget _buildRoomsStep() {
    final setup = ref.watch(propertySetupProvider);
    final notifier = ref.read(propertySetupProvider.notifier);
    final preset = setup.structurePreset;
    final roomsOnly = preset == OrgStructurePreset.roomsAndBeds && !setup.isApartment;
    final singleBuilding = preset == OrgStructurePreset.singleBuilding;
    final isApt = setup.isApartment;
    final roomNoun = isApt ? 'flat' : 'room';
    final roomNounCap = isApt ? 'Flat' : 'Room';

    final subtitle = roomsOnly
        ? 'How many rooms does this property have?'
        : isApt
            ? 'Set how many flats are on each floor.'
            : 'Set how many rooms are on each floor.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            children: [
              Text(
                roomsOnly
                    ? 'Add rooms'
                    : isApt
                        ? 'Set up your floors & flats'
                        : 'Set up your floors & rooms',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              if (singleBuilding && setup.buildings.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text(
                  'How many floors?',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const SizedBox(height: 8),
                _StepperRow(
                  value: setup.buildings.first.floorCount,
                  min: 1,
                  max: 50,
                  onChanged: notifier.setMainBuildingFloorCount,
                ),
              ],
              const SizedBox(height: 16),
              Text(
                '$roomNounCap naming',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              RadioListTile<RoomNamingPreference>(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(isApt
                    ? 'Automatic (101, 102…)'
                    : 'Automatic (101, 102…)'),
                value: RoomNamingPreference.automatic,
                groupValue: setup.roomNaming,
                activeColor: AppColors.blueprint,
                onChanged: (v) {
                  if (v != null) notifier.setRoomNaming(v);
                },
              ),
              RadioListTile<RoomNamingPreference>(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Custom'),
                value: RoomNamingPreference.custom,
                groupValue: setup.roomNaming,
                activeColor: AppColors.blueprint,
                onChanged: (v) {
                  if (v != null) notifier.setRoomNaming(v);
                },
              ),
              const SizedBox(height: 8),
              if (roomsOnly)
                ..._roomsOnlyRoomEditor(setup, notifier)
              else
                ...setup.buildings.expand((building) {
                  final widgets = <Widget>[];
                  if (!singleBuilding) {
                    widgets.add(
                      Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 8),
                        child: Text(
                          building.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                    );
                  }
                  for (var f = 0; f < building.floorCount; f++) {
                    widgets.add(
                      _floorRoomCard(
                        setup: setup,
                        notifier: notifier,
                        building: building,
                        floorIndex: f,
                        roomNoun: roomNoun,
                        roomNounCap: roomNounCap,
                      ),
                    );
                  }
                  return widgets;
                }),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: _primaryButton(
            label: 'Continue',
            trailing: '→',
            onPressed: _continueFromRooms,
          ),
        ),
      ],
    );
  }

  List<Widget> _roomsOnlyRoomEditor(
    PropertySetupState setup,
    PropertySetupNotifier notifier,
  ) {
    if (setup.buildings.isEmpty) return const [];
    final building = setup.buildings.first;
    final plan = setup.floorPlans['${building.id}:0'];
    final count = plan?.roomCount ?? 0;

    return [
      Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade300),
          color: const Color(0xFFF7F8FC),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Rooms',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const SizedBox(height: 10),
            Text(
              'How many rooms?',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            _StepperRow(
              value: count,
              min: 0,
              max: 100,
              onChanged: (v) => notifier.setRoomCount(
                buildingId: building.id,
                floorIndex: 0,
                roomCount: v,
              ),
            ),
            if (setup.roomNaming == RoomNamingPreference.custom &&
                count > 0) ...[
              const SizedBox(height: 12),
              ...List.generate(count, (r) {
                final name = plan != null &&
                        r < plan.customRoomNames.length
                    ? plan.customRoomNames[r]
                    : '';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextFormField(
                    initialValue: name,
                    decoration: InputDecoration(
                      labelText: 'Room ${r + 1}',
                      hintText: plan?.roomNameAt(
                            r,
                            RoomNamingPreference.automatic,
                          ) ??
                          '',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      isDense: true,
                    ),
                    onChanged: (v) => notifier.setCustomRoomName(
                      buildingId: building.id,
                      floorIndex: 0,
                      roomIndex: r,
                      name: v,
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    ];
  }

  Widget _floorRoomCard({
    required PropertySetupState setup,
    required PropertySetupNotifier notifier,
    required SetupBuilding building,
    required int floorIndex,
    String roomNoun = 'room',
    String roomNounCap = 'Room',
  }) {
    final plan = setup.floorPlans['${building.id}:$floorIndex'];
    final count = plan?.roomCount ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
        color: const Color(0xFFF7F8FC),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            building.floorLabel(floorIndex),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 10),
          Text(
            'How many ${roomNoun}s are on this floor?',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          _StepperRow(
            value: count,
            min: 0,
            max: 100,
            onChanged: (v) => notifier.setRoomCount(
              buildingId: building.id,
              floorIndex: floorIndex,
              roomCount: v,
            ),
          ),
          if (setup.roomNaming == RoomNamingPreference.custom && count > 0) ...[
            const SizedBox(height: 12),
            ...List.generate(count, (r) {
              final name = plan != null && r < plan.customRoomNames.length
                  ? plan.customRoomNames[r]
                  : '';
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextFormField(
                  initialValue: name,
                  decoration: InputDecoration(
                    labelText: '$roomNounCap ${r + 1}',
                    hintText: plan?.roomNameAt(
                          r,
                          RoomNamingPreference.automatic,
                        ) ??
                        '',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    isDense: true,
                  ),
                  onChanged: (v) => notifier.setCustomRoomName(
                    buildingId: building.id,
                    floorIndex: floorIndex,
                    roomIndex: r,
                    name: v,
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  // ─── Step 4: Beds (optional) ───────────────────────────────────────────────

  Widget _buildBedsStep() {
    final setup = ref.watch(propertySetupProvider);
    final notifier = ref.read(propertySetupProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            children: [
              const Text(
                'Your rooms are ready 🎉',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                setup.summaryLine,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 24),
              _ChoiceCard(
                selected: setup.addBedsNow == true,
                emoji: '🛏️',
                title: 'Add beds now',
                subtitle: 'Set the number of beds for each room.',
                onTap: () => notifier.setAddBedsNow(true),
              ),
              const SizedBox(height: 12),
              _ChoiceCard(
                selected: setup.addBedsNow == false,
                emoji: '⏭️',
                title: 'Add beds later',
                subtitle: 'You can configure beds anytime from Rooms.',
                onTap: () => notifier.setAddBedsNow(false),
              ),
              if (setup.addBedsNow == true) ...[
                const SizedBox(height: 20),
                const Text(
                  'Beds per room',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                _StepperRow(
                  value: setup.defaultBedsPerRoom,
                  min: 1,
                  max: 12,
                  onChanged: notifier.setDefaultBedsPerRoom,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: _primaryButton(
            label: 'Continue',
            trailing: '→',
            onPressed: _continueFromBeds,
          ),
        ),
      ],
    );
  }

  // ─── Step 5: Review ────────────────────────────────────────────────────────

  Widget _buildReviewStep() {
    final setup = ref.watch(propertySetupProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            children: [
              const Text(
                'Review your property',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: AppColors.blueprint.withOpacity(0.06),
                  border: Border.all(
                    color: AppColors.blueprint.withOpacity(0.25),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      setup.propertyName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                    if (setup.city.isNotEmpty)
                      Text(
                        setup.city,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        if (setup.isRentalHouse)
                          _StatChip(
                            label: 'Spaces',
                            value: '${setup.assignableRentalSpaces.length}',
                          )
                        else ...[
                          _StatChip(
                            label: setup.isApartment ? 'Towers' : 'Buildings',
                            value: '${setup.buildings.length}',
                          ),
                          _StatChip(
                            label: 'Floors',
                            value: '${setup.totalFloors}',
                          ),
                          _StatChip(
                            label: setup.isApartment ? 'Flats' : 'Rooms',
                            value: '${setup.totalRooms}',
                          ),
                          if (setup.addBedsNow == true)
                            _StatChip(
                              label: 'Beds',
                              value: '${setup.totalBeds}',
                            ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (setup.isRentalHouse) ...[
                const Text(
                  'Property Information',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                const SizedBox(height: 8),
                Text(
                  'Type · Rental House',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade800,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Spaces',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                const SizedBox(height: 10),
                ...setup.assignableRentalSpaces.map((s) {
                  final rent = s.monthlyRent;
                  final rentLabel = rent == null
                      ? null
                      : NumberFormat.currency(
                          locale: 'en_IN',
                          symbol: '₹',
                          decimalDigits: 0,
                        ).format(rent);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      [
                        s.name,
                        s.typeLabel,
                        if (rentLabel != null) '$rentLabel/month',
                      ].join('\n'),
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade800,
                        height: 1.4,
                      ),
                    ),
                  );
                }),
                if (setup.assignableRentalSpaces.isEmpty)
                  Text(
                    'No spaces yet — you can add them after creating from Dashboard → Spaces.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                      height: 1.4,
                    ),
                  ),
              ] else ...[
                const Text(
                  'Breakdown',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                const SizedBox(height: 10),
                ...setup.buildings.expand((building) {
                  final roomLabel = setup.isApartment ? 'Flat' : 'Room';
                  final rows = <Widget>[];
                  for (var f = 0; f < building.floorCount; f++) {
                    final plan = setup.floorPlans['${building.id}:$f'];
                    final rooms = plan?.roomCount ?? 0;
                    if (rooms < 1) continue;
                    final beds = setup.addBedsNow == true && plan != null
                        ? List.generate(
                            plan.roomCount,
                            (i) => plan.bedsAt(
                              i,
                              addBedsNow: true,
                              defaultBeds: setup.defaultBedsPerRoom,
                            ),
                          ).fold(0, (a, b) => a + b)
                        : 0;
                    rows.add(
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '${building.name} → ${building.floorLabel(f)} → '
                          '$rooms $roomLabel${rooms == 1 ? '' : 's'}'
                          '${beds > 0 ? ' · $beds Bed${beds == 1 ? '' : 's'}' : ''}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade800,
                            height: 1.35,
                          ),
                        ),
                      ),
                    );
                  }
                  return rows;
                }),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: _primaryButton(
            label: _creating
                ? 'Creating…'
                : (setup.isRentalHouse ? 'Create Property' : '✓ Looks good'),
            onPressed: _creating ? null : _createProperty,
            loading: _creating,
          ),
        ),
      ],
    );
  }

  Widget _primaryButton({
    required String label,
    String? trailing,
    VoidCallback? onPressed,
    bool loading = false,
  }) {
    return SizedBox(
      height: 54,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.blueprint,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: onPressed,
        child: loading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      trailing,
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _StructureOption {
  final OrgStructurePreset preset;
  final String title;
  final String hierarchy;
  final String footer;
  final IconData icon;

  const _StructureOption({
    required this.preset,
    required this.title,
    required this.hierarchy,
    required this.footer,
    required this.icon,
  });
}

class _ChoiceCard extends StatelessWidget {
  final bool selected;
  final String emoji;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ChoiceCard({
    required this.selected,
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
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
              Text(emoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: selected ? AppColors.blueprint : Colors.grey,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;

  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: AppColors.blueprint,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class _StepperRow extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _StepperRow({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _RoundIconButton(
          icon: Icons.remove,
          onPressed: value > min ? () => onChanged(value - 1) : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '$value',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        _RoundIconButton(
          icon: Icons.add,
          onPressed: value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;

  const _RoundIconButton({required this.icon, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: onPressed == null
          ? Colors.grey.shade100
          : AppColors.blueprint.withOpacity(0.1),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            icon,
            size: 20,
            color: onPressed == null
                ? Colors.grey.shade400
                : AppColors.blueprint,
          ),
        ),
      ),
    );
  }
}

class _CornerCheckPainter extends CustomPainter {
  final Color color;

  _CornerCheckPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _CornerCheckPainter oldDelegate) =>
      oldDelegate.color != color;
}
