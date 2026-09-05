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

// ── Indian Financial Year (1 Apr → 31 Mar) ──────────────────────────────

class FinancialYear {
  /// Calendar year of 1 April that starts this FY (e.g. 2025 for FY 2025-26).
  final int startYear;

  const FinancialYear(this.startYear);

  factory FinancialYear.current([DateTime? now]) {
    final n = now ?? DateTime.now();
    return FinancialYear(n.month >= 4 ? n.year : n.year - 1);
  }

  /// Recent FYs newest-first (includes current).
  static List<FinancialYear> recent({int count = 6, DateTime? now}) {
    final current = FinancialYear.current(now);
    return List.generate(count, (i) => FinancialYear(current.startYear - i));
  }

  String get label {
    final endShort = (startYear + 1) % 100;
    return 'FY $startYear-${endShort.toString().padLeft(2, '0')}';
  }

  DateTime get start => DateTime(startYear, 4, 1);

  /// Exclusive end: 1 Apr of next year.
  DateTime get endExclusive => DateTime(startYear + 1, 4, 1);

  /// Apr → Mar month anchors for this FY.
  List<DateTime> get months {
    return List.generate(12, (i) {
      final m = 4 + i; // 4..15
      if (m <= 12) return DateTime(startYear, m, 1);
      return DateTime(startYear + 1, m - 12, 1);
    });
  }

  bool containsDate(DateTime d) {
    final local = DateTime(d.year, d.month, d.day);
    return !local.isBefore(start) && local.isBefore(endExclusive);
  }

  @override
  bool operator ==(Object other) =>
      other is FinancialYear && other.startYear == startYear;

  @override
  int get hashCode => startYear.hashCode;
}

DateTime? parsePaymentDate(Map<String, dynamic> payment) {
  for (final key in ['paid_at', 'paidAt', 'created_at', 'createdAt']) {
    final raw = payment[key]?.toString().trim();
    if (raw == null || raw.isEmpty) continue;
    final d = DateTime.tryParse(raw);
    if (d != null) return d.toLocal();
  }
  return null;
}

double paymentAmount(Map<String, dynamic> payment) =>
    double.tryParse(
      (payment['amount'] ?? payment['paid_amount'] ?? payment['paidAmount'])
              ?.toString() ??
          '',
    ) ??
    0;

/// One receipt row for the CA month accordion.
class CaPaymentEntry {
  final String id;
  final String? invoiceId;
  final String tenantName;
  final String roomLabel;
  final double amount;
  final DateTime paidAt;

  const CaPaymentEntry({
    required this.id,
    required this.invoiceId,
    required this.tenantName,
    required this.roomLabel,
    required this.amount,
    required this.paidAt,
  });
}

/// Payments collected in a single calendar month within an FY.
class CaMonthGroup {
  final DateTime month;
  final List<CaPaymentEntry> payments;

  const CaMonthGroup({required this.month, required this.payments});

  String get title => DateFormat('MMMM yyyy').format(month);

  double get totalCollected =>
      payments.fold<double>(0, (s, p) => s + p.amount);
}

/// Build Apr→Mar groups that contain at least one payment in [fy].
List<CaMonthGroup> groupPaymentsByMonthForFy(
  List<CaPaymentEntry> entries,
  FinancialYear fy,
) {
  final byKey = <String, List<CaPaymentEntry>>{};
  for (final e in entries) {
    if (!fy.containsDate(e.paidAt)) continue;
    final key =
        '${e.paidAt.year}-${e.paidAt.month.toString().padLeft(2, '0')}';
    byKey.putIfAbsent(key, () => []).add(e);
  }

  final groups = <CaMonthGroup>[];
  for (final month in fy.months) {
    final key =
        '${month.year}-${month.month.toString().padLeft(2, '0')}';
    final list = byKey[key];
    if (list == null || list.isEmpty) continue;
    list.sort((a, b) => b.paidAt.compareTo(a.paidAt));
    groups.add(CaMonthGroup(month: month, payments: list));
  }
  return groups;
}

CaPaymentEntry? caPaymentFromApiRow(Map<String, dynamic> row) {
  final paidAt = parsePaymentDate(row);
  if (paidAt == null) return null;
  final amount = paymentAmount(row);
  if (amount <= 0) return null;
  return CaPaymentEntry(
    id: (row['id'] ?? '${row['invoice_id']}-$paidAt').toString(),
    invoiceId: (row['invoice_id'] ?? row['invoiceId'])?.toString(),
    tenantName: tenantDisplayName(row),
    roomLabel: tenantRoomLabel(row),
    amount: amount,
    paidAt: paidAt,
  );
}

/// Fallback when `/payments` is empty/unavailable: one synthetic receipt per
/// partially/fully paid invoice, dated on billing period start.
List<CaPaymentEntry> synthesizePaymentsFromInvoices(
  List<Map<String, dynamic>> invoices,
) {
  final out = <CaPaymentEntry>[];
  for (final inv in invoices) {
    final paid = invoicePaidAmount(inv);
    if (paid <= 0.009) continue;
    final month = invoiceMonthDate(inv);
    if (month == null) continue;
    final id = (inv['id'] ?? inv['invoice_id'])?.toString() ?? '';
    out.add(
      CaPaymentEntry(
        id: 'synth-$id',
        invoiceId: id.isEmpty ? null : id,
        tenantName: tenantDisplayName(inv),
        roomLabel: tenantRoomLabel(inv),
        amount: paid,
        paidAt: month,
      ),
    );
  }
  return out;
}

bool invoiceInFinancialYear(Map<String, dynamic> inv, FinancialYear fy) {
  final d = invoiceMonthDate(inv);
  if (d == null) return false;
  return fy.containsDate(d);
}
