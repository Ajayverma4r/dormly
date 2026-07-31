// features/structure/presentation/property_shell_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../properties/data/properties_repository.dart';
import 'dynamic_dashboard/dynamic_dashboard_screen.dart' show contextRoleProvider;
import 'property_dashboard_tab_screen.dart';
import 'property_structure_tab_screen.dart';
import 'operations_tab_screen.dart';
import 'property_more_screen.dart';
import '../../tenancies/presentation/residents_list_screen.dart';

final propertyDetailProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, propertyId) => ref.watch(propertiesRepositoryProvider).getById(propertyId),
);

// "Dynamic label based on property configuration" — keyed off the property
// type chosen in the wizard, defaulting to the universal "Residents".
String _peopleLabelFor(String? propertyTypeKey) {
  switch (propertyTypeKey) {
    case 'apartment':
    case 'rental':
    case 'villa':
    case 'house':
      return 'Tenants';
    case 'office':
      return 'Employees';
    case 'hotel':
    case 'resort':
      return 'Guests';
    case 'hospital':
      return 'Patients';
    case 'school':
      return 'Students';
    default:
      return 'Residents';
  }
}

class PropertyShellScreen extends ConsumerStatefulWidget {
  final String propertyId;
  final String propertyName;

  const PropertyShellScreen({super.key, required this.propertyId, required this.propertyName});

  @override
  ConsumerState<PropertyShellScreen> createState() => _PropertyShellScreenState();
}

class _PropertyShellScreenState extends ConsumerState<PropertyShellScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final roleAsync = ref.watch(contextRoleProvider);
    final propertyAsync = ref.watch(propertyDetailProvider(widget.propertyId));

    return roleAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (err, _) => Scaffold(body: Center(child: Text('Something went wrong: $err'))),
      data: (role) {
        final isOwnerOrAdmin = role == 'owner' || role == 'admin';
        final canManage = isOwnerOrAdmin || role == 'manager';
        final peopleLabel = propertyAsync.maybeWhen(
          data: (p) => _peopleLabelFor(p['property_type_key']),
          orElse: () => 'Residents',
        );

        final tabs = [
          PropertyDashboardTabScreen(propertyId: widget.propertyId, propertyName: widget.propertyName),
          PropertyStructureTabScreen(propertyId: widget.propertyId, canManage: canManage),
          ResidentsListScreen(propertyId: widget.propertyId, label: peopleLabel),
          OperationsTabScreen(propertyId: widget.propertyId, canManage: canManage),
          PropertyMoreScreen(propertyId: widget.propertyId, propertyName: widget.propertyName, role: role),
        ];

        return Scaffold(
          body: IndexedStack(index: _index, children: tabs),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            backgroundColor: AppColors.surface,
            indicatorColor: AppColors.blueprint.withOpacity(0.12),
            destinations: [
              const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home, color: AppColors.blueprint), label: 'Dashboard'),
              const NavigationDestination(icon: Icon(Icons.apartment_outlined), selectedIcon: Icon(Icons.apartment, color: AppColors.blueprint), label: 'Structure'),
              NavigationDestination(icon: const Icon(Icons.people_outline), selectedIcon: const Icon(Icons.people, color: AppColors.blueprint), label: peopleLabel),
              const NavigationDestination(icon: Icon(Icons.build_outlined), selectedIcon: Icon(Icons.build, color: AppColors.blueprint), label: 'Operations'),
              const NavigationDestination(icon: Icon(Icons.more_horiz), selectedIcon: Icon(Icons.more_horiz, color: AppColors.blueprint), label: 'More'),
            ],
          ),
        );
      },
    );
  }
}