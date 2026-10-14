import 'dart:async';

import 'package:dio/dio.dart';
import 'package:dormly/features/notifications/presentation/notifications_providers.dart';
import 'package:dormly/features/tenant_portal/domain/tenant_home_summary.dart';
import 'package:dormly/features/tenant_portal/presentation/tenant_home_tab.dart';
import 'package:dormly/features/tenant_portal/presentation/tenant_portal_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _tenancy({String type = 'hostel_pg'}) => {
      'id': 't1',
      'full_name': 'Rahul Sharma',
      'status': 'active',
      'property_id': 'p1',
      'property_name': 'Sky Hostel',
      'property_city': 'Pune',
      'property_type_key': type,
      'node_id': 'n1',
      'node_name': 'B',
      'parent_node_name': '204',
      'node_level_key': 'bed',
      'move_in_at': '2026-06-01',
    };

Map<String, dynamic> _invoice({
  required String id,
  required num total,
  num paid = 0,
  String due = '2026-11-05',
  String periodStart = '2026-11-01',
  bool? overdue,
  bool draft = false,
}) =>
    {
      'id': id,
      'total_amount': '$total',
      'paid_amount': '$paid',
      'due_date': due,
      'period_start': periodStart,
      'sent_at': draft ? null : '2026-10-31T10:00:00.000Z',
      if (overdue != null) 'is_overdue': overdue,
    };

class _NoUnread extends UnreadNotificationsCount {
  @override
  Future<int> build() async => 0;
}

Future<void> _pumpHome(
  WidgetTester tester, {
  required FutureOr<Map<String, dynamic>> Function() tenancy,
  List<Map<String, dynamic>> invoices = const [],
  List<Map<String, dynamic>> requests = const [],
  List<Map<String, dynamic>> meters = const [],
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(900, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        myTenancyProvider.overrideWith((ref) async => tenancy()),
        myInvoicesProvider.overrideWith((ref) async => invoices),
        myComplaintsProvider.overrideWith((ref) async => requests),
        tenantMeterReadingsProvider.overrideWith((ref) async => meters),
        unreadNotificationsCountProvider.overrideWith(_NoUnread.new),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: TenantHomeTab(onOpenPayments: () {}, onOpenServices: () {}),
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

void main() {
  group('TenantDuesSummary', () {
    test('excludes drafts from dues', () {
      final s = TenantDuesSummary.fromInvoices([
        _invoice(id: 'd', total: 9000, draft: true),
        _invoice(id: 's', total: 6500, overdue: false),
      ]);
      expect(s.outstanding, 6500);
      expect(s.nextInvoice?['id'], 's');
      expect(s.status, TenantDuesStatus.upcoming);
    });

    test('only drafts means no bills', () {
      final s = TenantDuesSummary.fromInvoices([
        _invoice(id: 'd', total: 9000, draft: true),
      ]);
      expect(s.outstanding, 0);
      expect(s.status, TenantDuesStatus.noBills);
    });

    test('uses the remaining balance of a partially paid invoice', () {
      final s = TenantDuesSummary.fromInvoices([
        _invoice(id: 'p', total: 6500, paid: 2000, overdue: false),
      ]);
      expect(s.outstanding, 4500);
      expect(s.status, TenantDuesStatus.partiallyPaid);
      expect(s.lastPaidInvoice?['id'], 'p');
    });

    test('overdue follows the backend flag, not the device date', () {
      final flagged = TenantDuesSummary.fromInvoices([
        _invoice(id: 'o', total: 6500, paid: 500, overdue: true),
        _invoice(
          id: 'n',
          total: 1000,
          due: '2026-12-05',
          periodStart: '2026-12-01',
          overdue: false,
        ),
      ]);
      expect(flagged.status, TenantDuesStatus.overdue);
      expect(flagged.overdueCount, 1);
      expect(flagged.overdueAmount, 6000);
      expect(flagged.outstanding, 7000);

      final pastButNotFlagged = TenantDuesSummary.fromInvoices([
        _invoice(id: 'x', total: 6500, due: '2020-01-05', overdue: false),
      ]);
      expect(pastButNotFlagged.status, TenantDuesStatus.upcoming);
    });

    test('fully paid invoices leave nothing due', () {
      final s = TenantDuesSummary.fromInvoices([
        _invoice(id: 'a', total: 6500, paid: 6500, overdue: false),
      ]);
      expect(s.outstanding, 0);
      expect(s.status, TenantDuesStatus.paid);
      expect(s.nextDueDate, isNull);
    });
  });

  group('buildTenantActivity', () {
    test('merges real records newest first and skips drafts and unpaid', () {
      final items = buildTenantActivity(
        invoices: [
          _invoice(id: 'paid', total: 6500, paid: 6500, due: '2026-10-05'),
          _invoice(id: 'unpaid', total: 6500, due: '2026-11-05'),
          _invoice(id: 'draft', total: 100, paid: 100, draft: true),
        ],
        requests: [
          {'id': 'r1', 'title': 'Leaking tap', 'created_at': '2026-10-12T09:00:00Z'},
        ],
        meterReadings: [
          {'id': 'm1', 'meter_reading_value': 1200, 'created_at': '2026-09-30T09:00:00Z'},
        ],
      );
      expect(items.map((i) => i.source['id']), ['r1', 'paid', 'm1']);
      expect(items[1].hasExactDate, isFalse);
    });
  });

  group('TenantHomeTab', () {
    testWidgets('shows a loading state while the stay loads', (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      await _pumpHome(tester, tenancy: () => pending.future, settle: false);
      await tester.pump();
      expect(find.byKey(const Key('tenant-home-loading')), findsOneWidget);
    });

    testWidgets('API failure shows a friendly error and Retry recovers',
        (tester) async {
      var calls = 0;
      await _pumpHome(tester, tenancy: () {
        calls++;
        if (calls == 1) {
          throw DioException(
            requestOptions: RequestOptions(path: '/v1/tenant-portal/me'),
            response: Response(
              requestOptions: RequestOptions(path: '/v1/tenant-portal/me'),
              statusCode: 500,
              data: {'error': 'column n.parent_id does not exist'},
            ),
            type: DioExceptionType.badResponse,
          );
        }
        return _tenancy();
      });

      expect(find.text("We couldn't load your dashboard"), findsOneWidget);
      expect(find.textContaining('DioException'), findsNothing);
      expect(find.textContaining('parent_id'), findsNothing);
      expect(find.textContaining('500'), findsNothing);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(calls, 2);
      expect(find.text('Rent & Dues'), findsOneWidget);
      expect(find.text('Sky Hostel'), findsOneWidget);
    });

    testWidgets('empty states when nothing has been billed or logged',
        (tester) async {
      await _pumpHome(tester, tenancy: _tenancy);
      expect(find.text('No bills have been sent to you yet'), findsOneWidget);
      expect(find.text('No bills'), findsOneWidget);
      expect(find.textContaining('No activity yet'), findsOneWidget);
      expect(find.text('None yet'), findsOneWidget);
      expect(find.text('Not uploaded'), findsOneWidget);
    });

    testWidgets('drafts are not shown as dues', (tester) async {
      await _pumpHome(tester, tenancy: _tenancy, invoices: [
        _invoice(id: 'd', total: 9000, draft: true),
        _invoice(id: 's', total: 6500, overdue: false),
      ]);
      final amount = tester.widget<Text>(
        find.byKey(const Key('rent-dues-outstanding')),
      );
      expect(amount.data, contains('6,500'));
      expect(find.textContaining('9,000'), findsNothing);
      expect(find.text('Upcoming'), findsOneWidget);
      expect(find.text('Due 5 Nov 2026'), findsOneWidget);
    });

    testWidgets('partial payment shows the remaining balance', (tester) async {
      await _pumpHome(tester, tenancy: _tenancy, invoices: [
        _invoice(id: 'p', total: 6500, paid: 2000, overdue: false),
      ]);
      final amount = tester.widget<Text>(
        find.byKey(const Key('rent-dues-outstanding')),
      );
      expect(amount.data, contains('4,500'));
      expect(find.text('Partially paid'), findsOneWidget);
      expect(find.textContaining('2,000 paid of'), findsOneWidget);
    });

    testWidgets('overdue display uses the backend flag', (tester) async {
      await _pumpHome(tester, tenancy: _tenancy, invoices: [
        _invoice(id: 'o', total: 6500, due: '2026-10-05', overdue: true),
      ]);
      expect(find.text('Overdue'), findsOneWidget);
      expect(find.textContaining('overdue on 1 bill'), findsOneWidget);
    });

    testWidgets('meter reading action only for supported property types',
        (tester) async {
      await _pumpHome(tester, tenancy: _tenancy);
      expect(find.text('Meter Reading'), findsNothing);
      expect(find.text('Raise Request'), findsOneWidget);
      expect(find.text('Rental Agreement'), findsOneWidget);
    });

    testWidgets('meter reading action shown for a rental house',
        (tester) async {
      await _pumpHome(
        tester,
        tenancy: () => _tenancy(type: 'rental_house'),
      );
      expect(find.text('Meter Reading'), findsOneWidget);
    });
  });
}
