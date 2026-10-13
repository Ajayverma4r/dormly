import 'package:dormly/features/dashboard/domain/dashboard_financials.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses the financials response', () {
    final f = DashboardFinancials.fromJson(FinancialPeriod.thisMonth, {
      'period': 'this_month',
      'range': {'start': '2026-10-01', 'end_inclusive': '2026-10-13'},
      'collected': 6000,
      'expenses': '1500',
      'net_profit': 4500,
      'previous': {
        'range': {'start': '2026-09-01', 'end_inclusive': '2026-09-13'},
      },
      'change': {'collected_pct': 50, 'expenses_pct': null},
    });
    expect(f.collected, 6000);
    expect(f.expenses, 1500);
    expect(f.netProfit, 4500);
    expect(f.collectedChangePct, 50);
    expect(f.expensesChangePct, isNull);
    expect(f.rangeCaption, '1 Oct – 13 Oct · vs 1 Sep – 13 Sep');
  });

  test('range labels show the year only when it changes', () {
    final r = FinancialRange.fromJson(
      {'start': '2025-12-01', 'end_inclusive': '2026-01-13'},
    )!;
    expect(r.label, '1 Dec 2025 – 13 Jan 2026');
  });

  test('badges reflect the real change and hide without a comparison', () {
    expect(changeBadgeText(12), '↑ 12%');
    expect(changeBadgeText(-5), '↓ 5%');
    expect(changeBadgeText(0), '0%');
    expect(changeBadgeText(null), isNull);
  });

  test('periods use the backend values', () {
    expect(FinancialPeriod.values.map((p) => p.apiValue),
        ['this_month', 'last_month', 'last_3_months', 'this_year']);
  });
}
