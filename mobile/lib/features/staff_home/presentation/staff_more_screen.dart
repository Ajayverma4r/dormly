// features/staff_home/presentation/staff_more_screen.dart
//
// Staff "More" tab: day-to-day tools the staff role is allowed to use, plus
// account actions. No billing, subscription, staff or property settings.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/login_flow.dart'
    show otherWorkspacesProvider, switchWorkspace;
import '../../auth/presentation/profile_creation_screen.dart';
import '../../complaints/presentation/complaints_list_screen.dart';
import '../../home/presentation/profile_screen.dart' show myProfileProvider;
import '../../properties/domain/property_archetype.dart';
import '../../tenant_portal/presentation/owner_mess_menu_screen.dart';
import 'staff_meter_readings_screen.dart';
import 'staff_tenants_screen.dart';
import 'staff_ui.dart';

class StaffMoreScreen extends ConsumerWidget {
  final String propertyId;
  final String propertyName;

  const StaffMoreScreen(
      {super.key, required this.propertyId, required this.propertyName});

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need to sign in again to use Dormly.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: StaffColors.danger),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(authRepositoryProvider).logout();
    if (context.mounted) context.go('/splash');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(myProfileProvider).valueOrNull;
    final name = profile?.name?.trim() ?? '';
    final archetype = staffPropertyArchetype(ref, propertyId);
    final canSwitch =
        ref.watch(otherWorkspacesProvider).valueOrNull?.isNotEmpty ?? false;

    final tools = <_MoreItem>[
      _MoreItem(
        key: 'my-tasks',
        icon: Icons.assignment_turned_in_outlined,
        title: 'My Tasks',
        subtitle: 'Complaints assigned to you',
        onTap: () => _push(
          context,
          ComplaintsListScreen(
              propertyId: propertyId, initialFilter: myTasksFilter),
        ),
      ),
      if (archetype?.showsMessMenu ?? false)
        _MoreItem(
          key: 'mess-menu',
          icon: Icons.restaurant_menu_outlined,
          title: 'Mess Menu',
          subtitle: 'View and update the weekly menu',
          onTap: () =>
              _push(context, OwnerMessMenuScreen(propertyId: propertyId)),
        ),
      if (archetype?.showsMeterUpload ?? false)
        _MoreItem(
          key: 'meter-readings',
          icon: Icons.speed_outlined,
          title: 'Meter Readings',
          subtitle: 'Record electricity readings',
          onTap: () =>
              _push(context, StaffMeterReadingsScreen(propertyId: propertyId)),
        ),
      _MoreItem(
        key: 'tenants',
        icon: Icons.groups_outlined,
        title: archetype?.peopleLabel ?? 'Tenants',
        subtitle: 'Names and rooms (limited view)',
        onTap: () => _push(context, StaffTenantsScreen(propertyId: propertyId)),
      ),
    ];

    final account = <_MoreItem>[
      _MoreItem(
        key: 'notifications',
        icon: Icons.notifications_none_rounded,
        title: 'Notifications',
        onTap: () => context.push('/notifications'),
      ),
      _MoreItem(
        key: 'profile',
        icon: Icons.person_outline_rounded,
        title: 'Edit Profile',
        subtitle: 'Name, email, photo',
        onTap: () async {
          final updated = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) =>
                  const ProfileCreationScreen(fromOnboarding: false),
            ),
          );
          if (updated == true) ref.invalidate(myProfileProvider);
        },
      ),
      if (canSwitch)
        _MoreItem(
          key: 'switch-workspace',
          icon: Icons.swap_horiz_rounded,
          title: 'Switch Workspace',
          onTap: () => switchWorkspace(context, ref),
        ),
      _MoreItem(
        key: 'logout',
        icon: Icons.logout_rounded,
        title: 'Log out',
        destructive: true,
        onTap: () => _logout(context, ref),
      ),
    ];

    return Scaffold(
      backgroundColor: StaffColors.bg,
      appBar: const StaffAppBar(title: 'More', showBack: false),
      body: ListView(
        key: const Key('staff-more'),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Container(
            decoration: staffCardDecoration(),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: StaffColors.brandSoft,
                  child: Text(
                    initialOf(name),
                    style: const TextStyle(
                      color: StaffColors.brand,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty ? 'Staff member' : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: StaffColors.ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        propertyName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: StaffColors.muted, fontSize: 12.5),
                      ),
                      const SizedBox(height: 6),
                      const StaffPill(
                        label: 'Staff',
                        fg: StaffColors.brand,
                        bg: StaffColors.brandSoft,
                        icon: Icons.verified_user_outlined,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const _GroupLabel('Tools'),
          _MoreGroup(items: tools),
          const SizedBox(height: 18),
          const _GroupLabel('Account'),
          _MoreGroup(items: account),
        ],
      ),
    );
  }
}

class _MoreItem {
  final String key;
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool destructive;
  final VoidCallback onTap;

  const _MoreItem({
    required this.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.destructive = false,
  });
}

class _GroupLabel extends StatelessWidget {
  final String text;
  const _GroupLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: StaffColors.muted,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _MoreGroup extends StatelessWidget {
  final List<_MoreItem> items;
  const _MoreGroup({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: staffCardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, color: StaffColors.border, indent: 60),
            _MoreTile(item: items[i]),
          ],
        ],
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  final _MoreItem item;
  const _MoreTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final color = item.destructive ? StaffColors.danger : StaffColors.brand;
    return Material(
      color: Colors.transparent,
      child: ListTile(
        key: Key('staff-more-${item.key}'),
        onTap: item.onTap,
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: item.destructive
                ? StaffColors.dangerSoft
                : StaffColors.brandSoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(item.icon, color: color, size: 20),
        ),
        title: Text(
          item.title,
          style: TextStyle(
            color: item.destructive ? StaffColors.danger : StaffColors.ink,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        subtitle: item.subtitle == null
            ? null
            : Text(item.subtitle!,
                style: const TextStyle(color: StaffColors.muted, fontSize: 12)),
        trailing: item.destructive
            ? null
            : const Icon(Icons.chevron_right_rounded, color: StaffColors.muted),
      ),
    );
  }
}
