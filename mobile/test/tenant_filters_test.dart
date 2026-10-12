import 'package:dormly/features/tenancies/domain/tenant_filters.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _t(
  String name, {
  String status = 'active',
  bool hasDue = false,
  String? due,
  String room = 'G01',
  String phone = '9000456700',
}) =>
    {
      'full_name': name,
      'status': status,
      'has_due': hasDue,
      'earliest_open_due_date': due,
      'node_name': room,
      'phone': phone,
    };

void main() {
  final today = DateTime(2026, 10, 10);

  final residents = [
    _t('paid'),
    _t('due', hasDue: true, due: '2026-10-12'),
    _t('dueToday', hasDue: true, due: '2026-10-10'),
    _t('overdue', hasDue: true, due: '2026-10-05', room: 'G05'),
    _t('outWithDues', status: 'ended', hasDue: true, due: '2026-09-05'),
    _t('outClean', status: 'ended'),
  ];

  List<String> names(
    HostelGuestFilter stay, {
    TenantPaymentFilter payment = TenantPaymentFilter.all,
    String query = '',
  }) =>
      residents
          .where((r) => matchesTenantFilters(
                r,
                stay: stay,
                payment: payment,
                query: query,
                today: today,
              ))
          .map((r) => r['full_name'] as String)
          .toList();

  test('All shows every tenancy', () {
    expect(names(HostelGuestFilter.all), hasLength(residents.length));
  });

  test('Active includes paid, due and overdue tenants', () {
    expect(names(HostelGuestFilter.active),
        ['paid', 'due', 'dueToday', 'overdue']);
  });

  test('Checked-out never leaks into Active, even with dues', () {
    expect(names(HostelGuestFilter.checkedOut), ['outWithDues', 'outClean']);
    expect(names(HostelGuestFilter.active), isNot(contains('outWithDues')));
  });

  test('payment sub-filters partition Active', () {
    expect(names(HostelGuestFilter.active, payment: TenantPaymentFilter.paid),
        ['paid']);
    expect(names(HostelGuestFilter.active, payment: TenantPaymentFilter.due),
        ['due', 'dueToday']);
    expect(
        names(HostelGuestFilter.active, payment: TenantPaymentFilter.overdue),
        ['overdue']);
  });

  test('due day itself is Due, day after is Overdue', () {
    final r = _t('x', hasDue: true, due: '2026-10-10');
    expect(tenantPaymentStatus(r, today: today), TenantPaymentStatus.due);
    expect(tenantPaymentStatus(r, today: DateTime(2026, 10, 11)),
        TenantPaymentStatus.overdue);
  });

  test('missing due date falls back to Due, not Overdue', () {
    final r = _t('x', hasDue: true);
    expect(tenantPaymentStatus(r, today: today), TenantPaymentStatus.due);
  });

  test('search combines with filters', () {
    expect(names(HostelGuestFilter.active, query: 'g05'), ['overdue']);
    expect(names(HostelGuestFilter.checkedOut, query: 'g05'), isEmpty);
    expect(names(HostelGuestFilter.all, query: '90004 56700'),
        hasLength(residents.length));
  });
}
