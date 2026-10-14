// features/structure/presentation/dashboard_recent_complaints.dart
//
// "Recent Complaints" card under Room Occupancy on the owner/manager
// dashboard. Reads the selected property's complaints through the existing
// property-scoped endpoint and opens the existing list and detail screens.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../complaints/presentation/complaint_details_screen.dart';
import '../../complaints/presentation/complaints_list_screen.dart';
import 'hostel_pg_dashboard_body.dart' show HostelPgDashboardColors;

final _when = DateFormat('d MMM yyyy, h:mm a');

DateTime? _created(Map<String, dynamic> c) =>
    DateTime.tryParse(c['created_at']?.toString() ?? '')?.toLocal();

/// Newest first by submission time; rows without a date go last.
List<Map<String, dynamic>> latestComplaints(
  List<Map<String, dynamic>> all, {
  int limit = 3,
}) {
  final sorted = [...all]..sort((a, b) {
      final da = _created(a);
      final db = _created(b);
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });
  return sorted.take(limit).toList();
}

class DashboardRecentComplaints extends ConsumerWidget {
  final String propertyId;

  const DashboardRecentComplaints({super.key, required this.propertyId});

  Future<void> _openAll(BuildContext context, WidgetRef ref) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ComplaintsListScreen(propertyId: propertyId),
      ),
    );
    ref.invalidate(complaintsProvider(propertyId));
  }

  Future<void> _openOne(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> complaint,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ComplaintDetailsScreen(complaint: complaint),
      ),
    );
    ref.invalidate(complaintsProvider(propertyId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(complaintsProvider(propertyId));

    final Widget body = async.when(
      loading: () => const _Shell(
        key: Key('recent-complaints-loading'),
        child: SizedBox(
          height: 56,
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      ),
      error: (_, __) => _Shell(
        key: const Key('recent-complaints-error'),
        child: Row(
          children: [
            Icon(Icons.cloud_off_rounded,
                color: HostelPgDashboardColors.textSecondary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "Couldn't load complaints right now.",
                style: TextStyle(
                  color: HostelPgDashboardColors.textSecondary,
                  fontSize: 12.5,
                ),
              ),
            ),
            TextButton(
              onPressed: () => ref.invalidate(complaintsProvider(propertyId)),
              child: Text(
                'Retry',
                style: TextStyle(
                  color: HostelPgDashboardColors.purple,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
      data: (all) {
        final recent = latestComplaints(all);
        if (recent.isEmpty) {
          return _Shell(
            key: const Key('recent-complaints-empty'),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline_rounded,
                    color: HostelPgDashboardColors.green, size: 20),
                const SizedBox(width: 10),
                Text(
                  'No complaints yet',
                  style: TextStyle(
                    color: HostelPgDashboardColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          );
        }
        return _Shell(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < recent.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    indent: 58,
                    color: HostelPgDashboardColors.cardBorder,
                  ),
                _ComplaintRow(
                  complaint: recent[i],
                  onTap: () => _openOne(context, ref, recent[i]),
                ),
              ],
            ],
          ),
        );
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Recent Complaints',
                style: TextStyle(
                  color: HostelPgDashboardColors.textPrimary,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            GestureDetector(
              key: const Key('recent-complaints-view-all'),
              onTap: () => _openAll(context, ref),
              child: Text(
                'View All →',
                style: TextStyle(
                  color: HostelPgDashboardColors.purple,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        body,
      ],
    );
  }
}

class _Shell extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _Shell({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: HostelPgDashboardColors.cardElevated,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: HostelPgDashboardColors.cardBorder),
      ),
      child: child,
    );
  }
}

class _ComplaintRow extends StatelessWidget {
  final Map<String, dynamic> complaint;
  final VoidCallback onTap;

  const _ComplaintRow({required this.complaint, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = complaint;
    final category = c['category']?.toString().trim() ?? '';
    final description = c['description']?.toString().trim() ?? '';
    final title = description.isNotEmpty
        ? description
        : (category.isNotEmpty ? category : 'Complaint');
    final room = c['node_name']?.toString().trim() ?? '';
    final created = _created(c);
    final subtitle = [
      if (room.isNotEmpty) room,
      if (created != null) _when.format(created),
    ].join(' · ');
    final (icon, iconColor) = _categoryIcon(category);
    final (label, color) = _statusBadge(c['status']?.toString() ?? '');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: HostelPgDashboardColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: HostelPgDashboardColors.textSecondary,
                        fontSize: 11.5,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded,
                color: HostelPgDashboardColors.textSecondary, size: 20),
          ],
        ),
      ),
    );
  }

  (IconData, Color) _categoryIcon(String category) {
    final c = category.toLowerCase();
    if (c.contains('electric')) {
      return (Icons.bolt_rounded, HostelPgDashboardColors.orange);
    }
    if (c.contains('plumb') || c.contains('water')) {
      return (Icons.water_drop_outlined, HostelPgDashboardColors.blue);
    }
    if (c.startsWith('ac') || c.contains('cool')) {
      return (Icons.ac_unit_rounded, HostelPgDashboardColors.cyan);
    }
    if (c.contains('furniture')) {
      return (Icons.chair_outlined, HostelPgDashboardColors.purple);
    }
    if (c.contains('clean')) {
      return (Icons.cleaning_services_outlined, HostelPgDashboardColors.green);
    }
    return (Icons.build_outlined, HostelPgDashboardColors.purple);
  }

  (String, Color) _statusBadge(String status) {
    switch (status) {
      case 'resolved':
        return ('Resolved', HostelPgDashboardColors.green);
      case 'closed':
        return ('Closed', HostelPgDashboardColors.textSecondary);
      case 'in_progress':
        return ('In Progress', const Color(0xFFD97706));
      case 'assigned':
        return ('Assigned', HostelPgDashboardColors.blue);
      default:
        return ('Open', HostelPgDashboardColors.red);
    }
  }
}
