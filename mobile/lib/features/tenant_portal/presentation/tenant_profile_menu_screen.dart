// features/tenant_portal/presentation/tenant_profile_menu_screen.dart
//
// Screen 14 — profile header + menu list (payments, complaints, logout…).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/login_flow.dart';
import '../../complaints/presentation/complaint_details_screen.dart';
import '../../complaints/presentation/raise_complaint_screen.dart';
import '../domain/tenant_property_profile.dart';
import 'mess_menu_screen.dart';
import 'move_out_notice_screen.dart';
import 'tenant_dashboard_screen.dart'
    show myComplaintsProvider, myTenancyProvider, hasOwnerContextProvider;

const _brand = Color(0xFF6D28D9);
const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _bg = Color(0xFFF8FAFC);

class TenantProfileMenuScreen extends ConsumerWidget {
  final VoidCallback? onOpenPayments;

  const TenantProfileMenuScreen({super.key, this.onOpenPayments});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenancy = ref.watch(myTenancyProvider).valueOrNull ?? {};
    final hasOwner =
        ref.watch(hasOwnerContextProvider).valueOrNull ?? false;
    final name = tenancy['full_name']?.toString() ?? 'Tenant';
    final initial =
        name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final profile = TenantPropertyProfile.fromTenancy(tenancy);
    final roomLine = profile.headerBadge(tenancy);
    final email = tenancy['email']?.toString() ??
        tenancy['owner_phone']?.toString() ??
        '';

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        foregroundColor: _ink,
        title: const Text(
          'Profile / Menu',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: const Color(0xFFEDE9FE),
                  child: Text(
                    initial,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: _brand,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(roomLine,
                    style: const TextStyle(color: _muted, fontSize: 13)),
                if (email.isNotEmpty)
                  Text(email,
                      style: const TextStyle(color: _muted, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _MenuTile(
            icon: Icons.person_outline,
            title: 'My Profile',
            onTap: () => context.push('/profile'),
          ),
          _MenuTile(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Payment History',
            onTap: () {
              Navigator.pop(context);
              onOpenPayments?.call();
            },
          ),
          _MenuTile(
            icon: Icons.assignment_outlined,
            title: 'My Complaints',
            onTap: () async {
              final list =
                  await ref.read(myComplaintsProvider.future);
              if (!context.mounted) return;
              if (list.isEmpty) {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => RaiseComplaintScreen(
                      propertyId:
                          tenancy['property_id']?.toString() ?? '',
                      nodeId: tenancy['node_id']?.toString() ?? '',
                    ),
                  ),
                );
                ref.invalidate(myComplaintsProvider);
                return;
              }
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      ComplaintDetailsScreen(complaint: list.first),
                ),
              );
            },
          ),
          _MenuTile(
            icon: Icons.logout_rounded,
            title: 'Move-Out Status',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      MoveOutNoticeScreen(tenancy: tenancy),
                ),
              );
            },
          ),
          _MenuTile(
            icon: Icons.notifications_outlined,
            title: 'Notifications',
            onTap: () => context.push('/notifications'),
          ),
          _MenuTile(
            icon: Icons.help_outline,
            title: 'Help & Support',
            onTap: () async {
              final phone = tenancy['owner_phone']?.toString() ?? '';
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    phone.isEmpty
                        ? 'Contact your property owner for support.'
                        : 'Call owner: $phone',
                  ),
                ),
              );
            },
          ),
          _MenuTile(
            icon: Icons.settings_outlined,
            title: 'App Settings',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Settings coming soon.')),
              );
            },
          ),
          if (hasOwner)
            _MenuTile(
              icon: Icons.business_center_outlined,
              title: 'Switch to Owner View',
              onTap: () =>
                  switchWorkspaceRole(context, ref, toTenant: false),
            ),
          const SizedBox(height: 8),
          _MenuTile(
            icon: Icons.exit_to_app_rounded,
            title: 'Logout',
            danger: true,
            onTap: () async {
              await ref.read(authRepositoryProvider).logout();
              if (context.mounted) context.go('/login');
            },
          ),
          const SizedBox(height: 16),
          if (profile.showsMessMenu)
            TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MessMenuScreen()),
                );
              },
              child: const Text('Mess Menu', style: TextStyle(color: _brand)),
            ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool danger;

  const _MenuTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? const Color(0xFFDC2626) : _ink;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: color),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: danger ? color : _muted,
        ),
      ),
    );
  }
}
