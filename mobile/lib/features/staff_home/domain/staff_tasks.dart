// features/staff_home/domain/staff_tasks.dart
//
// Which complaints a staff member should act on. The server already limits
// staff to complaints assigned to them or to nobody.

import '../../complaints/presentation/complaint_ui.dart';

const _activeStatuses = {'open', 'assigned', 'in_progress'};

bool isActiveComplaint(Map<String, dynamic> c) =>
    _activeStatuses.contains(complaintStatusOf(c));

bool isAssignedTo(Map<String, dynamic> c, String? userId) {
  if (userId == null || userId.isEmpty) return false;
  return c['assigned_to']?.toString() == userId;
}

bool isUnassigned(Map<String, dynamic> c) =>
    c.containsKey('assigned_to') &&
    (c['assigned_to']?.toString() ?? '').isEmpty;

int _priorityRank(Map<String, dynamic> c) {
  switch (c['priority']?.toString().toLowerCase()) {
    case 'high':
      return 0;
    case 'medium':
      return 1;
    case 'low':
      return 2;
    default:
      return 3;
  }
}

/// Active complaints: assigned to [userId] first, then unassigned, then
/// anything else the server returned; within each, high priority and newest first.
List<Map<String, dynamic>> staffTaskQueue(
  List<Map<String, dynamic>> complaints,
  String? userId,
) {
  int bucket(Map<String, dynamic> c) {
    if (isAssignedTo(c, userId)) return 0;
    if (isUnassigned(c)) return 1;
    return 2;
  }

  final active =
      sortComplaintsNewestFirst(complaints.where(isActiveComplaint).toList());
  final indexed = [for (var i = 0; i < active.length; i++) (i, active[i])];
  indexed.sort((a, b) {
    final byBucket = bucket(a.$2).compareTo(bucket(b.$2));
    if (byBucket != 0) return byBucket;
    final byPriority = _priorityRank(a.$2).compareTo(_priorityRank(b.$2));
    if (byPriority != 0) return byPriority;
    return a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

class StaffComplaintCounts {
  final int active;
  final int mine;
  const StaffComplaintCounts({required this.active, required this.mine});
}

StaffComplaintCounts staffComplaintCounts(
  List<Map<String, dynamic>> complaints,
  String? userId,
) {
  final active = complaints.where(isActiveComplaint).toList();
  return StaffComplaintCounts(
    active: active.length,
    mine: active.where((c) => isAssignedTo(c, userId)).length,
  );
}
