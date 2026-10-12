// features/tenancies/domain/tenant_filters.dart
//
// Tenants list filtering. Stay status (active / checked-out) and payment
// status (paid / due / overdue) are independent; payment applies inside Active.

/// Stay status filter.
enum HostelGuestFilter { all, active, checkedOut }

/// Payment status filter — only applies inside Active.
enum TenantPaymentFilter { all, paid, due, overdue }

enum TenantPaymentStatus { paid, due, overdue }

bool isActiveTenancy(Map<String, dynamic> r) =>
    r['status']?.toString() == 'active';

bool isCheckedOutTenancy(Map<String, dynamic> r) =>
    r['status']?.toString() == 'ended';

bool _hasOpenInvoice(Map<String, dynamic> r) {
  final raw = r['has_due'] ?? r['hasDue'];
  if (raw is bool) return raw;
  return raw?.toString().toLowerCase() == 'true';
}

/// Paid = no open invoice. Due = open invoice not yet past its due date.
/// Overdue = an open invoice whose due date has passed (due day itself is Due).
TenantPaymentStatus tenantPaymentStatus(
  Map<String, dynamic> r, {
  DateTime? today,
}) {
  if (!_hasOpenInvoice(r)) return TenantPaymentStatus.paid;
  final raw =
      (r['earliest_open_due_date'] ?? r['earliestOpenDueDate'])?.toString();
  if (raw == null || raw.length < 10) return TenantPaymentStatus.due;
  final due = DateTime.tryParse(raw.substring(0, 10));
  if (due == null) return TenantPaymentStatus.due;
  final now = today ?? DateTime.now();
  final todayDate = DateTime(now.year, now.month, now.day);
  return due.isBefore(todayDate)
      ? TenantPaymentStatus.overdue
      : TenantPaymentStatus.due;
}

bool matchesTenantFilters(
  Map<String, dynamic> r, {
  required HostelGuestFilter stay,
  required TenantPaymentFilter payment,
  required String query,
  DateTime? today,
}) {
  switch (stay) {
    case HostelGuestFilter.all:
      break;
    case HostelGuestFilter.checkedOut:
      if (!isCheckedOutTenancy(r)) return false;
    case HostelGuestFilter.active:
      if (!isActiveTenancy(r)) return false;
      if (payment != TenantPaymentFilter.all) {
        final status = tenantPaymentStatus(r, today: today);
        final wanted = switch (payment) {
          TenantPaymentFilter.paid => TenantPaymentStatus.paid,
          TenantPaymentFilter.due => TenantPaymentStatus.due,
          _ => TenantPaymentStatus.overdue,
        };
        if (status != wanted) return false;
      }
  }
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  final name =
      (r['full_name'] ?? r['user_name'] ?? '').toString().toLowerCase();
  final room = (r['node_name'] ?? '').toString().toLowerCase();
  final floor =
      (r['floor_name'] ?? r['floorName'] ?? '').toString().toLowerCase();
  final phone = (r['phone'] ?? '').toString().toLowerCase();
  final digits = q.replaceAll(RegExp(r'\D'), '');
  return name.contains(q) ||
      room.contains(q) ||
      floor.contains(q) ||
      phone.contains(q) ||
      (digits.length >= 3 &&
          phone.replaceAll(RegExp(r'\D'), '').contains(digits));
}
