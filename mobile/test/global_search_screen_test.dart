import 'dart:async';

import 'package:dio/dio.dart';
import 'package:dormly/features/auth/data/auth_repository.dart';
import 'package:dormly/features/notifications/presentation/notifications_providers.dart';
import 'package:dormly/features/search/data/global_search_repository.dart';
import 'package:dormly/features/search/domain/global_search.dart';
import 'package:dormly/features/search/presentation/global_search_screen.dart';
import 'package:dormly/features/search/presentation/search_navigation.dart';
import 'package:dormly/features/staff_home/presentation/staff_shell_screen.dart';
import 'package:dormly/features/structure/presentation/dynamic_dashboard/dynamic_dashboard_screen.dart'
    show contextRoleProvider;
import 'package:dormly/features/structure/presentation/property_shell_screen.dart'
    show propertyDetailProvider;
import 'package:dormly/features/tenant_portal/presentation/tenant_home_tab.dart';
import 'package:dormly/features/tenant_portal/presentation/tenant_portal_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/staff_test_support.dart';

const _p = 'p1';

class SearchCall {
  final String query;
  final SearchCategory? category;
  final SearchQuickFilter? filter;
  final CancelToken? token;
  SearchCall(this.query, this.category, this.filter, this.token);
}

class FakeSearchRepo implements GlobalSearchRepository {
  final calls = <SearchCall>[];

  /// When set, each call waits for a completer the test resolves.
  bool manual = false;
  final pending = <Completer<SearchResponse>>[];
  Object? error;
  List<SearchHit> Function(SearchCall call) respond = (_) => const [];

  @override
  Future<SearchResponse> search({
    required String query,
    SearchCategory? category,
    SearchQuickFilter? filter,
    CancelToken? cancelToken,
  }) {
    final call = SearchCall(query, category, filter, cancelToken);
    calls.add(call);
    if (manual) {
      final c = Completer<SearchResponse>();
      pending.add(c);
      return c.future;
    }
    if (error != null) return Future.error(error!);
    return Future.value(SearchResponse(results: respond(call)));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Opened {
  final List<SearchDestination> destinations = [];
}

SearchHit _hit(
  SearchCategory category,
  String id,
  String title, {
  String? subtitle,
  String? status,
  String propertyId = _p,
  String? propertyName = 'Sunrise PG',
  String? phone,
  double? amount,
  String? date,
  String? invoiceId,
}) =>
    SearchHit(
      category: category,
      id: id,
      title: title,
      subtitle: subtitle,
      status: status,
      propertyId: propertyId,
      propertyName: propertyName,
      propertyType: 'hostel_pg',
      nodeId: category == SearchCategory.rooms ? id : null,
      phone: phone,
      amount: amount,
      date: date,
      invoiceId: invoiceId,
    );

List<Override> _searchOverrides({
  required FakeAuthRepo auth,
  required FakeSearchRepo repo,
  _Opened? opened,
}) =>
    [
      authRepositoryProvider.overrideWithValue(auth),
      globalSearchRepositoryProvider.overrideWithValue(repo),
      propertyDetailProvider.overrideWith(
        (ref, id) async =>
            {'id': id, 'name': 'Sunrise PG', 'property_type_key': 'hostel_pg'},
      ),
      if (opened != null)
        searchResultOpenerProvider.overrideWithValue(
          (context, ref, destination, {required canManage}) async {
            opened.destinations.add(destination);
          },
        ),
    ];

Future<void> _pumpSearch(
  WidgetTester tester, {
  required String role,
  required FakeSearchRepo repo,
  _Opened? opened,
  FakeAuthRepo? auth,
  bool canManage = true,
  Size size = const Size(800, 1600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: _searchOverrides(
        auth: auth ?? FakeAuthRepo(role),
        repo: repo,
        opened: opened,
      ),
      child: MaterialApp(
        home: GlobalSearchScreen(propertyId: _p, canManage: canManage),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('global-search-field')), text);
  await tester.pump(searchDebounce);
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows loading, then grouped results with status and property',
      (tester) async {
    final repo = FakeSearchRepo()..manual = true;
    await _pumpSearch(tester, role: 'owner', repo: repo);
    expect(find.byKey(const Key('search-help')), findsOneWidget);

    await _type(tester, 'ravi');
    expect(repo.calls.single.query, 'ravi');
    expect(find.byKey(const Key('search-loading')), findsOneWidget);
    expect(find.byKey(const Key('search-progress')), findsOneWidget);

    repo.pending.single.complete(SearchResponse(results: [
      _hit(SearchCategory.invoices, 'i1', 'Ravi Kumar · Jan 2020',
          status: 'overdue', amount: 3000, date: '2020-01-06', invoiceId: 'i1'),
      _hit(SearchCategory.tenants, 't1', 'Ravi Kumar',
          subtitle: '101-A', status: 'active', phone: '9876543210'),
    ]));
    await tester.pumpAndSettle();

    expect(find.text('Tenants (1)'), findsOneWidget);
    expect(find.text('Invoices (1)'), findsOneWidget);
    // Tenants are listed before invoices, following the role's order.
    expect(
      tester.getTopLeft(find.text('Tenants (1)')).dy,
      lessThan(tester.getTopLeft(find.text('Invoices (1)')).dy),
    );
    expect(
      find.descendant(
          of: find.byKey(const Key('search-results')),
          matching: find.text('Overdue')),
      findsOneWidget,
    );
    expect(find.textContaining('Sunrise PG · 101-A'), findsOneWidget);
    expect(find.textContaining('₹3,000'), findsOneWidget);
    expect(find.byTooltip('Call'), findsOneWidget);
    expect(find.byTooltip('WhatsApp'), findsOneWidget);
    expect(find.byKey(const Key('search-progress')), findsNothing);
  });

  testWidgets('empty results explain what can be searched', (tester) async {
    final repo = FakeSearchRepo();
    await _pumpSearch(tester, role: 'manager', repo: repo);
    await _type(tester, 'zzzz');
    expect(find.text('No results for "zzzz".'), findsOneWidget);
    expect(find.textContaining('Search by name, phone'), findsOneWidget);
  });

  testWidgets('errors show a safe message and Retry searches again',
      (tester) async {
    final repo = FakeSearchRepo()
      ..error = httpError(403, data: {
        'error': 'You do not have access to search this category.',
        'code': 'search_category_forbidden',
      });
    await _pumpSearch(tester, role: 'manager', repo: repo);
    await _type(tester, 'ravi');
    expect(find.byKey(const Key('search-error')), findsOneWidget);
    expect(find.text('You do not have access to search this category.'),
        findsOneWidget);

    repo
      ..error = null
      ..respond = (_) => [_hit(SearchCategory.tenants, 't1', 'Ravi Kumar')];
    await tester.tap(find.byKey(const Key('search-retry')));
    await tester.pumpAndSettle();
    expect(repo.calls, hasLength(2));
    expect(find.text('Ravi Kumar'), findsOneWidget);
    expect(find.byKey(const Key('search-error')), findsNothing);
  });

  testWidgets('an expired session asks the user to sign in again',
      (tester) async {
    final repo = FakeSearchRepo()..error = httpError(401);
    await _pumpSearch(tester, role: 'staff', repo: repo);
    await _type(tester, 'ravi');
    expect(find.text('Your session has expired. Please sign in again.'),
        findsOneWidget);
  });

  testWidgets('too many searches shows the wait message and can retry',
      (tester) async {
    final repo = FakeSearchRepo()
      ..error = httpError(429, data: {
        'error': 'Too many searches. Please wait a moment and try again.',
        'code': 'search_rate_limited',
      });
    await _pumpSearch(tester, role: 'owner', repo: repo);
    await _type(tester, 'ravi');
    expect(
        find.text('Too many searches. Please wait a moment and try again.'),
        findsOneWidget);
    expect(repo.calls, hasLength(1));

    repo
      ..error = null
      ..respond = (_) => [_hit(SearchCategory.tenants, 't1', 'Ravi Kumar')];
    await tester.tap(find.byKey(const Key('search-retry')));
    await tester.pumpAndSettle();
    expect(find.text('Ravi Kumar'), findsOneWidget);
  });

  testWidgets(
      'overdue filter shows tenants who owe with Call/WhatsApp and overdue invoices',
      (tester) async {
    final repo = FakeSearchRepo()
      ..respond = (c) => c.filter == SearchQuickFilter.overdue
          ? [
              _hit(SearchCategory.tenants, 't1', 'Ravi Kumar',
                  subtitle: '101-A',
                  status: 'active',
                  phone: '9876543210',
                  amount: 4500),
              _hit(SearchCategory.invoices, 'i1', 'Ravi Kumar · Jan 2020',
                  subtitle: '101-A',
                  status: 'overdue',
                  amount: 3000,
                  date: '2020-01-06',
                  invoiceId: 'i1'),
            ]
          : const [];
    final opened = _Opened();
    await _pumpSearch(tester, role: 'manager', repo: repo, opened: opened);
    await tester.ensureVisible(find.byKey(const Key('search-chip-overdue')));
    await tester.tap(find.byKey(const Key('search-chip-overdue')));
    await tester.pumpAndSettle();

    expect(repo.calls.single.filter, SearchQuickFilter.overdue);
    expect(repo.calls.single.category, isNull);
    expect(find.text('Tenants (1)'), findsOneWidget);
    expect(find.text('Invoices (1)'), findsOneWidget);
    expect(find.textContaining('₹4,500'), findsOneWidget);
    expect(find.textContaining('₹3,000'), findsOneWidget);
    expect(find.byTooltip('Call'), findsOneWidget);
    expect(find.byTooltip('WhatsApp'), findsOneWidget);
    expect(
      find.descendant(
          of: find.byKey(const Key('search-results')),
          matching: find.text('Overdue')),
      findsOneWidget,
    );

    await tester.tap(find.text('Ravi Kumar'));
    await tester.pumpAndSettle();
    expect(opened.destinations.last.kind, SearchDestinationKind.tenantProfile);
    expect(opened.destinations.last.targetId, 't1');
    await tester.tap(find.text('Ravi Kumar · Jan 2020'));
    await tester.pumpAndSettle();
    expect(opened.destinations.last.kind, SearchDestinationKind.invoiceDetail);
    expect(opened.destinations.last.targetId, 'i1');
  });

  testWidgets('a tenant result without phone or amount shows no contact actions',
      (tester) async {
    final repo = FakeSearchRepo()
      ..respond = (_) => [
            _hit(SearchCategory.tenants, 't1', 'Ravi Kumar',
                subtitle: '101-A', status: 'active'),
          ];
    await _pumpSearch(tester, role: 'staff', repo: repo);
    await _type(tester, 'ravi');
    expect(find.text('Ravi Kumar'), findsOneWidget);
    expect(find.byTooltip('Call'), findsNothing);
    expect(find.byTooltip('WhatsApp'), findsNothing);
    expect(find.textContaining('₹'), findsNothing);
  });

  testWidgets('debounces typing and needs two characters', (tester) async {
    final repo = FakeSearchRepo();
    await _pumpSearch(tester, role: 'owner', repo: repo);

    await tester.enterText(find.byKey(const Key('global-search-field')), 'r');
    await tester.pump(const Duration(seconds: 1));
    expect(repo.calls, isEmpty);
    expect(find.byKey(const Key('search-min-length')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('global-search-field')), 'ra');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(find.byKey(const Key('global-search-field')), 'rav');
    await tester.pump(const Duration(milliseconds: 299));
    expect(repo.calls, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(repo.calls.map((c) => c.query), ['rav']);
  });

  testWidgets('cancels the previous request and ignores its late response',
      (tester) async {
    final repo = FakeSearchRepo()..manual = true;
    await _pumpSearch(tester, role: 'owner', repo: repo);

    await _type(tester, 'ra');
    await _type(tester, 'rav');
    expect(repo.calls, hasLength(2));
    expect(repo.calls.first.token!.isCancelled, isTrue);
    expect(repo.calls.last.token!.isCancelled, isFalse);

    repo.pending.last.complete(SearchResponse(
        results: [_hit(SearchCategory.tenants, 'new', 'Ravish New')]));
    await tester.pump();
    repo.pending.first.complete(SearchResponse(
        results: [_hit(SearchCategory.tenants, 'old', 'Rakesh Old')]));
    await tester.pumpAndSettle();

    expect(find.text('Ravish New'), findsOneWidget);
    expect(find.text('Rakesh Old'), findsNothing);
  });

  testWidgets('category and quick-filter chips narrow the request',
      (tester) async {
    final repo = FakeSearchRepo();
    await _pumpSearch(tester, role: 'owner', repo: repo);
    await _type(tester, 'ravi');

    // The category chip bar is the first list on the screen.
    final categoryBar = find.byType(ListView).first;
    await tester.dragUntilVisible(find.byKey(const Key('search-chip-invoices')),
        categoryBar, const Offset(-200, 0));
    await tester.ensureVisible(find.byKey(const Key('search-chip-invoices')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('search-chip-invoices')));
    await tester.pumpAndSettle();
    expect(repo.calls.last.category, SearchCategory.invoices);
    expect(repo.calls.last.filter, isNull);

    await tester.ensureVisible(find.byKey(const Key('search-chip-overdue')));
    await tester.tap(find.byKey(const Key('search-chip-overdue')));
    await tester.pumpAndSettle();
    expect(repo.calls.last.filter, SearchQuickFilter.overdue);
    expect(repo.calls.last.category, isNull);

    await tester.dragUntilVisible(find.byKey(const Key('search-chip-all')),
        categoryBar, const Offset(200, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('search-chip-all')));
    await tester.pumpAndSettle();
    expect(repo.calls.last.filter, isNull);
    expect(repo.calls.last.category, isNull);
  });

  testWidgets('a quick filter searches without any text', (tester) async {
    final repo = FakeSearchRepo()
      ..respond = (c) => c.filter == SearchQuickFilter.vacant
          ? [_hit(SearchCategory.rooms, 'r3', 'Room 103', status: 'vacant')]
          : const [];
    await _pumpSearch(tester, role: 'owner', repo: repo);
    await tester.ensureVisible(find.byKey(const Key('search-chip-vacant')));
    await tester.tap(find.byKey(const Key('search-chip-vacant')));
    await tester.pumpAndSettle();
    expect(repo.calls.single.query, '');
    expect(find.text('Room 103'), findsOneWidget);
    expect(find.byKey(const Key('search-add-tenant-r3')), findsOneWidget);
  });

  testWidgets('staff get operational chips only and no Add Tenant',
      (tester) async {
    final repo = FakeSearchRepo()
      ..respond = (_) =>
          [_hit(SearchCategory.rooms, 'r3', 'Room 103', status: 'vacant')];
    await _pumpSearch(tester, role: 'staff', repo: repo);
    for (final hidden in ['invoices', 'payments', 'team', 'properties',
        'overdue', 'drafts']) {
      expect(find.byKey(Key('search-chip-$hidden')), findsNothing,
          reason: hidden);
    }
    expect(find.byKey(const Key('search-chip-vacant')), findsOneWidget);
    expect(find.byKey(const Key('search-chip-complaints')), findsOneWidget);

    await _type(tester, 'room');
    expect(find.byKey(const Key('search-add-tenant-r3')), findsNothing);
    expect(find.text('Vacant'), findsOneWidget);
  });

  testWidgets('tenants get personal categories and no filters',
      (tester) async {
    final repo = FakeSearchRepo()
      ..respond = (_) => [
            _hit(SearchCategory.invoices, 'i1', 'Bill · Jan 2020',
                status: 'overdue', amount: 3000),
          ];
    await _pumpSearch(tester, role: 'tenant', repo: repo);
    expect(find.text('My bills'), findsOneWidget);
    expect(find.text('My complaints'), findsOneWidget);
    expect(find.byKey(const Key('search-chip-tenants')), findsNothing);
    expect(find.byKey(const Key('search-chip-vacant')), findsNothing);
    expect(find.byKey(const Key('search-chip-overdue')), findsNothing);

    await _type(tester, 'jan');
    expect(find.text('My bills (1)'), findsOneWidget);
    // Tenants never see another property's name on their own records.
    expect(find.textContaining('Sunrise PG'), findsNothing);
  });

  testWidgets('tapping a result opens its existing screen', (tester) async {
    final repo = FakeSearchRepo()
      ..respond = (_) => [
            _hit(SearchCategory.payments, 'pay1', 'Ravi · Jan 2020',
                invoiceId: 'inv1', propertyId: 'p2'),
          ];
    final opened = _Opened();
    await _pumpSearch(tester, role: 'owner', repo: repo, opened: opened);
    await _type(tester, 'upi');
    await tester.tap(find.text('Ravi · Jan 2020'));
    await tester.pumpAndSettle();

    final d = opened.destinations.single;
    expect(d.kind, SearchDestinationKind.invoiceDetail);
    expect(d.propertyId, 'p2');
    expect(d.targetId, 'inv1');
    // The tapped query is remembered and the results refresh.
    expect((await SharedPreferences.getInstance())
        .getStringList('globalSearchRecent:$_p'), ['upi']);
    expect(repo.calls, hasLength(2));
  });

  testWidgets('recent searches can be reused', (tester) async {
    SharedPreferences.setMockInitialValues({
      'globalSearchRecent:$_p': ['ravi'],
    });
    final repo = FakeSearchRepo();
    await _pumpSearch(tester, role: 'owner', repo: repo);
    await tester.tap(find.text('ravi'));
    await tester.pump(searchDebounce);
    await tester.pumpAndSettle();
    expect(repo.calls.single.query, 'ravi');
  });

  testWidgets('a workspace change clears the query and results',
      (tester) async {
    final auth = FakeAuthRepo('owner');
    final repo = FakeSearchRepo()
      ..respond = (_) => [_hit(SearchCategory.tenants, 't1', 'Ravi Kumar')];
    await _pumpSearch(tester, role: 'owner', repo: repo, auth: auth);
    await _type(tester, 'ravi');
    expect(find.text('Ravi Kumar'), findsOneWidget);

    auth.role = 'staff';
    ProviderScope.containerOf(tester.element(find.byType(GlobalSearchScreen)))
        .invalidate(contextRoleProvider);
    await tester.pumpAndSettle();

    expect(find.text('Ravi Kumar'), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('global-search-field')))
          .controller!
          .text,
      isEmpty,
    );
    expect(find.byKey(const Key('search-chip-invoices')), findsNothing);
  });

  testWidgets('fits a small phone screen without overflow', (tester) async {
    final long = 'Very long tenant name that keeps going ' * 3;
    final repo = FakeSearchRepo()
      ..respond = (_) => [
            _hit(SearchCategory.tenants, 't1', long,
                subtitle: long, phone: '9876543210', status: 'active'),
            _hit(SearchCategory.rooms, 'r1', long, status: 'vacant'),
            _hit(SearchCategory.invoices, 'i1', long,
                status: 'overdue', amount: 9999999999, date: '2020-01-06'),
            _hit(SearchCategory.complaints, 'c1', long,
                subtitle: long, status: 'in_progress'),
          ];
    await _pumpSearch(tester,
        role: 'owner', repo: repo, size: const Size(320, 568));
    await _type(tester, 'very');
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('search-results')), findsOneWidget);
  });

  group('entry points', () {
    testWidgets('staff home header opens search', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final repo = FakeSearchRepo();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          ...staffOverrides(),
          globalSearchRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(
          home: StaffShellScreen(propertyId: _p, propertyName: 'Sky Towers'),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('staff-search')));
      await tester.pumpAndSettle();
      expect(find.byType(GlobalSearchScreen), findsOneWidget);
      expect(find.byKey(const Key('search-chip-overdue')), findsNothing);
    });

    testWidgets('tenant home top bar opens personal search', (tester) async {
      tester.view.physicalSize = const Size(900, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = FakeSearchRepo();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(FakeAuthRepo('tenant')),
          globalSearchRepositoryProvider.overrideWithValue(repo),
          myTenancyProvider.overrideWith((ref) async => {
                'id': 't1',
                'full_name': 'Rahul Sharma',
                'status': 'active',
                'property_id': 'p1',
                'property_name': 'Sky Hostel',
                'property_type_key': 'hostel_pg',
                'node_id': 'n1',
                'node_name': 'B',
              }),
          myInvoicesProvider.overrideWith((ref) async => const []),
          myComplaintsProvider.overrideWith((ref) async => const []),
          tenantMeterReadingsProvider.overrideWith((ref) async => const []),
          unreadNotificationsCountProvider.overrideWith(FakeUnreadCount.new),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: TenantHomeTab(onOpenPayments: () {}, onOpenServices: () {}),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('tenant-search')));
      await tester.pumpAndSettle();
      expect(find.byType(GlobalSearchScreen), findsOneWidget);
      expect(find.text('My bills'), findsOneWidget);
      expect(find.byKey(const Key('search-chip-tenants')), findsNothing);
    });
  });
}
