// features/structure/presentation/property_dashboard_tab_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../analytics/data/analytics_repository.dart';
import '../../analytics/presentation/analytics_dashboard_screen.dart' show analyticsProvider;
import 'dynamic_dashboard/dynamic_dashboard_screen.dart' show activityProvider;

class PropertyDashboardTabScreen extends ConsumerWidget {
  final String propertyId;
  final String propertyName;

  const PropertyDashboardTabScreen({super.key, required this.propertyId, required this.propertyName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsAsync = ref.watch(analyticsProvider(propertyId));
    final activityAsync = ref.watch(activityProvider(propertyId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Navigator.of(context).canPop() ? Icons.arrow_back : Icons.apps),
          tooltip: 'Back',
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/properties');
            }
          },
        ),
        title: Text(propertyName),
      ),
      body: ListView(
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
                      trailing: Text(item['ts'].toString().split('T').first, style: theme.textTheme.labelSmall),
                    );
                  }).toList(),
                ),
              );
            },
          ),
        ],
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
}