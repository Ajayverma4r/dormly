// features/complaints/presentation/complaints_list_screen.dart
//
// All Complaints for one property: status filter chips with live counts,
// compact rows, and full Complaint Details on tap.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/complaints_repository.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/login_flow.dart';
import '../../structure/presentation/property_shell_screen.dart'
    show propertyDetailProvider;
import 'complaint_details_screen.dart';
import 'complaint_ui.dart';

final complaintsProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, propertyId) =>
      ref.watch(complaintsRepositoryProvider).listForProperty(propertyId),
);

/// Always-visible filters; `assigned` and `closed` appear once complaints use them.
const _primaryFilters = ['all', 'open', 'in_progress', 'resolved'];

/// Staff-only filter: complaints assigned to the signed-in user.
const myTasksFilter = 'mine';

class ComplaintsListScreen extends ConsumerStatefulWidget {
  final String propertyId;
  final bool isRoot;

  /// A tab inside a shell: titled "Complaints", no back button or account actions.
  final bool asTab;
  final String initialFilter;
  const ComplaintsListScreen({
    super.key,
    required this.propertyId,
    this.isRoot = false,
    this.asTab = false,
    this.initialFilter = 'all',
  });

  @override
  ConsumerState<ComplaintsListScreen> createState() =>
      _ComplaintsListScreenState();
}

class _ComplaintsListScreenState extends ConsumerState<ComplaintsListScreen> {
  late String _filter = widget.initialFilter;

  Future<void> _open(Map<String, dynamic> complaint) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ComplaintDetailsScreen(complaint: complaint),
      ),
    );
    if (mounted) ref.invalidate(complaintsProvider(widget.propertyId));
  }

  @override
  Widget build(BuildContext context) {
    final propertyId = widget.propertyId;
    final complaintsAsync = ref.watch(complaintsProvider(propertyId));
    final propertyName = complaintPropertyFrom(
      ref.watch(propertyDetailProvider(propertyId)).valueOrNull,
      propertyId,
    )?.name;
    final isStaff =
        ref.watch(complaintViewerRoleProvider).valueOrNull == 'staff';
    final viewerId =
        isStaff ? ref.watch(complaintViewerUserIdProvider).valueOrNull : null;

    return Scaffold(
      backgroundColor: ComplaintColors.bg,
      appBar: AppBar(
        backgroundColor: ComplaintColors.bg,
        foregroundColor: ComplaintColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: !widget.asTab,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.isRoot || widget.asTab ? 'Complaints' : 'All Complaints',
              style: const TextStyle(
                color: ComplaintColors.ink,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (propertyName != null && propertyName.isNotEmpty)
              Text(
                propertyName,
                style:
                    const TextStyle(color: ComplaintColors.muted, fontSize: 12),
              ),
          ],
        ),
        actions: widget.isRoot
            ? [
                if (ref
                        .watch(otherWorkspacesProvider)
                        .valueOrNull
                        ?.isNotEmpty ??
                    false)
                  IconButton(
                    icon: const Icon(Icons.swap_horiz_rounded),
                    tooltip: 'Switch Workspace',
                    onPressed: () => switchWorkspace(context, ref),
                  ),
                IconButton(
                  icon: const Icon(Icons.logout),
                  tooltip: 'Logout',
                  onPressed: () async {
                    await ref.read(authRepositoryProvider).logout();
                    if (context.mounted) context.go('/splash');
                  },
                ),
              ]
            : null,
      ),
      body: complaintsAsync.when(
        loading: () => const Center(
          key: Key('complaints-loading'),
          child: CircularProgressIndicator(color: ComplaintColors.brand),
        ),
        error: (err, _) => _Message(
          key: const Key('complaints-error'),
          icon: Icons.cloud_off_rounded,
          title: complaintErrorMessage(err),
          action: FilledButton(
            onPressed: () => ref.invalidate(complaintsProvider(propertyId)),
            style:
                FilledButton.styleFrom(backgroundColor: ComplaintColors.brand),
            child: const Text('Retry'),
          ),
        ),
        data: (raw) {
          final all = sortComplaintsNewestFirst(raw);
          final counts = complaintStatusCounts(all);
          bool isMine(Map<String, dynamic> c) =>
              viewerId != null && c['assigned_to']?.toString() == viewerId;
          final showMine =
              isStaff && all.any((c) => c.containsKey('assigned_to'));
          if (showMine) counts[myTasksFilter] = all.where(isMine).length;
          final filters = [
            ..._primaryFilters,
            if (showMine || _filter == myTasksFilter) myTasksFilter,
            for (final s in ['assigned', 'closed'])
              if ((counts[s] ?? 0) > 0 || _filter == s) s,
          ]..sort((a, b) => _filterOrder(a).compareTo(_filterOrder(b)));
          final visible = switch (_filter) {
            'all' => all,
            myTasksFilter => all.where(isMine).toList(),
            _ => all.where((c) => complaintStatusOf(c) == _filter).toList(),
          };

          return RefreshIndicator(
            color: ComplaintColors.brand,
            onRefresh: () => ref.refresh(complaintsProvider(propertyId).future),
            child: all.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 120),
                      _Message(
                        key: const Key('complaints-empty'),
                        icon: Icons.check_circle_outline_rounded,
                        title: 'No complaints yet',
                        subtitle: isStaff
                            ? 'New complaints from residents, and complaints assigned to you, will appear here.'
                            : 'Complaints raised for this property will appear here.',
                        action: OutlinedButton.icon(
                          key: const Key('complaints-empty-refresh'),
                          onPressed: () =>
                              ref.invalidate(complaintsProvider(propertyId)),
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Refresh'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: ComplaintColors.brand,
                            side:
                                const BorderSide(color: ComplaintColors.border),
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    children: [
                      SizedBox(
                        height: 36,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final f in filters) ...[
                                if (f != filters.first)
                                  const SizedBox(width: 8),
                                _FilterChip(
                                  key: Key('complaint-filter-$f'),
                                  label: switch (f) {
                                    'all' => 'All',
                                    myTasksFilter => 'My Tasks',
                                    _ => complaintStatusStyle(f).label,
                                  },
                                  count: counts[f] ?? 0,
                                  selected: _filter == f,
                                  onTap: () => setState(() => _filter = f),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (visible.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 60),
                          child: _Message(
                            key: const Key('complaints-filter-empty'),
                            icon: Icons.filter_alt_off_outlined,
                            title: _filter == myTasksFilter
                                ? 'No complaints are assigned to you'
                                : 'No ${complaintStatusStyle(_filter).label.toLowerCase()} complaints',
                          ),
                        )
                      else
                        for (final c in visible) ...[
                          ComplaintListTile(
                            complaint: c,
                            onTap: () => _open(c),
                            assignmentViewerId:
                                isStaff ? (viewerId ?? '') : null,
                          ),
                          const SizedBox(height: 10),
                        ],
                    ],
                  ),
          );
        },
      ),
    );
  }

  static int _filterOrder(String f) => switch (f) {
        'all' => -2,
        myTasksFilter => -1,
        _ => complaintStatuses.indexOf(f),
      };
}

class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? ComplaintColors.brand : ComplaintColors.card,
      shape: StadiumBorder(
        side: BorderSide(
            color: selected ? ComplaintColors.brand : ComplaintColors.border),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Center(
            child: Text(
              '$label ($count)',
              style: TextStyle(
                color: selected ? Colors.white : ComplaintColors.muted,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ComplaintListTile extends StatelessWidget {
  final Map<String, dynamic> complaint;
  final VoidCallback onTap;

  /// When set (staff view), the row also shows priority and who it is assigned to.
  final String? assignmentViewerId;

  const ComplaintListTile({
    super.key,
    required this.complaint,
    required this.onTap,
    this.assignmentViewerId,
  });

  @override
  Widget build(BuildContext context) {
    final c = complaint;
    final room = complaintRoomOf(c);
    final created = complaintCreatedAt(c);
    final subtitle = [
      if (room.isNotEmpty) room,
      if (created != null) formatComplaintDay(created),
    ].join(' · ');
    final assignment = assignmentViewerId == null
        ? null
        : complaintAssignmentLabel(c, assignmentViewerId);
    final priority = assignmentViewerId == null
        ? null
        : complaintPriorityStyle(c['priority']?.toString());

    return Material(
      color: ComplaintColors.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: ComplaintColors.border),
          ),
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
                        color: ComplaintColors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: ComplaintColors.muted, fontSize: 12),
                      ),
                    ],
                    if (assignment != null || priority != null) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (priority != null)
                            _MiniTag(
                              label: priority.$1,
                              fg: priority.$2,
                              bg: priority.$2.withValues(alpha: 0.1),
                            ),
                          if (assignment != null)
                            _MiniTag(
                              key: const Key('complaint-assignment'),
                              label: assignment.$1,
                              fg: assignment.$2
                                  ? const Color(0xFF16A34A)
                                  : ComplaintColors.muted,
                              bg: assignment.$2
                                  ? const Color(0xFFDCFCE7)
                                  : const Color(0xFFF1F5F9),
                              icon: Icons.person_outline_rounded,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ComplaintStatusBadge(status: complaintStatusOf(c)),
              const Icon(Icons.chevron_right_rounded,
                  color: ComplaintColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  final String label;
  final Color fg;
  final Color bg;
  final IconData? icon;

  const _MiniTag(
      {super.key,
      required this.label,
      required this.fg,
      required this.bg,
      this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: fg),
            const SizedBox(width: 3),
          ],
          Text(label,
              style: TextStyle(
                  color: fg, fontSize: 10.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const _Message({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: ComplaintColors.muted),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: ComplaintColors.ink,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: ComplaintColors.muted, fontSize: 13),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
