// features/structure/presentation/property_more_screen.dart
//
// Bottom-nav "Menu" tab.
// Hostel/PG → Screen 5 dark "More" design (profile + Property / Reports / Settings).
// Rental / apartment → previous light Menu (unchanged).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/login_flow.dart';
import '../../home/presentation/profile_screen.dart' show myProfileProvider;
import '../../staff/presentation/staff_list_screen.dart';
import '../../subscription/presentation/paywall_screen.dart';
import '../../complaints/presentation/complaints_list_screen.dart';
import '../../reports/presentation/reports_screen.dart';
import '../../analytics/presentation/analytics_dashboard_screen.dart';
import '../../tenant_portal/presentation/owner_mess_menu_screen.dart';
import '../../properties/domain/property_archetype.dart';
import 'property_shell_screen.dart' show propertyDetailProvider;

final _hasTenantContextProvider = FutureProvider.autoDispose<bool>((ref) async {
  final contexts = await ref.watch(authRepositoryProvider).listContexts();
  return contexts.any((c) => c['role']?.toString() == 'tenant');
});

class _H {
  static const bg = Color(0xFF0D1623);
  static const card = Color(0xFF151F30);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF94A3B8);
  static const purple = Color(0xFF8B5CF6);
  static const danger = Color(0xFFF87171);
  static const divider = Color(0xFF243044);
  static const chevron = Color(0xFF64748B);
}

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
    final hasTenantContext =
        ref.watch(_hasTenantContextProvider).valueOrNull ?? false;
    final property = ref.watch(propertyDetailProvider(propertyId)).valueOrNull;
    final archetype = propertyArchetypeFromProperty(property);
    final showStructureSettings =
        canManage && archetype != PropertyArchetype.individualLease;
    final showMessMenu = canManage && archetype.showsMessMenu;

    return _HostelPgMoreBody(
      propertyId: propertyId,
      propertyName: propertyName,
      role: role,
      isOwnerOrAdmin: isOwnerOrAdmin,
      canManage: canManage,
      hasTenantContext: hasTenantContext,
      showMessMenu: showMessMenu,
      showStructureSettings: showStructureSettings,
    );
  }
}

// ── Screen 5 — dark More (all property types) ────────────────────────────

class _HostelPgMoreBody extends ConsumerWidget {
  final String propertyId;
  final String propertyName;
  final String? role;
  final bool isOwnerOrAdmin;
  final bool canManage;
  final bool hasTenantContext;
  final bool showMessMenu;
  final bool showStructureSettings;

  const _HostelPgMoreBody({
    required this.propertyId,
    required this.propertyName,
    required this.role,
    required this.isOwnerOrAdmin,
    required this.canManage,
    required this.hasTenantContext,
    required this.showMessMenu,
    required this.showStructureSettings,
  });

  String get _roleLabel {
    switch (role) {
      case 'owner':
        return 'Owner';
      case 'admin':
        return 'Admin';
      case 'manager':
        return 'Manager';
      default:
        return role == null || role!.isEmpty
            ? 'Staff'
            : '${role![0].toUpperCase()}${role!.substring(1)}';
    }
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    await ref.read(authRepositoryProvider).logout();
    if (context.mounted) context.go('/splash');
  }

  void _openReports(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReportsScreen(propertyId: propertyId),
      ),
    );
  }

  void _openAnalytics(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AnalyticsDashboardScreen(propertyId: propertyId),
      ),
    );
  }

  void _openStructure(BuildContext context) {
    context.push('/dashboard/$propertyId/structure');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(myProfileProvider).valueOrNull;
    final name = (profile?.name ?? '').trim().isEmpty
        ? 'Your profile'
        : profile!.name!.trim();
    final initial =
        name.isEmpty || name == 'Your profile' ? '?' : name[0].toUpperCase();

    final propertyRows = <_MoreRowData>[
      _MoreRowData(
        icon: Icons.home_outlined,
        label: 'My Properties',
        onTap: () => context.push('/properties'),
      ),
      if (showStructureSettings)
        _MoreRowData(
          icon: Icons.settings_outlined,
          label: 'Property Settings',
          onTap: () => _openStructure(context),
        ),
      if (showStructureSettings) ...[
        _MoreRowData(
          icon: Icons.apartment_outlined,
          label: 'Manage Blocks',
          onTap: () => _openStructure(context),
        ),
        _MoreRowData(
          icon: Icons.door_front_door_outlined,
          label: 'Manage Floors',
          onTap: () => _openStructure(context),
        ),
        _MoreRowData(
          icon: Icons.bed_outlined,
          label: 'Manage Rooms',
          onTap: () => _openStructure(context),
        ),
      ],
      if (isOwnerOrAdmin)
        _MoreRowData(
          icon: Icons.badge_outlined,
          label: 'Team Management',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => StaffListScreen(propertyId: propertyId),
            ),
          ),
        ),
      _MoreRowData(
        icon: Icons.build_outlined,
        label: 'Complaints',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ComplaintsListScreen(propertyId: propertyId),
          ),
        ),
      ),
      if (showMessMenu)
        _MoreRowData(
          icon: Icons.restaurant_menu_outlined,
          label: 'Mess Menu',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => OwnerMessMenuScreen(propertyId: propertyId),
            ),
          ),
        ),
    ];

    final reportRows = <_MoreRowData>[
      if (canManage) ...[
        _MoreRowData(
          icon: Icons.bar_chart_outlined,
          label: 'Occupancy Report',
          onTap: () => _openReports(context),
        ),
        _MoreRowData(
          icon: Icons.receipt_long_outlined,
          label: 'Financial Report',
          onTap: () => _openReports(context),
        ),
        _MoreRowData(
          icon: Icons.groups_outlined,
          label: 'Tenant Report',
          onTap: () => _openAnalytics(context),
        ),
        _MoreRowData(
          icon: Icons.photo_outlined,
          label: 'Room Report',
          onTap: () => _openReports(context),
        ),
      ],
    ];

    final settingsRows = <_MoreRowData>[
      _MoreRowData(
        icon: Icons.settings_outlined,
        label: 'App Settings',
        onTap: () => context.push('/profile'),
      ),
      if (isOwnerOrAdmin)
        _MoreRowData(
          icon: Icons.workspace_premium_outlined,
          label: 'Upgrade Plan',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PaywallScreen()),
          ),
        ),
      if (hasTenantContext)
        _MoreRowData(
          icon: Icons.home_outlined,
          label: 'Switch to Tenant View',
          onTap: () => switchWorkspaceRole(context, ref, toTenant: true),
        ),
      _MoreRowData(
        icon: Icons.logout,
        label: 'Logout',
        danger: true,
        onTap: () => _logout(context, ref),
      ),
    ];

    return Scaffold(
      backgroundColor: _H.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            const Text(
              'More',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: _H.textPrimary,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              propertyName,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _H.textSecondary,
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              'Manage your account & settings',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: _H.textSecondary,
              ),
            ),
            const SizedBox(height: 18),
            _ProfileCard(
              initial: initial,
              name: name,
              roleLabel: _roleLabel,
              onTap: () => context.push('/profile'),
            ),
            if (propertyRows.isNotEmpty) ...[
              const SizedBox(height: 22),
              const _SectionTitle('Property'),
              const SizedBox(height: 10),
              _SectionCard(rows: propertyRows),
            ],
            if (reportRows.isNotEmpty) ...[
              const SizedBox(height: 22),
              const _SectionTitle('Reports'),
              const SizedBox(height: 10),
              _SectionCard(rows: reportRows),
            ],
            const SizedBox(height: 22),
            const _SectionTitle('Settings'),
            const SizedBox(height: 10),
            _SectionCard(rows: settingsRows),
          ],
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final String initial;
  final String name;
  final String roleLabel;
  final VoidCallback onTap;

  const _ProfileCard({
    required this.initial,
    required this.name,
    required this.roleLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _H.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: _H.purple,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  initial,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _H.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      roleLabel,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: _H.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: _H.chevron, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: _H.textPrimary,
      ),
    );
  }
}

class _MoreRowData {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  const _MoreRowData({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });
}

class _SectionCard extends StatelessWidget {
  final List<_MoreRowData> rows;

  const _SectionCard({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _H.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            _MoreRow(data: rows[i]),
            if (i < rows.length - 1)
              const Divider(
                height: 1,
                thickness: 1,
                color: _H.divider,
                indent: 52,
                endIndent: 12,
              ),
          ],
        ],
      ),
    );
  }
}

class _MoreRow extends StatelessWidget {
  final _MoreRowData data;

  const _MoreRow({required this.data});

  @override
  Widget build(BuildContext context) {
    final color = data.danger ? _H.danger : _H.textPrimary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(data.icon, color: color, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  data.label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: data.danger ? _H.danger.withValues(alpha: 0.7) : _H.chevron,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
