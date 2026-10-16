// features/staff_home/presentation/staff_home_tab.dart
//
// Staff Home: greeting, live counts, the staff member's task queue and
// shortcuts. Every figure comes from an API the backend lets staff call.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/presentation/login_flow.dart'
    show otherWorkspacesProvider, switchWorkspace;
import '../../complaints/presentation/complaint_details_screen.dart';
import '../../complaints/presentation/complaint_ui.dart';
import '../../complaints/presentation/complaints_list_screen.dart';
import '../../home/presentation/profile_screen.dart' show myProfileProvider;
import '../../notifications/presentation/notifications_providers.dart';
import '../../properties/domain/property_archetype.dart';
import '../../search/presentation/global_search_screen.dart'
    show openGlobalSearch;
import '../../structure/presentation/property_shell_screen.dart'
    show propertyDetailProvider;
import '../../structure/presentation/rooms/rooms_tree_provider.dart';
import '../../tenant_portal/presentation/owner_mess_menu_screen.dart';
import '../domain/staff_rooms_summary.dart';
import '../domain/staff_tasks.dart';
import 'staff_meter_readings_screen.dart';
import 'staff_tenants_screen.dart';
import 'staff_ui.dart';

const _maxTasks = 5;

class StaffHomeTab extends ConsumerWidget {
  final String propertyId;
  final String propertyName;
  final VoidCallback onOpenComplaints;
  final VoidCallback onOpenRooms;
  final VoidCallback onOpenGatePasses;

  const StaffHomeTab({
    super.key,
    required this.propertyId,
    required this.propertyName,
    required this.onOpenComplaints,
    required this.onOpenRooms,
    required this.onOpenGatePasses,
  });

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(myProfileProvider);
    ref.invalidate(roomsTreeProvider(propertyId));
    ref.invalidate(staffGatePassesProvider(propertyId));
    ref.read(unreadNotificationsCountProvider.notifier).refresh().ignore();
    await ref
        .refresh(complaintsProvider(propertyId).future)
        .catchError((_) => const <Map<String, dynamic>>[]);
  }

  Future<void> _openComplaint(
      BuildContext context, WidgetRef ref, Map<String, dynamic> c) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ComplaintDetailsScreen(complaint: c)),
    );
    ref.invalidate(complaintsProvider(propertyId));
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final complaintsAsync = ref.watch(complaintsProvider(propertyId));
    final userId = ref.watch(complaintViewerUserIdProvider).valueOrNull;
    final roomsAsync = ref.watch(roomsTreeProvider(propertyId));
    final archetype = staffPropertyArchetype(ref, propertyId);
    final showGatePasses = archetype?.showsGatePass ?? false;
    final pendingPasses = showGatePasses
        ? ref
            .watch(staffGatePassesProvider(propertyId))
            .valueOrNull
            ?.where((p) => (p['status']?.toString() ?? 'pending') == 'pending')
            .length
        : null;

    final counts =
        complaintsAsync.whenData((all) => staffComplaintCounts(all, userId));
    final rooms = roomsAsync.whenData(summarizeRooms);

    return Scaffold(
      backgroundColor: StaffColors.bg,
      body: SafeArea(
        child: RefreshIndicator(
          color: StaffColors.brand,
          onRefresh: () => _refresh(ref),
          child: ListView(
            key: const Key('staff-home'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              _Header(propertyId: propertyId, propertyName: propertyName),
              const SizedBox(height: 18),
              _SummaryGrid(
                cards: [
                  _SummaryData(
                    key: 'open',
                    icon: Icons.report_problem_outlined,
                    color: StaffColors.danger,
                    label: 'Open Complaints',
                    value: counts.whenData((c) => '${c.active}'),
                    onTap: onOpenComplaints,
                  ),
                  _SummaryData(
                    key: 'mine',
                    icon: Icons.assignment_turned_in_outlined,
                    color: StaffColors.brand,
                    label: 'My Tasks',
                    value: counts.whenData((c) => '${c.mine}'),
                    onTap: () => _push(
                      context,
                      ComplaintsListScreen(
                          propertyId: propertyId, initialFilter: myTasksFilter),
                    ),
                  ),
                  _SummaryData(
                    key: 'rooms',
                    icon: Icons.meeting_room_outlined,
                    color: const Color(0xFF2563EB),
                    label: rooms.valueOrNull?.usesBeds == false
                        ? 'Total Units'
                        : 'Total Rooms',
                    value: rooms.whenData((r) => '${r.totalRooms}'),
                    onTap: onOpenRooms,
                  ),
                  _SummaryData(
                    key: 'beds',
                    icon: Icons.bed_outlined,
                    color: StaffColors.success,
                    label: rooms.valueOrNull?.usesBeds == false
                        ? 'Occupied Units'
                        : 'Total Beds',
                    value: rooms.whenData(
                      (r) =>
                          r.usesBeds ? '${r.totalBeds}' : '${r.occupiedRooms}',
                    ),
                    onTap: onOpenRooms,
                  ),
                ],
              ),
              const SizedBox(height: 22),
              StaffSectionHeader(
                title: "Today's Tasks",
                actionLabel: 'View all',
                onAction: onOpenComplaints,
              ),
              const SizedBox(height: 6),
              complaintsAsync.when(
                loading: () => const _CardShell(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child:
                          CircularProgressIndicator(color: StaffColors.brand),
                    ),
                  ),
                ),
                error: (e, _) => _CardShell(
                  child: StaffErrorState(
                    key: const Key('staff-tasks-error'),
                    error: e,
                    fallback: "Couldn't load your tasks. Please try again.",
                    onRetry: () =>
                        ref.invalidate(complaintsProvider(propertyId)),
                  ),
                ),
                data: (all) {
                  final queue =
                      staffTaskQueue(all, userId).take(_maxTasks).toList();
                  if (queue.isEmpty) {
                    return const _CardShell(
                      child: StaffMessage(
                        key: Key('staff-tasks-empty'),
                        icon: Icons.task_alt_rounded,
                        title: "You're all caught up",
                        subtitle:
                            'New complaints from residents and work assigned to you will show up here.',
                      ),
                    );
                  }
                  return _CardShell(
                    child: Column(
                      children: [
                        for (var i = 0; i < queue.length; i++) ...[
                          if (i > 0)
                            const Divider(
                                height: 1,
                                color: StaffColors.border,
                                indent: 64),
                          _TaskRow(
                            complaint: queue[i],
                            userId: userId,
                            onTap: () => _openComplaint(context, ref, queue[i]),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 22),
              const StaffSectionHeader(title: 'Quick Actions'),
              const SizedBox(height: 10),
              _QuickActions(
                actions: [
                  _QuickAction(
                    icon: Icons.report_problem_outlined,
                    label: 'Complaints',
                    badge: counts.valueOrNull?.active,
                    onTap: onOpenComplaints,
                  ),
                  _QuickAction(
                    icon: Icons.bed_outlined,
                    label: 'Rooms & Beds',
                    onTap: onOpenRooms,
                  ),
                  if (showGatePasses)
                    _QuickAction(
                      icon: Icons.badge_outlined,
                      label: 'Gate Passes',
                      badge: pendingPasses,
                      onTap: onOpenGatePasses,
                    ),
                  if (archetype?.showsMessMenu ?? false)
                    _QuickAction(
                      icon: Icons.restaurant_menu_outlined,
                      label: 'Mess Menu',
                      onTap: () => _push(
                          context, OwnerMessMenuScreen(propertyId: propertyId)),
                    ),
                  if (archetype?.showsMeterUpload ?? false)
                    _QuickAction(
                      icon: Icons.speed_outlined,
                      label: 'Meter Readings',
                      onTap: () => _push(context,
                          StaffMeterReadingsScreen(propertyId: propertyId)),
                    ),
                  _QuickAction(
                    icon: Icons.groups_outlined,
                    label: archetype?.peopleLabel ?? 'Tenants',
                    onTap: () => _push(
                        context, StaffTenantsScreen(propertyId: propertyId)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  final String propertyId;
  final String propertyName;

  const _Header({required this.propertyId, required this.propertyName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(myProfileProvider).valueOrNull?.name?.trim() ?? '';
    final property = ref.watch(propertyDetailProvider(propertyId)).valueOrNull;
    final title = (property?['name']?.toString().trim().isNotEmpty ?? false)
        ? property!['name'].toString().trim()
        : propertyName;
    final unread = ref.watch(unreadNotificationsCountProvider).valueOrNull ?? 0;
    final canSwitch =
        ref.watch(otherWorkspacesProvider).valueOrNull?.isNotEmpty ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/images/logo.png',
                height: 30,
                width: 30,
                errorBuilder: (_, __, ___) => const Icon(
                    Icons.home_work_rounded,
                    color: StaffColors.brand),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Dormly',
              style: TextStyle(
                color: StaffColors.brand,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const Spacer(),
            IconButton(
              key: const Key('staff-search'),
              tooltip: 'Search',
              onPressed: () => openGlobalSearch(
                context,
                propertyId: propertyId,
                canManage: false,
              ),
              icon: const Icon(Icons.search_rounded, color: StaffColors.ink),
            ),
            IconButton(
              key: const Key('staff-notifications'),
              tooltip: 'Notifications',
              onPressed: () async {
                await context.push('/notifications');
                ref
                    .read(unreadNotificationsCountProvider.notifier)
                    .refresh()
                    .ignore();
              },
              icon: Badge(
                isLabelVisible: unread > 0,
                label: Text(unread > 99 ? '99+' : '$unread'),
                backgroundColor: StaffColors.danger,
                child: const Icon(Icons.notifications_none_rounded,
                    color: StaffColors.ink),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          '${staffGreeting()},',
          style: const TextStyle(
              color: StaffColors.muted,
              fontSize: 14,
              fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 2),
        Text(
          name.isEmpty ? 'Welcome' : name,
          key: const Key('staff-greeting-name'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: StaffColors.ink,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const StaffPill(
              label: 'Staff',
              fg: StaffColors.brand,
              bg: StaffColors.brandSoft,
              icon: Icons.verified_user_outlined,
            ),
            Material(
              color: Colors.white,
              shape: const StadiumBorder(
                  side: BorderSide(color: StaffColors.border)),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: canSwitch ? () => switchWorkspace(context, ref) : null,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.apartment_rounded,
                          size: 14, color: StaffColors.brand),
                      const SizedBox(width: 5),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 200),
                        child: Text(
                          title,
                          key: const Key('staff-property-name'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: StaffColors.ink,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (canSwitch) ...[
                        const SizedBox(width: 2),
                        const Icon(Icons.expand_more_rounded,
                            size: 16, color: StaffColors.muted),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SummaryData {
  final String key;
  final IconData icon;
  final Color color;
  final String label;
  final AsyncValue<String> value;
  final VoidCallback onTap;

  const _SummaryData({
    required this.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.onTap,
  });
}

class _SummaryGrid extends StatelessWidget {
  final List<_SummaryData> cards;
  const _SummaryGrid({required this.cards});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final c in cards)
              SizedBox(width: width, child: _SummaryCard(data: c)),
          ],
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final _SummaryData data;
  const _SummaryCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('staff-summary-${data.key}'),
        borderRadius: BorderRadius.circular(16),
        onTap: data.onTap,
        child: Ink(
          decoration: staffCardDecoration(),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: data.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(data.icon, color: data.color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    data.value.when(
                      loading: () => const SizedBox(
                        height: 26,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: StaffColors.brand),
                          ),
                        ),
                      ),
                      error: (_, __) => const Text(
                        '—',
                        style: TextStyle(
                            color: StaffColors.muted,
                            fontSize: 20,
                            fontWeight: FontWeight.w800),
                      ),
                      data: (v) => Text(
                        v,
                        key: Key('staff-summary-${data.key}-value'),
                        style: const TextStyle(
                          color: StaffColors.ink,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      data.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: StaffColors.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  final Widget child;
  const _CardShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: staffCardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _TaskRow extends StatelessWidget {
  final Map<String, dynamic> complaint;
  final String? userId;
  final VoidCallback onTap;

  const _TaskRow(
      {required this.complaint, required this.userId, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = complaint;
    final room = complaintRoomOf(c);
    final created = complaintCreatedAt(c);
    final subtitle = [
      if (room.isNotEmpty) room,
      if (created != null) formatComplaintDayTime(created),
    ].join(' · ');
    final priority = complaintPriorityStyle(c['priority']?.toString());
    final assignment = complaintAssignmentLabel(c, userId);

    return InkWell(
      key: Key('staff-task-${c['id']}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        child: Row(
          children: [
            ComplaintCategoryIcon(category: complaintCategoryOf(c)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    complaintTitle(c),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: StaffColors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 14),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: StaffColors.muted, fontSize: 12),
                    ),
                  ],
                  if (assignment != null) ...[
                    const SizedBox(height: 6),
                    StaffPill(
                      label: assignment.$1,
                      fg: assignment.$2
                          ? StaffColors.success
                          : StaffColors.muted,
                      bg: assignment.$2
                          ? StaffColors.successSoft
                          : const Color(0xFFF1F5F9),
                      icon: Icons.person_outline_rounded,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (priority != null)
              StaffPill(
                  label: priority.$1,
                  fg: priority.$2,
                  bg: priority.$2.withValues(alpha: 0.1))
            else
              ComplaintStatusBadge(status: complaintStatusOf(c)),
            const Icon(Icons.chevron_right_rounded, color: StaffColors.muted),
          ],
        ),
      ),
    );
  }
}

class _QuickAction {
  final IconData icon;
  final String label;
  final int? badge;
  final VoidCallback onTap;

  const _QuickAction(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.badge});
}

class _QuickActions extends StatelessWidget {
  final List<_QuickAction> actions;
  const _QuickActions({required this.actions});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final columns = constraints.maxWidth >= 420 ? 4 : 3;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final a in actions)
              SizedBox(
                width: width,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: Key('staff-action-${a.label}'),
                    borderRadius: BorderRadius.circular(16),
                    onTap: a.onTap,
                    child: Ink(
                      decoration: staffCardDecoration(),
                      padding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 6),
                      child: Column(
                        children: [
                          Badge(
                            isLabelVisible: (a.badge ?? 0) > 0,
                            label: Text('${a.badge ?? 0}'),
                            backgroundColor: StaffColors.brand,
                            child: Container(
                              width: 42,
                              height: 42,
                              decoration: const BoxDecoration(
                                color: StaffColors.brandSoft,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(a.icon,
                                  color: StaffColors.brand, size: 21),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            a.label,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: StaffColors.ink,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
