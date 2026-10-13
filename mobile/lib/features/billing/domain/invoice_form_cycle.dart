// features/billing/domain/invoice_form_cycle.dart
//
// Server-computed billing period for Add Utilities
// (GET /billing/tenancies/:id/invoice-cycle). The backend picks the oldest
// unbilled stay on the property's calendar, so no month is skipped.

import 'package:intl/intl.dart';

class InvoicePeriod {
  final DateTime start;
  final DateTime end;
  const InvoicePeriod(this.start, this.end);
}

class InvoiceFormCycle {
  final DateTime periodStart;
  final DateTime periodEnd;
  final DateTime dueDate;
  final DateTime standardDueDate;
  final bool isLate;

  /// Completed stays with no invoice yet, oldest first.
  final List<InvoicePeriod> unbilled;

  /// Oldest unsent rent draft for this tenant, if any.
  final String? draftId;
  final InvoicePeriod? draftPeriod;

  const InvoiceFormCycle({
    required this.periodStart,
    required this.periodEnd,
    required this.dueDate,
    required this.standardDueDate,
    required this.isLate,
    this.unbilled = const [],
    this.draftId,
    this.draftPeriod,
  });

  /// Null when the response has no cycle (tenant without a move-in date).
  static InvoiceFormCycle? fromResponse(Map<String, dynamic> data) {
    final cycle = data['cycle'];
    if (cycle is! Map) return null;
    final start = parseYmd(cycle['periodStart']);
    final end = parseYmd(cycle['periodEnd']);
    final due = parseYmd(cycle['dueDate']);
    if (start == null || end == null || due == null) return null;

    final unbilled = <InvoicePeriod>[];
    final rawUnbilled = cycle['unbilled'];
    if (rawUnbilled is List) {
      for (final p in rawUnbilled.whereType<Map>()) {
        final s = parseYmd(p['periodStart']);
        final e = parseYmd(p['periodEnd']);
        if (s != null && e != null) unbilled.add(InvoicePeriod(s, e));
      }
    }

    final draft = data['draft'];
    String? draftId;
    InvoicePeriod? draftPeriod;
    if (draft is Map && draft['id'] != null) {
      draftId = draft['id'].toString();
      final s = parseYmd(draft['periodStart']);
      final e = parseYmd(draft['periodEnd']);
      if (s != null && e != null) draftPeriod = InvoicePeriod(s, e);
    }

    return InvoiceFormCycle(
      periodStart: start,
      periodEnd: end,
      dueDate: due,
      standardDueDate: parseYmd(cycle['standardDueDate']) ?? due,
      isLate: cycle['isLate'] == true,
      unbilled: unbilled,
      draftId: draftId,
      draftPeriod: draftPeriod,
    );
  }

  /// "2 months not yet billed (Aug, Sep). Billing the oldest first."
  String? get unbilledSummary {
    if (unbilled.length < 2) return null;
    final months = unbilled.map((p) => DateFormat('MMM').format(p.start)).join(', ');
    return '${unbilled.length} months not yet billed ($months). '
        'Billing the oldest first.';
  }

  /// Explains why the due date differs from the usual bill date + 5 days.
  String? get lateDueNote {
    if (!isLate) return null;
    final fmt = DateFormat('d MMM');
    return 'Billed late: due ${fmt.format(dueDate)} '
        '(usual date ${fmt.format(standardDueDate)} has passed).';
  }

  String? get draftNote {
    final p = draftPeriod;
    if (draftId == null || p == null) return null;
    final fmt = DateFormat('d MMM');
    return 'A draft for ${fmt.format(p.start)} – ${fmt.format(p.end)} '
        'is waiting for review.';
  }
}

/// Calendar date from 'YYYY-MM-DD' (no time zone shift).
DateTime? parseYmd(Object? raw) {
  final s = raw?.toString() ?? '';
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
  if (m == null) return null;
  return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}
