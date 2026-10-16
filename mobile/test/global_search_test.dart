import 'package:dio/dio.dart';
import 'package:dormly/features/search/domain/global_search.dart';
import 'package:dormly/features/search/presentation/global_search_screen.dart'
    show searchErrorMessage;
import 'package:flutter_test/flutter_test.dart';

SearchHit _hit(
  SearchCategory category, {
  String id = 'x1',
  String propertyId = 'p1',
  String? propertyType,
  String? nodeId,
  String? invoiceId,
}) =>
    SearchHit(
      category: category,
      id: id,
      title: 'T',
      propertyId: propertyId,
      propertyType: propertyType,
      nodeId: nodeId,
      invoiceId: invoiceId,
    );

DioException _http(int? status, {Object? data}) {
  final options = RequestOptions(path: '/v1/search');
  return DioException(
    requestOptions: options,
    response: status == null
        ? null
        : Response(requestOptions: options, statusCode: status, data: data),
    type: status == null
        ? DioExceptionType.connectionError
        : DioExceptionType.badResponse,
  );
}

void main() {
  group('categories and filters per role', () {
    test('mirror the server policy', () {
      expect(searchCategoriesForRole('owner').map((c) => c.wire), [
        'properties', 'rooms', 'tenants', 'team', 'complaints',
        'gate_passes', 'invoices', 'payments', 'meter_readings', 'mess_menu',
      ]);
      expect(searchCategoriesForRole('admin'), searchCategoriesForRole('owner'));
      expect(searchCategoriesForRole('manager'),
          isNot(contains(SearchCategory.team)));
      expect(searchCategoriesForRole('manager'),
          isNot(contains(SearchCategory.properties)));
      expect(searchCategoriesForRole('staff').map((c) => c.wire), [
        'rooms', 'tenants', 'complaints', 'gate_passes', 'meter_readings',
        'mess_menu',
      ]);
      expect(searchCategoriesForRole('tenant').map((c) => c.wire), [
        'rooms', 'invoices', 'payments', 'complaints', 'gate_passes',
        'meter_readings', 'mess_menu',
      ]);
      expect(searchCategoriesForRole(null), isEmpty);
      expect(searchCategoriesForRole('viewer'), isEmpty);
    });

    test('money filters are for owner, admin and manager only', () {
      expect(searchFiltersForRole('manager'), SearchQuickFilter.values);
      expect(searchFiltersForRole('staff'),
          [SearchQuickFilter.vacant, SearchQuickFilter.checkedOut]);
      expect(searchFiltersForRole('tenant'), isEmpty);
      expect(SearchQuickFilter.checkedOut.wire, 'checked_out');
    });

    test('tenant labels are personal', () {
      expect(
          searchCategoryLabel(SearchCategory.invoices, tenant: true), 'My bills');
      expect(
          searchCategoryLabel(SearchCategory.rooms,
              tenant: false, roomsLabel: 'Flats'),
          'Flats');
    });
  });

  group('SearchResponse', () {
    test('parses results and skips unknown categories or missing ids', () {
      final r = SearchResponse.fromJson({
        'categories': ['rooms', 'bogus', 'gate_passes'],
        'results': [
          {
            'category': 'invoices',
            'id': 'i1',
            'title': 'Ravi · Jan 2020',
            'propertyId': 'p1',
            'propertyName': 'Sunrise PG',
            'status': 'overdue',
            'amount': 3000,
            'invoiceId': 'i1',
            'date': '2020-01-06',
          },
          {'category': 'future_thing', 'id': 'z'},
          {'category': 'rooms'},
          'garbage',
        ],
      });
      expect(r.categories, [SearchCategory.rooms, SearchCategory.gatePasses]);
      expect(r.results, hasLength(1));
      final hit = r.results.single;
      expect(hit.amount, 3000);
      expect(hit.propertyName, 'Sunrise PG');
      expect(hit.phone, isNull);
    });

    test('parses overdue tenant results with and without contact and money', () {
      final r = SearchResponse.fromJson({
        'results': [
          {
            'category': 'tenants',
            'id': 't1',
            'title': 'Ravi Kumar',
            'subtitle': '101-A',
            'status': 'active',
            'propertyId': 'p1',
            'phone': '9876543210',
            'amount': 4500,
          },
          // Shape the server sends to staff: no phone, no amount.
          {
            'category': 'tenants',
            'id': 't2',
            'title': 'Sita Devi',
            'status': 'active',
            'propertyId': 'p1',
          },
        ],
      });
      final manager = r.results.first;
      expect(manager.phone, '9876543210');
      expect(manager.amount, 4500);
      expect(searchDestinationFor(manager, 'manager')!.kind,
          SearchDestinationKind.tenantProfile);
      final staff = r.results.last;
      expect(staff.phone, isNull);
      expect(staff.amount, isNull);
      expect(searchDestinationFor(staff, 'staff')!.kind,
          SearchDestinationKind.staffTenants);
    });

    test('tolerates a missing body', () {
      expect(SearchResponse.fromJson(null).results, isEmpty);
    });

    test('groups by the role category order', () {
      final groups = groupSearchHits([
        _hit(SearchCategory.invoices, id: 'i'),
        _hit(SearchCategory.tenants, id: 't1'),
        _hit(SearchCategory.tenants, id: 't2'),
      ], searchCategoriesForRole('owner'));
      expect(groups.map((g) => g.$1),
          [SearchCategory.tenants, SearchCategory.invoices]);
      expect(groups.first.$2.map((h) => h.id), ['t1', 't2']);
    });
  });

  group('searchDestinationFor', () {
    test('owner rooms open node or rental-space detail of the result property', () {
      final node = searchDestinationFor(
          _hit(SearchCategory.rooms, propertyId: 'p2', nodeId: 'n1',
              propertyType: 'hostel_pg'),
          'owner')!;
      expect(node.kind, SearchDestinationKind.nodeDetail);
      expect(node.propertyId, 'p2');
      expect(node.targetId, 'n1');
      final rental = searchDestinationFor(
          _hit(SearchCategory.rooms, propertyType: 'rental_house'), 'manager')!;
      expect(rental.kind, SearchDestinationKind.rentalSpaceDetail);
    });

    test('staff open their operational screens and never billing', () {
      expect(searchDestinationFor(_hit(SearchCategory.rooms), 'staff')!.kind,
          SearchDestinationKind.staffRooms);
      expect(searchDestinationFor(_hit(SearchCategory.tenants), 'staff')!.kind,
          SearchDestinationKind.staffTenants);
      expect(searchDestinationFor(_hit(SearchCategory.invoices), 'staff'), isNull);
      expect(searchDestinationFor(_hit(SearchCategory.payments), 'staff'), isNull);
      expect(searchDestinationFor(_hit(SearchCategory.team), 'staff'), isNull);
    });

    test('team and properties are owner/admin only', () {
      expect(searchDestinationFor(_hit(SearchCategory.team), 'manager'), isNull);
      expect(
          searchDestinationFor(_hit(SearchCategory.properties), 'manager'), isNull);
      expect(searchDestinationFor(_hit(SearchCategory.team), 'admin')!.kind,
          SearchDestinationKind.teamList);
    });

    test('payments open their invoice', () {
      final d = searchDestinationFor(
          _hit(SearchCategory.payments, id: 'pay1', invoiceId: 'inv1'), 'owner')!;
      expect(d.kind, SearchDestinationKind.invoiceDetail);
      expect(d.targetId, 'inv1');
    });

    test('tenants open their own self-service screens', () {
      String? kind(SearchCategory c) =>
          searchDestinationFor(_hit(c), 'tenant')?.kind.name;
      expect(kind(SearchCategory.invoices), 'tenantPayments');
      expect(kind(SearchCategory.payments), 'tenantPayments');
      expect(kind(SearchCategory.complaints), 'tenantComplaint');
      expect(kind(SearchCategory.gatePasses), 'tenantGatePasses');
      expect(kind(SearchCategory.messMenu), 'tenantMessMenu');
      expect(kind(SearchCategory.meterReadings), 'tenantMeterReadings');
      expect(kind(SearchCategory.rooms), 'tenantHome');
      expect(kind(SearchCategory.tenants), isNull);
      expect(searchDestinationFor(_hit(SearchCategory.rooms), null), isNull);
    });
  });

  group('searchErrorMessage', () {
    test('maps session, access, validation, network and server failures', () {
      expect(searchErrorMessage(_http(401)),
          'Your session has expired. Please sign in again.');
      expect(
          searchErrorMessage(_http(403, data: {
            'error': 'You do not have access to search this category.',
            'code': 'search_category_forbidden',
          })),
          'You do not have access to search this category.');
      expect(searchErrorMessage(_http(403)),
          'You do not have access to search this.');
      expect(
          searchErrorMessage(_http(400, data: {
            'error': 'Type at least 2 characters to search.',
          })),
          'Type at least 2 characters to search.');
      expect(searchErrorMessage(_http(null)),
          'Could not reach Dormly. Check your connection and try again.');
      expect(
          searchErrorMessage(_http(500, data: {'error': 'Internal server error'})),
          'Search failed. Please try again.');
      expect(searchErrorMessage(StateError('x')), 'Search failed. Please try again.');
    });

    test('rate limiting asks the user to wait', () {
      expect(
          searchErrorMessage(_http(429, data: {
            'error': 'Too many searches. Please wait a moment and try again.',
            'code': 'search_rate_limited',
          })),
          'Too many searches. Please wait a moment and try again.');
      expect(searchErrorMessage(_http(429)),
          'Too many searches. Please wait a moment and try again.');
    });
  });

  test('recent searches: newest first, de-duplicated, capped', () {
    var r = <String>[];
    for (final q in ['a1', 'b2', 'A1', 'c3']) {
      r = pushRecentSearch(r, q, max: 2);
    }
    expect(r, ['c3', 'A1']);
  });
}
