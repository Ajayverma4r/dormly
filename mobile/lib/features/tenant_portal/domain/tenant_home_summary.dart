// features/tenant_portal/domain/tenant_home_summary.dart
//
// Pure view-model for the tenant Home tab: dues from sent invoices only and a
// merged recent-activity feed. No device-date overdue logic: the backend's
// property-local `is_overdue` flag decides.

import '../../billing/presentation/billing_invoice_helpers.dart';

enum TenantDuesStatus { noBills, paid, upcoming, partiallyPaid, overdue }

class TenantDuesSummary {
  /// Remaining balance across sent invoices (partial payments deducted).
  final double outstanding;

  /// Earliest due date among sent invoices that still have a balance.
  final DateTime? nextDueDate;

  /// Sent invoice with a balance and the earliest due date.
  final Map<String, dynamic>? nextInvoice;

  final int overdueCount;
  final double overdueAmount;
  final TenantDuesStatus status;

  /// Most recent sent invoice with any amount paid against it.
  final Map<String, dynamic>? lastPaidInvoice;

  const TenantDuesSummary({
    required this.outstanding,
    required this.nextDueDate,
    required this.nextInvoice,
    required this.overdueCount,
    required this.overdueAmount,
    required this.status,
    required this.lastPaidInvoice,
  });

  factory TenantDuesSummary.fromInvoices(
    Iterable<Map<String, dynamic>> invoices,
  ) {
    final sent = invoices.where((inv) => !isDraftInvoice(inv)).toList();
    final open = sent.where(isOpenUnpaidInvoice).toList();

    Map<String, dynamic>? next;
    DateTime? nextDue;
    for (final inv in open) {
      final due = invoiceDueDate(inv);
      if (next == null ||
          (due != null && (nextDue == null || due.isBefore(nextDue)))) {
        next = inv;
        nextDue = due;
      }
    }

    final overdue = open.where(isOverdueInvoice).toList();

    Map<String, dynamic>? lastPaid;
    DateTime? lastPaidKey;
    for (final inv in sent) {
      if (invoicePaidAmount(inv) <= 0.009) continue;
      final key = _invoiceSortDate(inv);
      if (lastPaid == null ||
          (key != null && (lastPaidKey == null || key.isAfter(lastPaidKey)))) {
        lastPaid = inv;
        lastPaidKey = key;
      }
    }

    final outstanding = outstandingTotal(sent);
    final TenantDuesStatus status;
    if (sent.isEmpty) {
      status = TenantDuesStatus.noBills;
    } else if (overdue.isNotEmpty) {
      status = TenantDuesStatus.overdue;
    } else if (open.isEmpty) {
      status = TenantDuesStatus.paid;
    } else if (next != null && invoicePaidAmount(next) > 0.009) {
      status = TenantDuesStatus.partiallyPaid;
    } else {
      status = TenantDuesStatus.upcoming;
    }

    return TenantDuesSummary(
      outstanding: outstanding,
      nextDueDate: nextDue,
      nextInvoice: next,
      overdueCount: overdue.length,
      overdueAmount: overdue.fold<double>(
        0,
        (sum, inv) => sum + invoiceRemaining(inv),
      ),
      status: status,
      lastPaidInvoice: lastPaid,
    );
  }
}

enum TenantActivityKind { payment, meterReading, request }

class TenantActivity {
  final TenantActivityKind kind;

  /// Ordering key. Payments use the bill's due date because the tenant API
  /// does not expose individual payment timestamps.
  final DateTime sortDate;

  /// True when [sortDate] is when the event actually happened.
  final bool hasExactDate;

  final Map<String, dynamic> source;

  const TenantActivity({
    required this.kind,
    required this.sortDate,
    required this.hasExactDate,
    required this.source,
  });
}

List<TenantActivity> buildTenantActivity({
  required Iterable<Map<String, dynamic>> invoices,
  required Iterable<Map<String, dynamic>> requests,
  required Iterable<Map<String, dynamic>> meterReadings,
  int limit = 5,
}) {
  final items = <TenantActivity>[];

  for (final inv in invoices) {
    if (isDraftInvoice(inv) || invoicePaidAmount(inv) <= 0.009) continue;
    final key = _invoiceSortDate(inv);
    if (key == null) continue;
    items.add(TenantActivity(
      kind: TenantActivityKind.payment,
      sortDate: key,
      hasExactDate: false,
      source: inv,
    ));
  }

  for (final r in requests) {
    final at = _timestamp(r['created_at'] ?? r['createdAt']);
    if (at == null) continue;
    items.add(TenantActivity(
      kind: TenantActivityKind.request,
      sortDate: at,
      hasExactDate: true,
      source: r,
    ));
  }

  for (final m in meterReadings) {
    final at = _timestamp(m['created_at'] ?? m['createdAt']);
    if (at == null) continue;
    items.add(TenantActivity(
      kind: TenantActivityKind.meterReading,
      sortDate: at,
      hasExactDate: true,
      source: m,
    ));
  }

  items.sort((a, b) => b.sortDate.compareTo(a.sortDate));
  return items.take(limit).toList();
}

DateTime? _invoiceSortDate(Map<String, dynamic> inv) =>
    invoiceDueDate(inv) ?? invoiceMonthDate(inv);

DateTime? _timestamp(Object? raw) {
  final s = raw?.toString().trim() ?? '';
  if (s.isEmpty) return null;
  return DateTime.tryParse(s)?.toLocal();
}
