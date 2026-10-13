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

bool _hasOpenInvoice(Map<String, dynamic> r) => _flag(r, 'has_due', 'hasDue');

bool _flag(Map<String, dynamic> r, String snake, String camel) {
  final raw = r[snake] ?? r[camel];
  if (raw is bool) return raw;
  return raw?.toString().toLowerCase() == 'true';
}

/// Paid = no open invoice. Due = open invoice not yet past its due date.
/// Overdue = the backend's `has_overdue`, judged in the property's calendar
/// (the due day itself is Due). The device date is never used.
TenantPaymentStatus tenantPaymentStatus(Map<String, dynamic> r) {
  if (!_hasOpenInvoice(r)) return TenantPaymentStatus.paid;
  return _flag(r, 'has_overdue', 'hasOverdue')
      ? TenantPaymentStatus.overdue
      : TenantPaymentStatus.due;
}

bool matchesTenantFilters(
  Map<String, dynamic> r, {
  required HostelGuestFilter stay,
  required TenantPaymentFilter payment,
  required String query,
}) {
  switch (stay) {
    case HostelGuestFilter.all:
      break;
    case HostelGuestFilter.checkedOut:
      if (!isCheckedOutTenancy(r)) return false;
    case HostelGuestFilter.active:
      if (!isActiveTenancy(r)) return false;
      if (payment != TenantPaymentFilter.all) {
        final status = tenantPaymentStatus(r);
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
