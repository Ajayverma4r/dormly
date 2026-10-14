import 'dart:async';

import 'package:dio/dio.dart';
import 'package:dormly/core/network/api_client.dart';
import 'package:dormly/features/tenant_portal/data/tenant_portal_repository.dart';
import 'package:dormly/features/tenant_portal/domain/payment_history.dart';
import 'package:dormly/features/tenant_portal/presentation/tenant_payment_history_screen.dart';
import 'package:dormly/features/tenant_portal/presentation/tenant_portal_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _cur = '11000000-0000-4000-8000-000000000001';
const _old = '11000000-0000-4000-8000-000000000002';

final _stays = [
  TenantStay.fromJson({
    'tenancy_id': 't-cur',
    'property_id': _cur,
    'property_name': 'Sky Hostel',
    'property_city': 'Hyderabad',
    'node_name': 'Bed 1',
    'parent_node_name': 'Room 101',
    'move_in_at': '2026-09-01T00:00:00.000Z',
    'move_out_at': null,
    'status': 'active',
    'is_current': true,
  }),
  TenantStay.fromJson({
    'tenancy_id': 't-old',
    'property_id': _old,
    'property_name': 'River PG',
    'property_city': 'Delhi',
    'node_name': 'Room 203',
    'move_in_at': '2026-01-01',
    'move_out_at': '2026-08-31',
    'status': 'ended',
    'is_current': false,
  }),
];

Map<String, dynamic> _payment(String id, num amount, String paidOn,
        {String property = _old,
        String name = 'River PG',
        num total = 6000,
        num balance = 0}) =>
    {
      'id': id,
      'amount': amount,
      'method': 'upi',
      'paid_at': '${paidOn}T04:00:00.000Z',
      'paid_on': paidOn,
      'invoice_id': 'inv-$property',
      'period_start': '2026-05-01',
      'period_end': '2026-05-31',
      'invoice_total': total,
      'invoice_balance': balance,
      'property_id': property,
      'property_name': name,
    };

PaymentHistory _history(List<Map<String, dynamic>> payments,
        {num outstanding = 0}) =>
    PaymentHistory.fromJson({
      'summary': {
        'total_received':
            payments.fold<num>(0, (s, p) => s + (p['amount'] as num)),
        'payment_count': payments.length,
        'invoice_count': payments.map((p) => p['invoice_id']).toSet().length,
        'current_outstanding': outstanding,
      },
      'payments': payments,
    });

Future<List<StatementFilter>> _pump(
  WidgetTester tester, {
  required FutureOr<PaymentHistory> Function(StatementFilter) history,
  FutureOr<List<TenantStay>> Function()? stays,
  int initialTab = 0,
}) async {
  tester.view.physicalSize = const Size(900, 3600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final requested = <StatementFilter>[];

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tenantStaysProvider.overrideWith((ref) async => (stays ?? () => _stays)()),
        paymentHistoryProvider.overrideWith((ref, filter) async {
          requested.add(filter);
          return history(filter);
        }),
      ],
      child: MaterialApp(
        home: TenantPaymentHistoryScreen(initialTab: initialTab),
      ),
    ),
  );
  return requested;
}

void main() {
  group('payment history domain', () {
    test('filter validates the range and sends calendar dates only', () {
      final bad = StatementFilter(
        from: DateTime(2026, 10, 20),
        to: DateTime(2026, 10, 1),
      );
      expect(bad.validationError, isNotNull);

      final ok = StatementFilter(
        propertyId: _old,
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 10, 14),
      );
      expect(ok.validationError, isNull);
      expect(ok.toQuery(), {
        'propertyId': _old,
        'from': '2026-01-01',
        'to': '2026-10-14',
      });
      expect(StatementFilter.all.toQuery(), isEmpty);
    });

    test('properties list current first, one entry per property', () {
      final props = stayProperties([..._stays.reversed, _stays[1]]);
      expect(props.map((p) => p.name), ['Sky Hostel', 'River PG']);
      expect(props.first.isCurrent, isTrue);
    });

    test('two payments on one invoice stay two transactions', () {
      final h = _history([
        _payment('a', 3000, '2026-05-20'),
        _payment('b', 3000, '2026-05-10'),
      ]);
      expect(h.payments, hasLength(2));
      expect(h.totalReceived, 6000);
      expect(h.invoiceCount, 1);
      expect(h.payments.first.paidOn, DateTime(2026, 5, 20));
    });

    test('statement link carries the filter and the token', () {
      final repo = TenantPortalRepository(ApiClient());
      final uri = repo.paymentStatementUrl(
        StatementFilter(propertyId: _old, from: DateTime(2026, 5, 1)).toQuery(),
        'tok',
      );
      expect(uri.path, '/v1/tenant-portal/payment-statement.pdf');
      expect(uri.queryParameters,
          {'propertyId': _old, 'from': '2026-05-01', 'token': 'tok'});
    });
  });

  group('TenantPaymentHistoryScreen', () {
    testWidgets('shows loading while payments load', (tester) async {
      final pending = Completer<PaymentHistory>();
      await _pump(tester, history: (_) => pending.future);
      await tester.pump();
      expect(find.byKey(const Key('history-loading')), findsOneWidget);
    });

    testWidgets('error shows a friendly message and Retry reloads',
        (tester) async {
      var calls = 0;
      await _pump(tester, history: (_) {
        calls++;
        if (calls == 1) {
          throw DioException(
            requestOptions: RequestOptions(path: '/x'),
            response: Response(
              requestOptions: RequestOptions(path: '/x'),
              statusCode: 500,
              data: {'error': 'relation payments does not exist'},
            ),
            type: DioExceptionType.badResponse,
          );
        }
        return _history([_payment('a', 3000, '2026-05-20')]);
      });
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load your payments"), findsOneWidget);
      expect(find.textContaining('relation'), findsNothing);
      expect(find.textContaining('DioException'), findsNothing);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('Payments (1)'), findsOneWidget);
    });

    testWidgets('empty history shows a clear message', (tester) async {
      await _pump(tester, history: (_) => _history([]));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('history-empty')), findsOneWidget);
      expect(find.text('Payments (0)'), findsOneWidget);
    });

    testWidgets('lists current and past stays with stay indicators',
        (tester) async {
      await _pump(tester, history: (_) => _history([]));
      await tester.pumpAndSettle();
      expect(find.text('Your Properties (2)'), findsOneWidget);
      expect(find.text('Current Stay'), findsOneWidget);
      expect(find.text('Past Stay'), findsOneWidget);
      expect(find.text('Room 101 · Bed 1 · Hyderabad'), findsOneWidget);
      expect(find.text('1 Sep 2026 – Present'), findsOneWidget);
      expect(find.text('1 Jan 2026 – 31 Aug 2026'), findsOneWidget);
    });

    testWidgets('selecting a past stay requests only that property',
        (tester) async {
      final requested = await _pump(tester, history: (f) {
        return f.propertyId == _old
            ? _history([
                _payment('a', 3000, '2026-05-20'),
                _payment('b', 3000, '2026-05-10'),
              ])
            : _history([]);
      });
      await tester.pumpAndSettle();
      await tester.tap(find.text('River PG').last);
      await tester.pumpAndSettle();

      expect(requested.last.propertyId, _old);
      expect(find.text('Payments (2)'), findsOneWidget);
      // Two actual ₹3,000 payments, ₹6,000 received in total.
      expect(find.text('₹3,000'), findsNWidgets(2));
      final total = tester.widget<Text>(find.byKey(const Key('summary-total')));
      expect(total.data, '₹6,000');
    });

    testWidgets('partial payment keeps outstanding separate from paid',
        (tester) async {
      await _pump(
        tester,
        history: (_) => _history(
          [
            _payment('p', 2000, '2026-10-01',
                property: _cur, name: 'Sky Hostel', total: 6500, balance: 4500),
          ],
          outstanding: 4500,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('summary-total'))).data,
        '₹2,000',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('summary-outstanding'))).data,
        '₹4,500',
      );

      await tester.tap(find.text('₹2,000').last);
      await tester.pumpAndSettle();
      expect(find.text('Payment Details'), findsOneWidget);
      expect(find.text('₹4,500 still due'), findsOneWidget);
      expect(find.text('UPI'), findsOneWidget);
      expect(find.text('1 Oct 2026'), findsOneWidget);
    });

    testWidgets('a From date after the To date blocks Apply', (tester) async {
      await _pump(tester, history: (_) => _history([]));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('from-date')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('20'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('to-date')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('10'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('filter-error')), findsOneWidget);
      final apply = tester.widget<FilledButton>(
        find.byKey(const Key('apply-filters')),
      );
      expect(apply.onPressed, isNull);
    });

    testWidgets('PDF tab disables download when there is nothing to export',
        (tester) async {
      await _pump(tester, history: (_) => _history([]), initialTab: 1);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('statement-empty')), findsOneWidget);
      final button = tester.widget<ButtonStyleButton>(
        find.byKey(const Key('download-pdf')),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('PDF tab previews the summary and enables download',
        (tester) async {
      await _pump(
        tester,
        history: (_) => _history([
          _payment('a', 3000, '2026-05-20'),
          _payment('b', 3000, '2026-05-10'),
        ]),
        initialTab: 1,
      );
      await tester.pumpAndSettle();
      expect(find.text('2 payments will be included in the statement.'),
          findsOneWidget);
      final button = tester.widget<ButtonStyleButton>(
        find.byKey(const Key('download-pdf')),
      );
      expect(button.onPressed, isNotNull);
    });
  });
}
