// features/structure/presentation/property_more_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/data/auth_repository.dart';
import '../../staff/presentation/staff_list_screen.dart';
import '../../subscription/presentation/paywall_screen.dart';

class PropertyMoreScreen extends ConsumerWidget {
  final String propertyId;
  final String propertyName;
  final String? role;

  const PropertyMoreScreen({super.key, required this.propertyId, required this.propertyName, required this.role});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOwnerOrAdmin = role == 'owner' || role == 'admin';
    final canManage = isOwnerOrAdmin || role == 'manager';

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(propertyName, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          if (isOwnerOrAdmin) ...[
            _tile(context, 'Team', 'Manage staff & managers', Icons.badge_outlined,
                () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => StaffListScreen(propertyId: propertyId)))),
            const SizedBox(height: 10),
            _tile(context, 'Subscription & Billing', 'Manage your plan, view invoices', Icons.workspace_premium_outlined,
                () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PaywallScreen()))),
          ],
          if (canManage) ...[
            const SizedBox(height: 10),
            _tile(context, 'Structure Settings', 'Rename, reorder, add levels', Icons.tune,
                () => context.push('/dashboard/$propertyId/structure')),
          ],
          const SizedBox(height: 10),
          _tile(context, 'All Properties', 'Switch to another property', Icons.apartment_outlined,
              () => context.go('/home')),
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
              label: const Text('Logout', style: TextStyle(color: AppColors.danger)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, String title, String subtitle, IconData icon, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            Icon(icon, color: AppColors.blueprint),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(subtitle, style: const TextStyle(color: AppColors.slate, fontSize: 12)),
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