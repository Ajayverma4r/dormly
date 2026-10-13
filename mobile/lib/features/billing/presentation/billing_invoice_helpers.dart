// features/billing/presentation/billing_invoice_helpers.dart
import 'package:intl/intl.dart';

final billingCurrency =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// Calendar day of a date field from the API (no time-of-day).
///
/// Accepts 'YYYY-MM-DD' or a timestamp. The API serialises SQL DATE columns
/// as the server's local midnight, so 1 Sep arrives as
/// '2026-08-31T18:30:00.000Z' from a server in India: never take the first 10
/// characters. An exact UTC midnight (server in UTC) keeps its calendar day;
/// any other timestamp is read in the device zone.
DateTime? invoiceCalendarDate(Object? raw) {
  final s = raw?.toString().trim() ?? '';
  if (s.isEmpty) return null;
  final dateOnly = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
  if (dateOnly != null) {
    return DateTime(
      int.parse(dateOnly.group(1)!),
      int.parse(dateOnly.group(2)!),
      int.parse(dateOnly.group(3)!),
    );
  }
  final parsed = DateTime.tryParse(s);
  if (parsed == null) return null;
  final d = parsed.isUtc &&
          parsed.hour == 0 &&
          parsed.minute == 0 &&
          parsed.second == 0 &&
          parsed.millisecond == 0
      ? parsed
      : parsed.toLocal();
  return DateTime(d.year, d.month, d.day);
}

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
    final d = invoiceCalendarDate(inv[key]);
    if (d != null) return DateTime(d.year, d.month, 1);
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

/// Auto-generated invoice awaiting owner review; the tenant cannot see it yet.
/// Older API responses without `sent_at` are treated as already sent.
bool isDraftInvoice(Map<String, dynamic> inv) =>
    inv.containsKey('sent_at') && inv['sent_at'] == null;

/// Sent to the tenant with a balance still owed — the same rule the backend
/// uses for dues, `has_due` and dashboard pending totals. Drafts never count.
bool isOpenUnpaidInvoice(Map<String, dynamic> inv) =>
    !isDraftInvoice(inv) && invoiceRemaining(inv) > 0.009;

/// Calendar due date of the invoice (date only, no time-of-day).
DateTime? invoiceDueDate(Map<String, dynamic> inv) =>
    invoiceCalendarDate(inv['due_date'] ?? inv['dueDate']);

/// Outstanding and past due in the property's calendar, partially paid
/// included. Uses the backend's derived `is_overdue`; older responses without
/// it fall back to the stored `overdue` status. Never uses the device date.
bool isOverdueInvoice(Map<String, dynamic> inv) {
  if (!isOpenUnpaidInvoice(inv)) return false;
  final flag = inv['is_overdue'] ?? inv['isOverdue'];
  if (flag is bool) return flag;
  if (flag != null) return flag.toString().toLowerCase() == 'true';
  return invoiceStatus(inv) == 'overdue';
}

/// Sum of remaining balances on sent invoices; drafts and paid excluded.
double outstandingTotal(Iterable<Map<String, dynamic>> invoices) =>
    invoices.where(isOpenUnpaidInvoice).fold<double>(
          0,
          (sum, inv) => sum + invoiceRemaining(inv),
        );

/// Unsent drafts' amounts — billed but not yet owed by the tenant.
double draftTotal(Iterable<Map<String, dynamic>> invoices) =>
    invoices.where(isDraftInvoice).fold<double>(
          0,
          (sum, inv) => sum + invoiceRemaining(inv),
        );

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
