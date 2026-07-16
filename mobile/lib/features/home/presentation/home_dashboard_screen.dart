// features/home/presentation/home_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/data/auth_repository.dart';
import '../../analytics/data/analytics_repository.dart';
import '../../properties/data/properties_repository.dart';
import '../../../core/theme/app_theme.dart';

final orgIdProvider = FutureProvider.autoDispose<String?>(
  (ref) => ref.watch(authRepositoryProvider).getOrganizationId(),
);

final orgAnalyticsProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final orgId = await ref.watch(orgIdProvider.future);
  if (orgId == null) return null;
  return ref.watch(analyticsRepositoryProvider).getOrganizationAnalytics(orgId);
});

final homePropertiesProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  final authRepo = ref.watch(authRepositoryProvider);
  final orgId = await authRepo.getOrganizationId();
  if (orgId != null) {
    return ref.watch(propertiesRepositoryProvider).list(orgId);
  }
  final scopedPropertyId = await authRepo.getScopedPropertyId();
  if (scopedPropertyId != null) {
    final property = await ref.watch(propertiesRepositoryProvider).getById(scopedPropertyId);
    return [property];
  }
  return [];
});
class HomeDashboardScreen extends ConsumerWidget {
  const HomeDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsAsync = ref.watch(orgAnalyticsProvider);
    final propertiesAsync = ref.watch(homePropertiesProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Good morning 👋'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none),
            onPressed: () => context.push('/notifications'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(orgAnalyticsProvider);
          ref.invalidate(homePropertiesProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Overview', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            analyticsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Text('Could not load overview: $err'),
              data: (a) {
                if (a == null) return const SizedBox.shrink();
                final revenue = double.tryParse(a['totalRevenue'].toString()) ?? 0;
                return GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.5,
                  children: [
                    _statCard('Total Properties', '${a['totalProperties']}', Icons.apartment, AppColors.blueprint),
                    _statCard('Occupancy', '${a['occupancyRate']}%', Icons.pie_chart_outline, AppColors.positive),
                    _statCard('Residents', '${a['totalResidents']}', Icons.people_outline, const Color(0xFF7C3AED)),
                    _statCard('Revenue', '₹${_formatNumber(revenue)}', Icons.trending_up, AppColors.caution),
                  ],
                );
              },
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Your Properties', style: theme.textTheme.titleLarge),
                TextButton(onPressed: () => context.push('/properties'), child: const Text('View all')),
              ],
            ),
            const SizedBox(height: 8),
            propertiesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Text('Could not load properties: $err'),
              data: (properties) {
                if (properties.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      children: [
                        Text('No properties yet', style: theme.textTheme.bodyLarge),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: () => context.push('/onboarding/create-property'),
                          child: const Text('Create Property'),
                        ),
                      ],
                    ),
                  );
                }
                return Column(
                  children: properties.take(3).map((p) => Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppColors.canvas,
                            child: const Icon(Icons.apartment, color: AppColors.blueprint),
                          ),
                          title: Text(p['name'] ?? '', style: theme.textTheme.titleMedium),
                          subtitle: Text(p['city'] ?? '', style: theme.textTheme.bodyMedium),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push('/dashboard/${p['id']}', extra: {'propertyName': p['name']}),
                        ),
                      )).toList(),
                );
              },
            ),
          ],
        ),
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
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink)),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.slate)),
        ],
      ),
    );
  }

  String _formatNumber(double value) {
    final s = value.toStringAsFixed(0);
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write(',');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }
}