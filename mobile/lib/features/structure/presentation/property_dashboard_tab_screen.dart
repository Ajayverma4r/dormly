// features/structure/presentation/property_dashboard_tab_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../analytics/presentation/analytics_dashboard_screen.dart'
    show analyticsProvider;
import '../../properties/presentation/property_switcher_sheet.dart';
import '../../subscription/presentation/widgets/ad_banner_gate.dart';
import '../../subscription/presentation/widgets/expiry_warning_banner.dart';
import 'dynamic_dashboard/dynamic_dashboard_screen.dart' show activityProvider;
import 'property_shell_screen.dart' show propertyDetailProvider;

class PropertyDashboardTabScreen extends ConsumerWidget {
  final String propertyId;
  final String propertyName;
  final bool canManage;
  final VoidCallback? onAddTenant;
  final VoidCallback? onCollectRent;

  const PropertyDashboardTabScreen({
    super.key,
    required this.propertyId,
    required this.propertyName,
    this.canManage = false,
    this.onAddTenant,
    this.onCollectRent,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsAsync = ref.watch(analyticsProvider(propertyId));
    final activityAsync = ref.watch(activityProvider(propertyId));
    final propertyAsync = ref.watch(propertyDetailProvider(propertyId));
    final theme = Theme.of(context);
    final propertyTypeKey =
        propertyAsync.valueOrNull?['property_type_key'] as String?;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => showPropertySwitcherSheet(
            context,
            ref,
            currentPropertyId: propertyId,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    propertyName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Colors.grey.shade700,
                ),
              ],
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const ExpiryWarningBanner(),
          Text('Overview', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          analyticsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Text('Could not load overview: $err'),
            data: (a) {
              final revenue =
                  double.tryParse(a['totalRevenue'].toString()) ?? 0;
              final pendingRent =
                  double.tryParse(a['pendingRent'].toString()) ?? 0;
              return GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.6,
                children: [
                  _statCard('Occupancy', '${a['occupancyRate']}%',
                      Icons.pie_chart_outline, AppColors.blueprint),
                  _statCard('Occupied Units', '${a['occupiedUnits']}',
                      Icons.people_outline, const Color(0xFF7C3AED)),
                  _statCard(
                      'Pending Rent',
                      '₹${pendingRent.toStringAsFixed(0)}',
                      Icons.hourglass_bottom,
                      AppColors.caution),
                  _statCard('Revenue', '₹${revenue.toStringAsFixed(0)}',
                      Icons.trending_up, AppColors.positive),
                ],
              );
            },
          ),
          if (canManage) ...[
            const SizedBox(height: 20),
            Text('Quick Actions', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _quickAction(
                    context,
                    icon: Icons.person_add_alt_1_outlined,
                    label: 'Add Tenant',
                    color: AppColors.blueprint,
                    onTap: onAddTenant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _quickAction(
                    context,
                    icon: Icons.payments_outlined,
                    label: 'Collect Rent',
                    color: AppColors.positive,
                    onTap: onCollectRent,
                  ),
                ),
              ],
            ),
          ],
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
                  decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16)),
                  child: Text('No activity yet.',
                      style: theme.textTheme.bodyMedium),
                );
              }
              return Container(
                decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: items.map((item) {
                    final isPayment = item['type'] == 'payment';
                    return ListTile(
                      leading: Icon(
                        isPayment
                            ? Icons.payments_outlined
                            : Icons.person_add_alt_outlined,
                        color: isPayment
                            ? AppColors.positive
                            : AppColors.blueprint,
                      ),
                      title: Text(
                        isPayment
                            ? 'Payment received: ${item['title']}'
                            : 'New resident: ${item['title']}',
                        style: theme.textTheme.bodyLarge,
                      ),
                      subtitle: Text(
                        isPayment
                            ? item['subtitle'].toString()
                            : 'Moved into ${item['subtitle']}',
                        style: theme.textTheme.bodyMedium,
                      ),
                      trailing: Text(item['ts'].toString().split('T').first,
                          style: theme.textTheme.labelSmall),
                    );
                  }).toList(),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Center(child: AdBannerGate(propertyTypeKey: propertyTypeKey)),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _quickAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppColors.ink),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const Spacer(),
          Text(value,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink)),
          Text(label,
              style: const TextStyle(fontSize: 11, color: AppColors.slate)),
        ],
      ),
    );
  }
}
