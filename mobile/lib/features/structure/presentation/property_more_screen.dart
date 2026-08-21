// features/structure/presentation/property_more_screen.dart
//
// Bottom-nav "Menu" tab — secondary destinations that used to live under
// Operations / More.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/data/auth_repository.dart';
import '../../staff/presentation/staff_list_screen.dart';
import '../../subscription/presentation/paywall_screen.dart';
import '../../complaints/presentation/complaints_list_screen.dart';
import '../../reports/presentation/reports_screen.dart';
import '../../analytics/presentation/analytics_dashboard_screen.dart';

class PropertyMoreScreen extends ConsumerWidget {
  final String propertyId;
  final String propertyName;
  final String? role;

  const PropertyMoreScreen({
    super.key,
    required this.propertyId,
    required this.propertyName,
    required this.role,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOwnerOrAdmin = role == 'owner' || role == 'admin';
    final canManage = isOwnerOrAdmin || role == 'manager';

    return Scaffold(
      appBar: AppBar(title: const Text('Menu')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(propertyName, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          const Text(
            'Settings & tools',
            style: TextStyle(color: AppColors.slate, fontSize: 13),
          ),
          const SizedBox(height: 16),
          _tile(
            context,
            'Profile & App Subscription',
            'Your profile and Dormly plan',
            Icons.person_outline,
            () => context.push('/profile'),
          ),
          if (isOwnerOrAdmin) ...[
            const SizedBox(height: 10),
            _tile(
              context,
              'Team Management',
              'Staff & managers',
              Icons.badge_outlined,
              () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => StaffListScreen(propertyId: propertyId),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _tile(
              context,
              'Upgrade Plan',
              'Early Bird Pro pricing',
              Icons.workspace_premium_outlined,
              () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PaywallScreen()),
              ),
            ),
          ],
          const SizedBox(height: 10),
          _tile(
            context,
            'Complaints',
            'Maintenance & resident issues',
            Icons.build_outlined,
            () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) =>
                    ComplaintsListScreen(propertyId: propertyId),
              ),
            ),
          ),
          if (canManage) ...[
            const SizedBox(height: 10),
            _tile(
              context,
              'Analytics & Reports',
              'Revenue, occupancy, PDF/CSV exports',
              Icons.bar_chart_outlined,
              () => _openAnalyticsReports(context),
            ),
            const SizedBox(height: 10),
            _tile(
              context,
              'Structure Settings',
              'Rename, reorder, add levels',
              Icons.tune,
              () => context.push('/dashboard/$propertyId/structure'),
            ),
          ],
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: () async {
                await ref.read(authRepositoryProvider).logout();
                if (context.mounted) context.go('/login');
              },
              icon: const Icon(Icons.logout, color: AppColors.danger),
              label: const Text('Logout',
                  style: TextStyle(color: AppColors.danger)),
            ),
          ),
        ],
      ),
    );
  }

  void _openAnalyticsReports(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.insights_outlined,
                  color: AppColors.positive),
              title: const Text('Analytics'),
              subtitle: const Text('Revenue, occupancy, trends'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        AnalyticsDashboardScreen(propertyId: propertyId),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined,
                  color: Color(0xFF0891B2)),
              title: const Text('Reports'),
              subtitle: const Text('Downloadable PDF / CSV'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ReportsScreen(propertyId: propertyId),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    VoidCallback onTap,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.blueprint),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(subtitle,
                      style: const TextStyle(
                          color: AppColors.slate, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}
