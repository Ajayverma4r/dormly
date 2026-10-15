// features/complaints/presentation/complaint_ui.dart
//
// Shared look, labels and providers for the complaints list and details
// screens. Light palette with the Dormly purple accent.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/network/api_config.dart';
import '../../auth/data/auth_repository.dart';
import '../data/complaints_repository.dart';

class ComplaintColors {
  static const brand = Color(0xFF7C3AED);
  static const brandSoft = Color(0xFFF3E8FF);
  static const bg = Color(0xFFF6F7FB);
  static const card = Colors.white;
  static const border = Color(0xFFE6E8EF);
  static const ink = Color(0xFF111827);
  static const muted = Color(0xFF6B7280);
}

/// Statuses the backend accepts, in workflow order.
const complaintStatuses = [
  'open',
  'assigned',
  'in_progress',
  'resolved',
  'closed'
];

/// Roles the backend lets update a complaint (PATCH is owner/admin/manager/staff).
const _complaintEditorRoles = {'owner', 'admin', 'manager', 'staff'};

bool canEditComplaints(String? role) => _complaintEditorRoles.contains(role);

/// Roles the backend lets assign a complaint (PUT …/assignment).
const _complaintAssignerRoles = {'owner', 'admin', 'manager'};

bool canAssignComplaints(String? role) =>
    _complaintAssignerRoles.contains(role);

final complaintViewerRoleProvider = FutureProvider.autoDispose<String?>(
  (ref) => ref.watch(authRepositoryProvider).getContextRole(),
);

final complaintViewerUserIdProvider = FutureProvider.autoDispose<String?>(
  (ref) => ref.watch(authRepositoryProvider).getUserId(),
);

/// Whether this team member may update or comment on [complaint]. Staff are
/// limited to complaints assigned to them once the server reports assignment.
bool canActOnComplaint(
    String? role, String? userId, Map<String, dynamic> complaint) {
  if (!canEditComplaints(role)) return false;
  if (role != 'staff' || !complaint.containsKey('assigned_to')) return true;
  final assignee = complaint['assigned_to']?.toString();
  return assignee != null && assignee.isNotEmpty && assignee == userId;
}

/// "Assigned to you" / "Unassigned" / "Assigned to {name}" and whether it is
/// the viewer's. Null when the server does not report assignment yet.
(String, bool)? complaintAssignmentLabel(
    Map<String, dynamic> complaint, String? viewerId) {
  if (!complaint.containsKey('assigned_to')) return null;
  final assignee = complaint['assigned_to']?.toString() ?? '';
  if (assignee.isEmpty) return ('Unassigned', false);
  if (viewerId != null && viewerId.isNotEmpty && assignee == viewerId) {
    return ('Assigned to you', true);
  }
  final name = complaint['assignee_name']?.toString().trim() ?? '';
  return (name.isEmpty ? 'Assigned' : 'Assigned to $name', false);
}

/// Comments and activity for (propertyId, complaintId). Null when the server
/// does not offer comments yet (503) or this viewer may not read them.
final complaintCommentsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>?, (String, String)>((ref, key) async {
  try {
    return await ref
        .watch(complaintsRepositoryProvider)
        .listComments(key.$1, key.$2);
  } on DioException catch (e) {
    final status = e.response?.statusCode;
    if (status == 503 || status == 403 || status == 404) return null;
    rethrow;
  }
});

final complaintAssigneesProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, propertyId) =>
      ref.watch(complaintsRepositoryProvider).listAssignees(propertyId),
);

String complaintRoleLabel(String? role) {
  final r = role?.trim() ?? '';
  if (r.isEmpty) return '';
  return '${r[0].toUpperCase()}${r.substring(1)}';
}

class ComplaintProperty {
  final String name;
  final String address;
  const ComplaintProperty(this.name, this.address);
}

/// Name and address from [source], only when it describes [propertyId].
ComplaintProperty? complaintPropertyFrom(
  Map<String, dynamic>? source,
  String? propertyId, {
  String idKey = 'id',
  String nameKey = 'name',
  String addressKey = 'address',
  String cityKey = 'city',
}) {
  if (source == null || propertyId == null || propertyId.isEmpty) return null;
  if (source[idKey]?.toString() != propertyId) return null;
  final name = source[nameKey]?.toString().trim() ?? '';
  final address = [
    source[addressKey]?.toString().trim() ?? '',
    source[cityKey]?.toString().trim() ?? '',
  ].where((s) => s.isNotEmpty).join(', ');
  if (name.isEmpty && address.isEmpty) return null;
  return ComplaintProperty(name, address);
}

final _day = DateFormat('d MMM yyyy');
final _dayTime = DateFormat('d MMM yyyy, h:mm a');

DateTime? complaintCreatedAt(Map<String, dynamic> c) =>
    DateTime.tryParse(c['created_at']?.toString() ?? '')?.toLocal();

DateTime? complaintUpdatedAt(Map<String, dynamic> c) =>
    DateTime.tryParse(c['updated_at']?.toString() ?? '')?.toLocal();

String formatComplaintDay(DateTime d) => _day.format(d);
String formatComplaintDayTime(DateTime d) => _dayTime.format(d);

String complaintStatusOf(Map<String, dynamic> c) =>
    (c['status']?.toString().trim().toLowerCase() ?? '').isEmpty
        ? 'open'
        : c['status'].toString().trim().toLowerCase();

String complaintCategoryOf(Map<String, dynamic> c) =>
    c['category']?.toString().trim() ?? '';

String complaintDescriptionOf(Map<String, dynamic> c) =>
    c['description']?.toString().trim() ?? '';

String complaintRoomOf(Map<String, dynamic> c) =>
    c['node_name']?.toString().trim() ?? '';

/// Description first, then category, so every row has a readable title.
String complaintTitle(Map<String, dynamic> c) {
  final description = complaintDescriptionOf(c);
  if (description.isNotEmpty) return description;
  final category = complaintCategoryOf(c);
  return category.isNotEmpty ? category : 'Complaint';
}

/// Newest first by submission time; rows without a date go last.
List<Map<String, dynamic>> sortComplaintsNewestFirst(
  List<Map<String, dynamic>> all,
) {
  return [...all]..sort((a, b) {
      final da = complaintCreatedAt(a);
      final db = complaintCreatedAt(b);
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });
}

/// Per-status counts plus `all`, from the complaints the caller was given.
Map<String, int> complaintStatusCounts(List<Map<String, dynamic>> all) {
  final counts = <String, int>{'all': all.length};
  for (final c in all) {
    final s = complaintStatusOf(c);
    counts[s] = (counts[s] ?? 0) + 1;
  }
  return counts;
}

class ComplaintStatusStyle {
  final String label;
  final Color fg;
  final Color bg;
  final IconData icon;
  const ComplaintStatusStyle(this.label, this.fg, this.bg, this.icon);
}

ComplaintStatusStyle complaintStatusStyle(String status) {
  switch (status) {
    case 'open':
      return const ComplaintStatusStyle('Open', Color(0xFFDC2626),
          Color(0xFFFEE2E2), Icons.error_outline_rounded);
    case 'assigned':
      return const ComplaintStatusStyle('Assigned', Color(0xFF2563EB),
          Color(0xFFDBEAFE), Icons.person_outline_rounded);
    case 'in_progress':
      return const ComplaintStatusStyle('In Progress', Color(0xFFD97706),
          Color(0xFFFEF3C7), Icons.autorenew_rounded);
    case 'resolved':
      return const ComplaintStatusStyle('Resolved', Color(0xFF16A34A),
          Color(0xFFDCFCE7), Icons.check_circle_outline_rounded);
    case 'closed':
      return const ComplaintStatusStyle('Closed', Color(0xFF6B7280),
          Color(0xFFF1F5F9), Icons.lock_outline_rounded);
    default:
      final label = status.isEmpty
          ? 'Unknown'
          : '${status[0].toUpperCase()}${status.substring(1).replaceAll('_', ' ')}';
      return ComplaintStatusStyle(label, const Color(0xFF6B7280),
          const Color(0xFFF1F5F9), Icons.help_outline_rounded);
  }
}

class ComplaintCategoryStyle {
  final IconData icon;
  final Color fg;
  final Color bg;
  const ComplaintCategoryStyle(this.icon, this.fg, this.bg);
}

ComplaintCategoryStyle complaintCategoryStyle(String category) {
  final c = category.toLowerCase();
  if (c.contains('electric')) {
    return const ComplaintCategoryStyle(
        Icons.bolt_rounded, Color(0xFFEA580C), Color(0xFFFFEDD5));
  }
  if (c.contains('plumb') || c.contains('water')) {
    return const ComplaintCategoryStyle(
        Icons.water_drop_outlined, Color(0xFF2563EB), Color(0xFFDBEAFE));
  }
  if (c.startsWith('ac') || c.contains('cool')) {
    return const ComplaintCategoryStyle(
        Icons.ac_unit_rounded, Color(0xFF0891B2), Color(0xFFCFFAFE));
  }
  if (c.contains('furniture')) {
    return const ComplaintCategoryStyle(
        Icons.chair_outlined, Color(0xFF7C3AED), Color(0xFFF3E8FF));
  }
  if (c.contains('clean')) {
    return const ComplaintCategoryStyle(
        Icons.cleaning_services_outlined, Color(0xFF16A34A), Color(0xFFDCFCE7));
  }
  return const ComplaintCategoryStyle(
      Icons.build_outlined, Color(0xFF7C3AED), Color(0xFFF3E8FF));
}

(String, Color)? complaintPriorityStyle(String? priority) {
  switch (priority?.toLowerCase()) {
    case 'low':
      return ('Low', const Color(0xFF16A34A));
    case 'medium':
      return ('Medium', const Color(0xFFD97706));
    case 'high':
      return ('High', const Color(0xFFDC2626));
    default:
      return null;
  }
}

/// Absolute URLs for the complaint's uploaded photos.
List<String> complaintPhotoUrls(Map<String, dynamic> c) {
  final raw = c['photo_urls'] ?? c['photoUrls'];
  if (raw is! List) return const [];
  final base = resolveApiBaseUrl();
  return [
    for (final p in raw)
      if ((p?.toString().trim() ?? '').isNotEmpty)
        p.toString().trim().startsWith('http')
            ? p.toString().trim()
            : '$base${p.toString().trim()}',
  ];
}

/// User-facing message for a failed complaints request; never raw server text.
String complaintErrorMessage(Object error, {bool saving = false}) {
  if (error is DioException) {
    final status = error.response?.statusCode;
    if (status == 401) return 'Your session has expired. Please sign in again.';
    if (status == 403) {
      return saving
          ? "You don't have permission to update this complaint."
          : "You don't have access to these complaints.";
    }
    if (status == 404) return 'This complaint could not be found.';
    if (status == null) {
      return 'Could not reach the server. Check your connection and try again.';
    }
  }
  return saving
      ? "Couldn't update this complaint. Please try again."
      : "Couldn't load complaints right now. Please try again.";
}

class ComplaintStatusBadge extends StatelessWidget {
  final String status;
  final bool withIcon;

  const ComplaintStatusBadge(
      {super.key, required this.status, this.withIcon = false});

  @override
  Widget build(BuildContext context) {
    final style = complaintStatusStyle(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: style.bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (withIcon) ...[
            Icon(style.icon, size: 13, color: style.fg),
            const SizedBox(width: 4),
          ],
          Text(
            style.label,
            style: TextStyle(
              color: style.fg,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class ComplaintCategoryIcon extends StatelessWidget {
  final String category;
  final double size;

  const ComplaintCategoryIcon(
      {super.key, required this.category, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final style = complaintCategoryStyle(category);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: style.bg, shape: BoxShape.circle),
      child: Icon(style.icon, color: style.fg, size: size * 0.5),
    );
  }
}
