// features/dashboard/domain/dashboard_financials.dart
import 'package:intl/intl.dart';

enum FinancialPeriod {
  thisMonth('this_month', 'This Month'),
  lastMonth('last_month', 'Last Month'),
  last3Months('last_3_months', 'Last 3 Months'),
  thisYear('this_year', 'This Year');

  const FinancialPeriod(this.apiValue, this.label);
  final String apiValue;
  final String label;
}

class FinancialRange {
  final DateTime start;
  final DateTime endInclusive;

  const FinancialRange(this.start, this.endInclusive);

  static FinancialRange? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final start = DateTime.tryParse(raw['start']?.toString() ?? '');
    final end = DateTime.tryParse(raw['end_inclusive']?.toString() ?? '');
    if (start == null || end == null) return null;
    return FinancialRange(start, end);
  }

  /// "1 Oct – 13 Oct", or "1 Dec 2025 – 13 Jan 2026" across years.
  String get label {
    final sameYear = start.year == endInclusive.year;
    final fmt = DateFormat(sameYear ? 'd MMM' : 'd MMM yyyy');
    if (start == endInclusive) return fmt.format(start);
    return '${fmt.format(start)} – ${fmt.format(endInclusive)}';
  }
}

class DashboardFinancials {
  final FinancialPeriod period;
  final FinancialRange? range;
  final FinancialRange? previousRange;
  final double collected;
  final double expenses;
  final double netProfit;
  final int? collectedChangePct;
  final int? expensesChangePct;

  const DashboardFinancials({
    required this.period,
    required this.collected,
    required this.expenses,
    required this.netProfit,
    this.range,
    this.previousRange,
    this.collectedChangePct,
    this.expensesChangePct,
  });

  factory DashboardFinancials.fromJson(
    FinancialPeriod period,
    Map<String, dynamic> json,
  ) {
    final previous = json['previous'];
    final change = json['change'];
    return DashboardFinancials(
      period: period,
      range: FinancialRange.fromJson(json['range']),
      previousRange:
          previous is Map ? FinancialRange.fromJson(previous['range']) : null,
      collected: _asDouble(json['collected']),
      expenses: _asDouble(json['expenses']),
      netProfit: _asDouble(json['net_profit']),
      collectedChangePct: change is Map ? _asIntOrNull(change['collected_pct']) : null,
      expensesChangePct: change is Map ? _asIntOrNull(change['expenses_pct']) : null,
    );
  }

  /// Caption under the section title, e.g. "1 Oct – 13 Oct · vs 1 Sep – 13 Sep".
  String? get rangeCaption {
    final r = range;
    if (r == null) return null;
    final p = previousRange;
    return p == null ? r.label : '${r.label} · vs ${p.label}';
  }
}

/// "↑ 12%", "↓ 5%", "0%", or null when there is no previous figure.
String? changeBadgeText(int? pct) {
  if (pct == null) return null;
  if (pct > 0) return '↑ $pct%';
  if (pct < 0) return '↓ ${pct.abs()}%';
  return '0%';
}

double _asDouble(Object? v) =>
    v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;

int? _asIntOrNull(Object? v) {
  if (v == null) return null;
  if (v is num) return v.round();
  return int.tryParse(v.toString());
}
