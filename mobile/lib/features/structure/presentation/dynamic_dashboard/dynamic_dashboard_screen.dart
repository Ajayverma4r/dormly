// features/structure/presentation/dynamic_dashboard/dynamic_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../domain/hierarchy_level.dart';
import '../../data/structure_repository.dart';
import '../../../../core/widgets/dormly_empty_state.dart';
import '../../../../core/widgets/dynamic_icon.dart';
import '../../../../core/theme/app_theme.dart';
import '../node_list/node_list_screen.dart';
import '../../../billing/presentation/invoices_list_screen.dart';
import '../../../analytics/presentation/analytics_dashboard_screen.dart';
import '../../../analytics/data/analytics_repository.dart';
import '../../../complaints/presentation/complaints_list_screen.dart';
import '../../../staff/presentation/staff_list_screen.dart';
import '../../../auth/data/auth_repository.dart';

final hierarchyLevelsProvider =
    FutureProvider.family<List<HierarchyLevel>, String>((ref, propertyId) async {
  final repo = ref.watch(structureRepositoryProvider);
  final levels = await repo.listLevels(propertyId);
  return levels.where((l) => l.isEnabled).toList()
    ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
});

final nodeCountProvider =
    FutureProvider.family<int, (String propertyId, String levelId)>((ref, args) async {
  final repo = ref.watch(structureRepositoryProvider);
  return repo.countNodes(args.$1, args.$2);
});

final activityProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, propertyId) => ref.watch(analyticsRepositoryProvider).getActivity(propertyId),
);

final contextRoleProvider = FutureProvider.autoDispose<String?>(
  (ref) => ref.watch(authRepositoryProvider).getContextRole(),
);

class DynamicDashboardScreen extends ConsumerWidget {
  final String propertyId;
  final String propertyName;

  const DynamicDashboardScreen({
    super.key,
    required this.propertyId,
    required this.propertyName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roleAsync = ref.watch(contextRoleProvider);

    return roleAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (err, _) => Scaffold(body: Center(child: Text('Something went wrong: $err'))),
      data: (role) {
        // Staff's entire job is complaints — no rooms, billing, or analytics
        // access at all. They land directly on the Complaints screen with
        // nothing else visible.
        if (role == 'staff') {
          return ComplaintsListScreen(propertyId: propertyId, isRoot: true);
        }
        return _OwnerManagerDashboard(propertyId: propertyId, propertyName: propertyName, role: role);
      },
    );
  }
}

class _OwnerManagerDashboard extends ConsumerWidget {
  final String propertyId;
  final String propertyName;
  final String? role;

  const _OwnerManagerDashboard({required this.propertyId, required this.propertyName, required this.role});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final levelsAsync = ref.watch(hierarchyLevelsProvider(propertyId));
    final analyticsAsync = ref.watch(analyticsProvider(propertyId));
    final activityAsync = ref.watch(activityProvider(propertyId));
    final theme = Theme.of(context);

    final isOwnerOrAdmin = role == 'owner' || role == 'admin';
    final canManage = isOwnerOrAdmin || role == 'manager';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Navigator.of(context).canPop() ? Icons.arrow_back : Icons.apps),
          tooltip: 'Back',
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/properties'); // only reached when this IS the root (e.g. Manager's direct post-login landing)
            }
          },
        ),
        title: Text(propertyName),
        actions: [
          if (canManage)
            IconButton(
              icon: const Icon(Icons.tune, size: 20),
              tooltip: 'Structure settings',
              onPressed: () => context.push('/dashboard/$propertyId/structure'),
            ),
        ],
      ),
      body: levelsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Something went wrong: $err')),
        data: (levels) {
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('Overview', style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              analyticsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Text('Could not load overview: $err'),
                data: (a) {
                  final revenue = double.tryParse(a['totalRevenue'].toString()) ?? 0;
                  final pendingRent = double.tryParse(a['pendingRent'].toString()) ?? 0;
                  return GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.6,
                    children: [
                      _statCard('Occupancy', '${a['occupancyRate']}%', Icons.pie_chart_outline, AppColors.blueprint),
                      _statCard('Occupied Units', '${a['occupiedUnits']}', Icons.people_outline, const Color(0xFF7C3AED)),
                      _statCard('Pending Rent', '₹${pendingRent.toStringAsFixed(0)}', Icons.hourglass_bottom, AppColors.caution),
                      _statCard('Revenue', '₹${revenue.toStringAsFixed(0)}', Icons.trending_up, AppColors.positive),
                    ],
                  );
                },
              ),
              const SizedBox(height: 28),

              Text('Quick Actions', style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.4,
                children: [
                  _quickAction(context, 'Add Room', Icons.meeting_room_outlined, const Color(0xFF2451B4), () {
                    if (levels.isNotEmpty) {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (context) => NodeListScreen(propertyId: propertyId, level: levels.first, allLevels: levels),
                      ));
                    }
                  }),
                  _quickAction(context, 'Residents', Icons.people_alt_outlined, const Color(0xFF7C3AED), () {
                    final occupancyLevel = levels.where((l) => l.supportsOccupancy).isNotEmpty
                        ? levels.firstWhere((l) => l.supportsOccupancy)
                        : (levels.isNotEmpty ? levels.first : null);
                    if (occupancyLevel != null) {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (context) => NodeListScreen(propertyId: propertyId, level: occupancyLevel, allLevels: levels),
                      ));
                    }
                  }),
                  _quickAction(context, 'Rent & Billing', Icons.receipt_long_outlined, AppColors.caution, () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (context) => InvoicesListScreen(propertyId: propertyId),
                    ));
                  }),
                  _quickAction(context, 'Analytics', Icons.bar_chart_outlined, AppColors.positive, () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (context) => AnalyticsDashboardScreen(propertyId: propertyId),
                    ));
                  }),
                  _quickAction(context, 'Complaints', Icons.build_outlined, AppColors.danger, () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (context) => ComplaintsListScreen(propertyId: propertyId),
                    ));
                  }),
                  if (isOwnerOrAdmin)
                    _quickAction(context, 'Team', Icons.badge_outlined, const Color(0xFF7C3AED), () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (context) => StaffListScreen(propertyId: propertyId),
                      ));
                    }),
                ],
              ),
              const SizedBox(height: 28),

              Text('Recent Activity', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              activityAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Text('Could not load activity: $err'),
                data: (items) {
                  if (items.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
                      child: Text('No activity yet.', style: theme.textTheme.bodyMedium),
                    );
                  }
                  return Container(
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      children: items.map((item) {
                        final isPayment = item['type'] == 'payment';
                        return ListTile(
                          leading: Icon(
                            isPayment ? Icons.payments_outlined : Icons.person_add_alt_outlined,
                            color: isPayment ? AppColors.positive : AppColors.blueprint,
                          ),
                          title: Text(
                            isPayment ? 'Payment received: ${item['title']}' : 'New resident: ${item['title']}',
                            style: theme.textTheme.bodyLarge,
                          ),
                          subtitle: Text(
                            isPayment ? item['subtitle'].toString() : 'Moved into ${item['subtitle']}',
                            style: theme.textTheme.bodyMedium,
                          ),
                          trailing: Text(
                            item['ts'].toString().split('T').first,
                            style: theme.textTheme.labelSmall,
                          ),
                        );
                      }).toList(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 28),

              Text('Structure', style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              if (levels.isEmpty)
                DormlyEmptyState(
                  title: 'No structure configured yet',
                  subtitle: canManage
                      ? 'Tap the settings icon above to define levels for this property.'
                      : 'Ask the property owner to configure the structure.',
                  action: canManage
                      ? FilledButton(
                          onPressed: () => context.push('/dashboard/$propertyId/structure'),
                          child: const Text('Open Structure Settings'),
                        )
                      : null,
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 1.1,
                  ),
                  itemCount: levels.length,
                  itemBuilder: (context, index) {
                    final level = levels[index];
                    return _LevelCard(level: level, propertyId: propertyId, allLevels: levels);
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink)),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.slate)),
        ],
      ),
    );
  }

  Widget _quickAction(BuildContext context, String label, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 20),
            ),
            const Spacer(),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.ink)),
          ],
        ),
      ),
    );
  }
}

class _LevelCard extends ConsumerWidget {
  final HierarchyLevel level;
  final String propertyId;
  final List<HierarchyLevel> allLevels;

  const _LevelCard({required this.level, required this.propertyId, required this.allLevels});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countAsync = ref.watch(nodeCountProvider((propertyId, level.id)));
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => NodeListScreen(
                propertyId: propertyId,
                level: level,
                allLevels: allLevels,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DynamicIcon(name: level.icon, colorHex: level.color, size: 28),
              const Spacer(),
              Text(
                level.displayName,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              countAsync.when(
                data: (count) => Text('$count', style: theme.textTheme.headlineSmall),
                loading: () => const SizedBox(
                  height: 16, width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                error: (_, __) => const Text('—'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}