import 'package:dormly/features/tenancies/domain/tenant_filters.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _t(
  String name, {
  String status = 'active',
  bool hasDue = false,
  bool? hasOverdue,
  String? due,
  String room = 'G01',
  String phone = '9000456700',
}) =>
    {
      'full_name': name,
      'status': status,
      'has_due': hasDue,
      'earliest_open_due_date': due,
      if (hasOverdue != null) 'has_overdue': hasOverdue,
      'node_name': room,
      'phone': phone,
    };

void main() {
  // `has_overdue` is decided by the backend in the property's calendar.
  final residents = [
    _t('paid'),
    _t('due', hasDue: true, hasOverdue: false, due: '2026-10-12'),
    _t('dueToday', hasDue: true, hasOverdue: false, due: '2026-10-10'),
    _t('overdue', hasDue: true, hasOverdue: true, due: '2026-10-05', room: 'G05'),
    _t('outWithDues',
        status: 'ended', hasDue: true, hasOverdue: true, due: '2026-09-05'),
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

  test('overdue follows the backend flag, not the due date', () {
    // Device may already be past the due date; the property is not.
    final dueToday = _t('x', hasDue: true, hasOverdue: false, due: '2020-01-01');
    expect(tenantPaymentStatus(dueToday), TenantPaymentStatus.due);
    final overdue = _t('x', hasDue: true, hasOverdue: true, due: '2099-01-01');
    expect(tenantPaymentStatus(overdue), TenantPaymentStatus.overdue);
  });

  test('missing has_overdue falls back to Due, not Overdue', () {
    final r = _t('x', hasDue: true, due: '2020-01-01');
    expect(tenantPaymentStatus(r), TenantPaymentStatus.due);
  });

  test('a stale overdue flag without dues is Paid', () {
    final r = _t('x', hasOverdue: true);
    expect(tenantPaymentStatus(r), TenantPaymentStatus.paid);
  });

  test('search combines with filters', () {
    expect(names(HostelGuestFilter.active, query: 'g05'), ['overdue']);
    expect(names(HostelGuestFilter.checkedOut, query: 'g05'), isEmpty);
    expect(names(HostelGuestFilter.all, query: '90004 56700'),
        hasLength(residents.length));
  });
}
