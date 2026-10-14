// features/tenant_portal/domain/payment_history.dart
//
// Tenant payment history: stays, actual payment transactions and the
// statement filter. Dates are calendar days (no time-of-day, no zone shift).

DateTime? calendarDay(Object? raw) {
  final s = raw?.toString().trim() ?? '';
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
  if (m == null) return null;
  if (s.length > 10) {
    final parsed = DateTime.tryParse(s);
    if (parsed == null) return null;
    final local = parsed.toLocal();
    return DateTime(local.year, local.month, local.day);
  }
  return DateTime(
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
  );
}

String ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

double _num(Object? v) => double.tryParse(v?.toString() ?? '') ?? 0;

class TenantStay {
  final String tenancyId;
  final String propertyId;
  final String propertyName;
  final String? city;
  final String? nodeName;
  final String? parentNodeName;
  final String? levelKey;
  final DateTime? moveIn;
  final DateTime? moveOut;
  final bool isCurrent;

  const TenantStay({
    required this.tenancyId,
    required this.propertyId,
    required this.propertyName,
    this.city,
    this.nodeName,
    this.parentNodeName,
    this.levelKey,
    this.moveIn,
    this.moveOut,
    required this.isCurrent,
  });

  factory TenantStay.fromJson(Map<String, dynamic> j) => TenantStay(
        tenancyId: j['tenancy_id']?.toString() ?? '',
        propertyId: j['property_id']?.toString() ?? '',
        propertyName: j['property_name']?.toString() ?? 'Property',
        city: j['property_city']?.toString(),
        nodeName: j['node_name']?.toString(),
        parentNodeName: j['parent_node_name']?.toString(),
        levelKey: j['node_level_key']?.toString(),
        moveIn: calendarDay(j['move_in_at']),
        moveOut: calendarDay(j['move_out_at']),
        isCurrent: j['is_current'] == true,
      );

  /// e.g. "Room 101 · Bed 1"; null when the unit is unknown.
  String? get unitLabel {
    final node = nodeName?.trim();
    final parent = parentNodeName?.trim();
    if (node == null || node.isEmpty) return null;
    if (parent != null && parent.isNotEmpty) return '$parent · $node';
    return node;
  }
}

/// One property option for the filter; several stays can share a property.
class StayProperty {
  final String propertyId;
  final String name;
  final bool isCurrent;

  const StayProperty(this.propertyId, this.name, this.isCurrent);
}

List<StayProperty> stayProperties(List<TenantStay> stays) {
  final byId = <String, StayProperty>{};
  for (final s in stays) {
    final prev = byId[s.propertyId];
    byId[s.propertyId] = StayProperty(
      s.propertyId,
      s.propertyName,
      s.isCurrent || (prev?.isCurrent ?? false),
    );
  }
  final list = byId.values.toList()
    ..sort((a, b) => a.isCurrent == b.isCurrent ? 0 : (a.isCurrent ? -1 : 1));
  return list;
}

class StatementPayment {
  final String id;
  final double amount;
  final String? method;
  final DateTime paidAt;

  /// Property-local calendar day the payment was recorded.
  final DateTime paidOn;
  final String invoiceId;
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final double invoiceTotal;
  final double invoiceBalance;
  final String propertyId;
  final String propertyName;

  const StatementPayment({
    required this.id,
    required this.amount,
    required this.method,
    required this.paidAt,
    required this.paidOn,
    required this.invoiceId,
    required this.periodStart,
    required this.periodEnd,
    required this.invoiceTotal,
    required this.invoiceBalance,
    required this.propertyId,
    required this.propertyName,
  });

  factory StatementPayment.fromJson(Map<String, dynamic> j) {
    final paidAt =
        DateTime.tryParse(j['paid_at']?.toString() ?? '')?.toLocal() ??
            DateTime.fromMillisecondsSinceEpoch(0);
    return StatementPayment(
      id: j['id']?.toString() ?? '',
      amount: _num(j['amount']),
      method: j['method']?.toString(),
      paidAt: paidAt,
      paidOn: calendarDay(j['paid_on']) ??
          DateTime(paidAt.year, paidAt.month, paidAt.day),
      invoiceId: j['invoice_id']?.toString() ?? '',
      periodStart: calendarDay(j['period_start']),
      periodEnd: calendarDay(j['period_end']),
      invoiceTotal: _num(j['invoice_total']),
      invoiceBalance: _num(j['invoice_balance']),
      propertyId: j['property_id']?.toString() ?? '',
      propertyName: j['property_name']?.toString() ?? 'Property',
    );
  }

  bool get invoiceFullyPaid => invoiceBalance <= 0.009;

  String get methodLabel {
    final m = (method ?? '').replaceAll('_', ' ').trim();
    if (m.isEmpty) return '—';
    return m.length <= 4
        ? m.toUpperCase()
        : '${m[0].toUpperCase()}${m.substring(1)}';
  }
}

class PaymentHistory {
  final double totalReceived;
  final int paymentCount;
  final int invoiceCount;

  /// Owed today in the property scope; not limited to the date range.
  final double currentOutstanding;
  final List<StatementPayment> payments;

  const PaymentHistory({
    required this.totalReceived,
    required this.paymentCount,
    required this.invoiceCount,
    required this.currentOutstanding,
    required this.payments,
  });

  factory PaymentHistory.fromJson(Map<String, dynamic> j) {
    final s = Map<String, dynamic>.from(j['summary'] as Map? ?? const {});
    final rows = (j['payments'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => StatementPayment.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return PaymentHistory(
      totalReceived: _num(s['total_received']),
      paymentCount: (s['payment_count'] as num?)?.toInt() ?? rows.length,
      invoiceCount: (s['invoice_count'] as num?)?.toInt() ?? 0,
      currentOutstanding: _num(s['current_outstanding']),
      payments: rows,
    );
  }
}

class StatementFilter {
  final String? propertyId;
  final DateTime? from;
  final DateTime? to;

  const StatementFilter({this.propertyId, this.from, this.to});

  static const all = StatementFilter();

  bool get isDefault => propertyId == null && from == null && to == null;

  /// User-facing problem with the range, or null when it can be applied.
  String? get validationError {
    if (from != null && to != null && from!.isAfter(to!)) {
      return 'From date must be on or before the To date.';
    }
    return null;
  }

  Map<String, String> toQuery() => {
        if (propertyId != null) 'propertyId': propertyId!,
        if (from != null) 'from': ymd(from!),
        if (to != null) 'to': ymd(to!),
      };

  StatementFilter copyWith({
    String? Function()? propertyId,
    DateTime? Function()? from,
    DateTime? Function()? to,
  }) =>
      StatementFilter(
        propertyId: propertyId == null ? this.propertyId : propertyId(),
        from: from == null ? this.from : from(),
        to: to == null ? this.to : to(),
      );

  @override
  bool operator ==(Object other) =>
      other is StatementFilter &&
      other.propertyId == propertyId &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(propertyId, from, to);
}
