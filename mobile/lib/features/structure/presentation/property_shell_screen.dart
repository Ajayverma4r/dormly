// features/structure/presentation/property_shell_screen.dart
//
// Bottom nav (5 tabs):
//   0 Dashboard · 1 Tenants · 2 Payments · 3 Rooms · 4 Menu
// Property switcher = global app-bar dropdown (bottom sheet), not a full screen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../properties/data/properties_repository.dart';
import '../../properties/domain/property_monetization.dart';
import '../../subscription/presentation/paywall_screen.dart';
import '../../subscription/presentation/subscription_provider.dart';
import '../../billing/presentation/invoices_list_screen.dart';
import 'dynamic_dashboard/dynamic_dashboard_screen.dart' show contextRoleProvider;
import 'property_dashboard_tab_screen.dart';
import 'property_structure_tab_screen.dart';
import 'property_more_screen.dart';
import '../../tenancies/presentation/residents_list_screen.dart';

final propertyDetailProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, propertyId) =>
      ref.watch(propertiesRepositoryProvider).getById(propertyId),
);

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

  const PropertyShellScreen(
      {super.key, required this.propertyId, required this.propertyName});

  @override
  ConsumerState<PropertyShellScreen> createState() =>
      _PropertyShellScreenState();
}

class _PropertyShellScreenState extends ConsumerState<PropertyShellScreen> {
  int _index = 0;

  void _goToTab(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final roleAsync = ref.watch(contextRoleProvider);
    final propertyAsync = ref.watch(propertyDetailProvider(widget.propertyId));
    final sub = ref.watch(subscriptionProvider).valueOrNull;
    final isPaid = PropertyMonetization.isPaidPlan(
      sub?.subscription.planSlug,
      sub?.subscription.status,
    );

    return roleAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (err, _) =>
          Scaffold(body: Center(child: Text('Something went wrong: $err'))),
      data: (role) {
        return propertyAsync.when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (err, _) =>
              Scaffold(body: Center(child: Text('Something went wrong: $err'))),
          data: (property) {
            final locked = !isPaid &&
                (property['is_locked'] == true ||
                    property['manageable'] == false);

            if (locked) {
              return Scaffold(
                appBar: AppBar(
                  title: Text(widget.propertyName),
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go('/properties');
                      }
                    },
                  ),
                ),
                body: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.lock_outline,
                          size: 56, color: Color(0xFFB45309)),
                      const SizedBox(height: 16),
                      Text(
                        property['name']?.toString() ?? widget.propertyName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        PropertyMonetization.expiredLockMessage,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: AppColors.slate, height: 1.45, fontSize: 14),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const PaywallScreen(
                                  reason:
                                      PropertyMonetization.expiredLockMessage,
                                ),
                              ),
                            );
                          },
                          child: const Text('Upgrade to Unlock'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => context.go('/properties'),
                        child: const Text('Back to properties'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final isOwnerOrAdmin = role == 'owner' || role == 'admin';
            final canManage = isOwnerOrAdmin || role == 'manager';
            final peopleLabel =
                _peopleLabelFor(property['property_type_key'] as String?);

            final tabs = [
              // 0 — Dashboard
              PropertyDashboardTabScreen(
                propertyId: widget.propertyId,
                propertyName: widget.propertyName,
                canManage: canManage,
                onAddTenant: () => _goToTab(1),
                onCollectRent: () => _goToTab(2),
              ),
              // 1 — Tenants
              ResidentsListScreen(
                propertyId: widget.propertyId,
                label: peopleLabel,
              ),
              // 2 — Payments (Rent & Billing)
              InvoicesListScreen(
                propertyId: widget.propertyId,
                asTab: true,
              ),
              // 3 — Rooms / Units (structure of the active property)
              PropertyStructureTabScreen(
                propertyId: widget.propertyId,
                canManage: canManage,
              ),
              // 4 — Menu
              PropertyMoreScreen(
                propertyId: widget.propertyId,
                propertyName: widget.propertyName,
                role: role,
              ),
            ];

            return Scaffold(
              key: const ValueKey('property-bottom-nav-v2'),
              body: IndexedStack(index: _index, children: tabs),
              bottomNavigationBar: NavigationBar(
                key: const ValueKey('nav-bar-dashboard-tenants-payments-rooms-menu'),
                selectedIndex: _index,
                onDestinationSelected: _goToTab,
                backgroundColor: AppColors.surface,
                indicatorColor: AppColors.blueprint.withOpacity(0.12),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home, color: AppColors.blueprint),
                    label: 'Dashboard',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.people_outline),
                    selectedIcon: Icon(Icons.people, color: AppColors.blueprint),
                    label: 'Tenants',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.account_balance_wallet_outlined),
                    selectedIcon: Icon(Icons.account_balance_wallet,
                        color: AppColors.blueprint),
                    label: 'Payments',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.meeting_room_outlined),
                    selectedIcon:
                        Icon(Icons.meeting_room, color: AppColors.blueprint),
                    label: 'Rooms',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.menu),
                    selectedIcon: Icon(Icons.menu, color: AppColors.blueprint),
                    label: 'Menu',
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
