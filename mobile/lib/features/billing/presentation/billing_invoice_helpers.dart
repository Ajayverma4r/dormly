// features/billing/presentation/billing_invoice_helpers.dart
import 'package:intl/intl.dart';

final billingCurrency =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

DateTime? invoiceMonthDate(Map<String, dynamic> inv) {
  for (final key in [
    'period_start',
    'periodStart',
    'period_end',
    'periodEnd',
    'due_date',
    'dueDate',
    'created_at',
    'createdAt',
  ]) {
    final raw = inv[key]?.toString().trim();
    if (raw == null || raw.isEmpty) continue;
    final match = RegExp(r'^(\d{4})-(\d{2})').firstMatch(raw);
    if (match != null) {
      final year = int.tryParse(match.group(1)!);
      final month = int.tryParse(match.group(2)!);
      if (year != null && month != null) return DateTime(year, month, 1);
    }
    final d = DateTime.tryParse(raw);
    if (d != null) {
      final local = d.toLocal();
      return DateTime(local.year, local.month, 1);
    }
  }
  return null;
}

bool invoiceMatchesMonth(Map<String, dynamic> inv, DateTime month) {
  final d = invoiceMonthDate(inv);
  if (d == null) return false;
  return d.year == month.year && d.month == month.month;
}

double invoiceTotalAmount(Map<String, dynamic> inv) =>
    double.tryParse(
      (inv['total_amount'] ?? inv['totalAmount'])?.toString() ?? '',
    ) ??
    0;

double invoicePaidAmount(Map<String, dynamic> inv) =>
    double.tryParse(
      (inv['paid_amount'] ?? inv['paidAmount'])?.toString() ?? '',
    ) ??
    0;

double invoiceRemaining(Map<String, dynamic> inv) =>
    (invoiceTotalAmount(inv) - invoicePaidAmount(inv))
        .clamp(0.0, double.infinity);

String invoiceStatus(Map<String, dynamic> inv) =>
    inv['status']?.toString().toLowerCase().trim() ?? 'pending';

bool isOpenUnpaidInvoice(Map<String, dynamic> inv) {
  final status = invoiceStatus(inv);
  if (!{'pending', 'overdue', 'partial', 'partially_paid'}.contains(status)) {
    return false;
  }
  return invoiceRemaining(inv) > 0.009;
}

String tenantDisplayName(Map<String, dynamic> inv) =>
    inv['full_name']?.toString() ??
    inv['fullName']?.toString() ??
    'Tenant';

String tenantRoomLabel(Map<String, dynamic> inv) {
  final room =
      inv['node_name']?.toString() ?? inv['nodeName']?.toString() ?? '—';
  final floor =
      inv['floor_name']?.toString() ?? inv['floorName']?.toString();
  if (floor != null && floor.trim().isNotEmpty) {
    final f = floor.trim();
    return f.toLowerCase().contains('floor')
        ? '$room · $f'
        : '$room · $f Floor';
  }
  return room;
}

String? tenantPhone(Map<String, dynamic> inv) =>
    (inv['phone'] ?? inv['mobile'] ?? inv['user_phone'])?.toString();

String? tenantPhotoUrl(Map<String, dynamic> inv) =>
    (inv['profile_photo_url'] ?? inv['profilePhotoUrl'])?.toString();

String initialsFromName(String name) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return '${parts.first[0]}${parts[1][0]}'.toUpperCase();
}

String? resolvePhotoUrl(String? raw, String baseUrl) {
  if (raw == null || raw.trim().isEmpty) return null;
  if (raw.startsWith('http')) return raw;
  return '$baseUrl$raw';
}

String periodLabel(Map<String, dynamic> inv) {
  final d = invoiceMonthDate(inv);
  if (d == null) return '—';
  return DateFormat('MMM yyyy').format(d);
}
