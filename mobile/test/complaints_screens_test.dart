import 'dart:async';

import 'package:dio/dio.dart';
import 'package:dormly/features/complaints/data/complaints_repository.dart';
import 'package:dormly/features/complaints/presentation/complaint_details_screen.dart';
import 'package:dormly/features/complaints/presentation/complaint_ui.dart';
import 'package:dormly/features/complaints/presentation/complaints_list_screen.dart';
import 'package:dormly/features/structure/presentation/property_shell_screen.dart'
    show propertyDetailProvider;
import 'package:dormly/features/tenant_portal/presentation/tenant_portal_providers.dart'
    show myTenancyProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _p1 = '11000000-0000-4000-8000-000000000001';

Map<String, dynamic> _c(
  String id,
  String description,
  String day, {
  String status = 'open',
  String category = 'Electricity',
  String? room = 'Room 101',
}) =>
    {
      'id': id,
      'property_id': _p1,
      'category': category,
      'description': description,
      'status': status,
      'priority': 'medium',
      if (room != null) 'node_name': room,
      'created_at': '2026-10-${day}T06:30:00Z',
    };

final _complaints = [
  _c('a', 'Door lock issue', '02', status: 'resolved', category: 'Other', room: 'Room 202'),
  _c('b', 'Water leakage', '10', status: 'in_progress', category: 'Plumbing', room: 'Room 203'),
  _c('c', 'AC not working', '12', category: 'AC / Cooling'),
  _c('d', 'Fan not working', '06', category: 'Electricity', room: 'Room 104'),
  _c('e', 'Old closed ticket', '01', status: 'closed', category: 'Cleaning'),
];

class _FakeRepo implements ComplaintsRepository {
  final calls = <(String, String, String, String?)>[];
  final commentCalls = <(String, String, String, String?)>[];
  final assignCalls = <(String, String, String?)>[];
  Object? failWith;
  Map<String, dynamic> Function(String? userId)? assignResult;

  @override
  Future<Map<String, dynamic>> addComment(
    String propertyId,
    String complaintId,
    String body, {
    String? visibility,
  }) async {
    if (failWith != null) throw failWith!;
    commentCalls.add((propertyId, complaintId, body, visibility));
    return {'id': 'new'};
  }

  @override
  Future<Map<String, dynamic>> setAssignment(
    String propertyId,
    String complaintId,
    String? assigneeUserId,
  ) async {
    if (failWith != null) throw failWith!;
    assignCalls.add((propertyId, complaintId, assigneeUserId));
    return assignResult!(assigneeUserId);
  }

  @override
  Future<void> updateStatus(
    String propertyId,
    String complaintId,
    String status, {
    String? resolutionNote,
  }) async {
    if (failWith != null) throw failWith!;
    calls.add((propertyId, complaintId, status, resolutionNote));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _tapFilter(WidgetTester tester, String status) async {
  final chip = find.byKey(Key('complaint-filter-$status'));
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

DioException _dio(int status, String serverText) => DioException(
      requestOptions: RequestOptions(path: '/x'),
      response: Response(
        requestOptions: RequestOptions(path: '/x'),
        statusCode: status,
        data: {'error': serverText},
      ),
      type: DioExceptionType.badResponse,
    );

const _p2 = '12000000-0000-4000-8000-000000000002';

/// Property records as GET /v1/properties/:id returns them.
final _properties = {
  _p1: {'id': _p1, 'name': 'Sky Hostel', 'address': 'Shamirpet', 'city': 'Hyderabad'},
  _p2: {'id': _p2, 'name': 'Lake View PG', 'address': 'Madhapur', 'city': 'Hyderabad'},
};

Future<ProviderContainer> _pump(
  WidgetTester tester,
  Widget home, {
  String? role = 'owner',
  FutureOr<List<Map<String, dynamic>>> Function()? load,
  _FakeRepo? repo,
  Map<String, dynamic> Function(String id)? property,
  Map<String, dynamic>? tenancy,
  List<String>? propertyRequests,
  List<String>? tenancyRequests,
  FutureOr<List<Map<String, dynamic>>?> Function()? comments,
  List<Map<String, dynamic>> assignees = const [],
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      complaintsProvider.overrideWith((ref, id) async => (load ?? () => _complaints)()),
      complaintViewerRoleProvider.overrideWith((ref) async => role),
      propertyDetailProvider.overrideWith((ref, id) async {
        propertyRequests?.add(id);
        return (property ?? (id) => _properties[id] ?? {'id': id})(id);
      }),
      myTenancyProvider.overrideWith((ref) async {
        tenancyRequests?.add('me');
        return tenancy ?? <String, dynamic>{};
      }),
      // Default: the server has no comments yet (migration not applied).
      complaintCommentsProvider.overrideWith((ref, key) async => (comments ?? () => null)()),
      complaintAssigneesProvider.overrideWith((ref, id) async => assignees),
      if (repo != null) complaintsRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: home),
    ),
  );
  return container;
}

Widget _details(Map<String, dynamic> c) => ComplaintDetailsScreen(
      complaint: c,
      propertyName: 'Sky Hostel',
      propertyAddress: 'Shamirpet, Hyderabad',
    );

void main() {
  group('helpers', () {
    test('status counts come from the loaded complaints', () {
      expect(complaintStatusCounts(_complaints), {
        'all': 5,
        'resolved': 1,
        'in_progress': 1,
        'open': 2,
        'closed': 1,
      });
    });

    test('newest first by creation time', () {
      expect(sortComplaintsNewestFirst(_complaints).map((c) => c['id']),
          ['c', 'b', 'd', 'a', 'e']);
    });
  });

  group('Complaint Details property information', () {
    testWidgets("owners see the complaint's own property from the shared property record",
        (tester) async {
      final requests = <String>[];
      await _pump(tester, ComplaintDetailsScreen(complaint: _c('c', 'AC not working', '12')),
          propertyRequests: requests);
      await tester.pumpAndSettle();

      expect(find.text('Room 101 · Sky Hostel'), findsOneWidget);
      expect(find.text('Shamirpet, Hyderabad'), findsOneWidget);
      expect(requests, [_p1]);
    });

    testWidgets("a complaint from another property shows that property, not the first one",
        (tester) async {
      await _pump(tester,
          ComplaintDetailsScreen(complaint: {..._c('z', 'Leak', '12'), 'property_id': _p2}));
      await tester.pumpAndSettle();

      expect(find.text('Room 101 · Lake View PG'), findsOneWidget);
      expect(find.text('Madhapur, Hyderabad'), findsOneWidget);
      expect(find.textContaining('Sky Hostel'), findsNothing);
    });

    testWidgets("a property record for a different id is never shown", (tester) async {
      await _pump(tester, ComplaintDetailsScreen(complaint: _c('c', 'AC not working', '12')),
          property: (_) => _properties[_p2]!);
      await tester.pumpAndSettle();

      expect(find.text('Room 101'), findsOneWidget);
      expect(find.textContaining('Lake View PG'), findsNothing);
      expect(find.textContaining('Madhapur'), findsNothing);
    });

    testWidgets("tenants see their current tenancy's property without the owner endpoint",
        (tester) async {
      final requests = <String>[];
      await _pump(
        tester,
        ComplaintDetailsScreen(complaint: _c('t', 'Fan not working', '06')),
        role: 'tenant',
        propertyRequests: requests,
        tenancy: {
          'property_id': _p1,
          'property_name': 'Sky Hostel',
          'property_address': 'Shamirpet',
          'property_city': 'Hyderabad',
        },
      );
      await tester.pumpAndSettle();

      expect(find.text('Room 101 · Sky Hostel'), findsOneWidget);
      expect(find.text('Shamirpet, Hyderabad'), findsOneWidget);
      expect(requests, isEmpty);
    });

    testWidgets("a tenant's complaint from a past property does not borrow the current one",
        (tester) async {
      await _pump(
        tester,
        ComplaintDetailsScreen(complaint: {..._c('t', 'Old issue', '01'), 'property_id': _p2}),
        role: 'tenant',
        tenancy: {'property_id': _p1, 'property_name': 'Sky Hostel', 'property_address': 'Shamirpet'},
      );
      await tester.pumpAndSettle();

      expect(find.text('Room 101'), findsOneWidget);
      expect(find.textContaining('Sky Hostel'), findsNothing);
      expect(find.textContaining('Shamirpet'), findsNothing);
    });

    testWidgets('missing property id: no lookup, no crash, nothing invented', (tester) async {
      final requests = <String>[];
      final tenancyRequests = <String>[];
      await _pump(
        tester,
        const ComplaintDetailsScreen(complaint: {'id': 'x', 'status': 'open', 'node_name': 'Room 9'}),
        propertyRequests: requests,
        tenancyRequests: tenancyRequests,
      );
      await tester.pumpAndSettle();

      expect(find.text('Room 9'), findsOneWidget);
      expect(requests, isEmpty);
      expect(tenancyRequests, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failed property lookup just hides the property line', (tester) async {
      await _pump(tester, ComplaintDetailsScreen(complaint: _c('c', 'AC not working', '12')),
          property: (_) => throw _dio(500, 'boom'));
      await tester.pumpAndSettle();

      expect(find.text('Room 101'), findsOneWidget);
      expect(find.text('AC not working'), findsOneWidget);
      expect(find.textContaining('boom'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an unknown role makes no property lookups', (tester) async {
      final requests = <String>[];
      final tenancyRequests = <String>[];
      await _pump(tester, ComplaintDetailsScreen(complaint: _c('c', 'AC not working', '12')),
          role: null, propertyRequests: requests, tenancyRequests: tenancyRequests);
      await tester.pumpAndSettle();

      expect(requests, isEmpty);
      expect(tenancyRequests, isEmpty);
      expect(find.text('Room 101'), findsOneWidget);
    });
  });

  group('All Complaints', () {
    testWidgets('renders rows newest first with room, date and status badges',
        (tester) async {
      await _pump(tester, const ComplaintsListScreen(propertyId: _p1));
      await tester.pumpAndSettle();

      expect(find.text('All Complaints'), findsOneWidget);
      expect(find.text('Sky Hostel'), findsOneWidget);
      final titles = ['AC not working', 'Water leakage', 'Fan not working', 'Door lock issue'];
      final ys = [for (final t in titles) tester.getTopLeft(find.text(t)).dy];
      expect(ys, orderedEquals([...ys]..sort()));
      expect(find.text('Room 101 · 12 Oct 2026'), findsOneWidget);
      expect(find.text('Room 203 · 10 Oct 2026'), findsOneWidget);
      final tiles = find.byType(ComplaintListTile);
      expect(find.descendant(of: tiles, matching: find.text('Open')), findsNWidgets(2));
      expect(find.descendant(of: tiles, matching: find.text('In Progress')), findsOneWidget);
      expect(find.descendant(of: tiles, matching: find.text('Resolved')), findsOneWidget);
      expect(find.descendant(of: tiles, matching: find.text('Closed')), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNWidgets(5));
    });

    testWidgets('filter chips show counts and filter the list', (tester) async {
      await _pump(tester, const ComplaintsListScreen(propertyId: _p1));
      await tester.pumpAndSettle();

      expect(find.text('All (5)'), findsOneWidget);
      expect(find.text('Open (2)'), findsOneWidget);
      expect(find.text('In Progress (1)'), findsOneWidget);
      expect(find.text('Resolved (1)'), findsOneWidget);
      expect(find.text('Closed (1)'), findsOneWidget);
      expect(find.textContaining('Assigned ('), findsNothing);

      await _tapFilter(tester, 'open');
      expect(find.byType(ComplaintListTile), findsNWidgets(2));
      expect(find.text('AC not working'), findsOneWidget);
      expect(find.text('Fan not working'), findsOneWidget);
      expect(find.text('Water leakage'), findsNothing);

      await _tapFilter(tester, 'in_progress');
      expect(find.byType(ComplaintListTile), findsOneWidget);
      expect(find.text('Water leakage'), findsOneWidget);

      await _tapFilter(tester, 'resolved');
      expect(find.byType(ComplaintListTile), findsOneWidget);
      expect(find.text('Door lock issue'), findsOneWidget);
      final selected = tester.widget<Material>(find.descendant(
        of: find.byKey(const Key('complaint-filter-resolved')),
        matching: find.byType(Material),
      ));
      expect(selected.color, ComplaintColors.brand);

      await _tapFilter(tester, 'all');
      expect(find.byType(ComplaintListTile), findsNWidgets(5));
    });

    testWidgets('a filter with no matches says so and keeps the chips',
        (tester) async {
      await _pump(
        tester,
        const ComplaintsListScreen(propertyId: _p1),
        load: () => [_c('x', 'Only open', '05')],
      );
      await tester.pumpAndSettle();
      await _tapFilter(tester, 'resolved');

      expect(find.byKey(const Key('complaints-filter-empty')), findsOneWidget);
      expect(find.text('No resolved complaints'), findsOneWidget);
      expect(find.text('All (1)'), findsOneWidget);
    });

    testWidgets('tapping a row opens Complaint Details, not a status sheet',
        (tester) async {
      await _pump(tester, const ComplaintsListScreen(propertyId: _p1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Water leakage'));
      await tester.pumpAndSettle();

      final details = tester.widget<ComplaintDetailsScreen>(find.byType(ComplaintDetailsScreen));
      expect(details.complaint['id'], 'b');
      expect(find.text('Room 203 · Sky Hostel'), findsOneWidget);
      expect(find.text('Shamirpet, Hyderabad'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('All Complaints'), findsOneWidget);
    });

    testWidgets('fits a small phone', (tester) async {
      await _pump(tester, const ComplaintsListScreen(propertyId: _p1));
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _tapFilter(tester, 'closed');
      expect(find.byType(ComplaintListTile), findsOneWidget);
    });

    testWidgets('loading state', (tester) async {
      final pending = Completer<List<Map<String, dynamic>>>();
      await _pump(tester, const ComplaintsListScreen(propertyId: _p1),
          load: () => pending.future);
      await tester.pump();
      expect(find.byKey(const Key('complaints-loading')), findsOneWidget);
    });

    testWidgets('empty state', (tester) async {
      await _pump(tester, const ComplaintsListScreen(propertyId: _p1), load: () => const []);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('complaints-empty')), findsOneWidget);
      expect(find.text('No complaints yet'), findsOneWidget);
    });

    testWidgets('errors are friendly and Retry reloads', (tester) async {
      var calls = 0;
      await _pump(tester, const ComplaintsListScreen(propertyId: _p1), load: () {
        calls++;
        if (calls == 1) throw _dio(500, 'relation "complaints" does not exist');
        return _complaints;
      });
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('complaints-error')), findsOneWidget);
      expect(find.text("Couldn't load complaints right now. Please try again."), findsOneWidget);
      expect(find.textContaining('relation'), findsNothing);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.byType(ComplaintListTile), findsNWidgets(5));
    });

    testWidgets("another property's complaints (403) are refused without leaking server text",
        (tester) async {
      await _pump(tester, const ComplaintsListScreen(propertyId: _p1),
          load: () => throw _dio(403, 'You do not have access to this property.'));
      await tester.pumpAndSettle();

      expect(find.text("You don't have access to these complaints."), findsOneWidget);
      expect(find.byType(ComplaintListTile), findsNothing);
    });
  });

  group('Complaint Details', () {
    testWidgets('shows status, date, location, photos and fields', (tester) async {
      await _pump(
        tester,
        _details({
          ..._c('c', 'AC not working', '12', category: 'AC / Cooling'),
          'priority': 'high',
          'ticket_number': 'CMP-1234ABCD',
          'photo_urls': ['/uploads/complaints/a.jpg', 'https://cdn.example/b.jpg'],
        }),
      );
      await tester.pumpAndSettle();

      expect(find.text('Complaint Details'), findsOneWidget);
      expect(find.byKey(const Key('complaint-detail-status')), findsOneWidget);
      expect(find.textContaining('12 Oct 2026'), findsWidgets);
      expect(find.text('AC not working'), findsOneWidget);
      expect(find.text('Room 101 · Sky Hostel'), findsOneWidget);
      expect(find.text('Shamirpet, Hyderabad'), findsOneWidget);
      expect(find.text('AC / Cooling'), findsOneWidget);
      expect(find.text('High'), findsOneWidget);
      expect(find.text('CMP-1234ABCD'), findsOneWidget);
      expect(find.byKey(const Key('complaint-photo-0')), findsOneWidget);
      expect(find.byKey(const Key('complaint-photo-1')), findsOneWidget);
      expect(find.text('Complaint raised'), findsOneWidget);
      // Hidden while the server offers no assignment or comments.
      expect(find.text('Assigned To'), findsNothing);
      expect(find.text('Add Comment'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping a photo opens the preview; broken images do not crash',
        (tester) async {
      await _pump(
        tester,
        _details({..._c('c', 'AC not working', '12'), 'photo_urls': ['/uploads/complaints/a.jpg']}),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('complaint-photo-0')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('complaint-photo-preview')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('optional fields are hidden when the API does not provide them',
        (tester) async {
      await _pump(
        tester,
        const ComplaintDetailsScreen(complaint: {'id': 'm', 'status': 'open'}),
      );
      await tester.pumpAndSettle();

      expect(find.text('Complaint'), findsOneWidget);
      expect(find.text('Category'), findsNothing);
      expect(find.text('Priority'), findsNothing);
      expect(find.text('Ticket'), findsNothing);
      expect(find.byKey(const Key('complaint-photo-0')), findsNothing);
      expect(find.byKey(const Key('complaint-resolution-note')), findsNothing);
      // No property id means nothing to update against.
      expect(find.byKey(const Key('complaint-edit')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('long descriptions get a short title plus the full text',
        (tester) async {
      const long = 'The ceiling fan in the room makes a loud grinding noise and '
          'stops working after a few minutes, especially at night.';
      await _pump(tester, _details(_c('l', long, '09')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('complaint-detail-description')), findsOneWidget);
      expect(find.text(long), findsOneWidget);
      final title = tester.widget<Text>(find.byKey(const Key('complaint-detail-title')));
      expect(title.data!.endsWith('…'), isTrue);
    });

    testWidgets('title shortening never splits an emoji', (tester) async {
      final long = '${'a' * 79}😀 then the rest of a long complaint description';
      await _pump(tester, _details(_c('e', long, '09')));
      await tester.pumpAndSettle();

      final title = tester.widget<Text>(find.byKey(const Key('complaint-detail-title')));
      expect(title.data, '${'a' * 79}😀…');
    });

    testWidgets('fits a small phone, including the Edit sheet', (tester) async {
      await _pump(
        tester,
        _details({
          ..._c('s', 'Water leakage near the bathroom door', '10',
              status: 'in_progress', category: 'Plumbing'),
          'ticket_number': 'CMP-1234ABCD',
          'photo_urls': ['/uploads/complaints/a.jpg'],
        }),
      );
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('complaint-edit')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const Key('edit-complaint-save')));
      expect(find.byKey(const Key('edit-complaint-save')), findsOneWidget);
    });

    testWidgets('activity shows real timestamps and the resolution note',
        (tester) async {
      await _pump(
        tester,
        _details({
          ..._c('r', 'Door lock issue', '02', status: 'resolved'),
          'updated_at': '2026-10-04T06:30:00Z',
          'resolution_note': 'Lock replaced.',
        }),
      );
      await tester.pumpAndSettle();

      expect(find.text('Marked Resolved'), findsOneWidget);
      expect(find.textContaining('4 Oct 2026'), findsOneWidget);
      expect(find.text('Lock replaced.'), findsOneWidget);
    });

    for (final role in ['owner', 'admin', 'manager', 'staff']) {
      testWidgets('$role sees Edit', (tester) async {
        await _pump(tester, _details(_c('c', 'AC not working', '12')), role: role);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('complaint-edit')), findsOneWidget);
      });
    }

    for (final role in ['tenant', null]) {
      testWidgets('${role ?? 'unknown role'} does not see Edit or Add Comment',
          (tester) async {
        await _pump(tester, _details(_c('c', 'AC not working', '12')), role: role);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('complaint-edit')), findsNothing);
        expect(find.text('Add Comment'), findsNothing);
        expect(find.text('Add a Reply'), findsNothing);
      });
    }

    testWidgets('Edit updates status through the property-scoped API',
        (tester) async {
      final repo = _FakeRepo();
      await _pump(tester, _details(_c('c', 'AC not working', '12')), repo: repo);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('complaint-edit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edit-status-resolved')));
      await tester.enterText(find.byType(TextField), 'Fixed the AC');
      await tester.tap(find.byKey(const Key('edit-complaint-save')));
      await tester.pumpAndSettle();

      expect(repo.calls, [(_p1, 'c', 'resolved', 'Fixed the AC')]);
      final badge = find.byKey(const Key('complaint-detail-status'));
      expect(find.descendant(of: badge, matching: find.text('Resolved')), findsOneWidget);
      expect(find.text('Fixed the AC'), findsOneWidget);
    });

    testWidgets('a refused update shows a friendly error and keeps the sheet open',
        (tester) async {
      final repo = _FakeRepo()..failWith = _dio(403, 'Requires one of roles: owner, admin');
      await _pump(tester, _details(_c('c', 'AC not working', '12')), repo: repo);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('complaint-edit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edit-status-closed')));
      await tester.tap(find.byKey(const Key('edit-complaint-save')));
      await tester.pumpAndSettle();

      expect(find.text("You don't have permission to update this complaint."), findsOneWidget);
      expect(find.textContaining('Requires one of roles'), findsNothing);
      final badge = find.byKey(const Key('complaint-detail-status'));
      expect(find.descendant(of: badge, matching: find.text('Open')), findsOneWidget);
    });
  });

  group('Assigned To', () {
    const staffId = '31000000-0000-4000-8000-000000000005';
    const managerId = '31000000-0000-4000-8000-000000000004';
    Map<String, dynamic> assigned({bool active = true}) => {
          ..._c('c', 'AC not working', '12'),
          'assigned_to': staffId,
          'assignee_name': 'Sam Staff',
          'assignee_role': active ? 'staff' : null,
          'assignee_active': active,
        };
    final team = [
      {'user_id': managerId, 'name': 'Maya Manager', 'role': 'manager'},
      {'user_id': staffId, 'name': 'Sam Staff', 'role': 'staff'},
    ];

    String assigneeText(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const Key('complaint-assignee'))).data!;

    testWidgets('the team sees the assignee name and role; assigners can change it',
        (tester) async {
      await _pump(tester, _details(assigned()));
      await tester.pumpAndSettle();
      expect(find.text('Assigned To'), findsOneWidget);
      expect(assigneeText(tester), 'Sam Staff · Staff');
      expect(find.byKey(const Key('complaint-assign-change')), findsOneWidget);
      expect(find.text('Change'), findsOneWidget);
      expect(find.byKey(const Key('complaint-assignee-inactive')), findsNothing);
    });

    testWidgets('staff see the assignee but cannot change it', (tester) async {
      await _pump(tester, _details(assigned()), role: 'staff');
      await tester.pumpAndSettle();
      expect(assigneeText(tester), 'Sam Staff · Staff');
      expect(find.byKey(const Key('complaint-assign-change')), findsNothing);
    });

    testWidgets('unassigned complaints offer Assign', (tester) async {
      await _pump(tester, _details({..._c('c', 'AC not working', '12'), 'assigned_to': null}),
          role: 'manager');
      await tester.pumpAndSettle();
      expect(assigneeText(tester), 'Unassigned');
      expect(find.text('Assign'), findsOneWidget);
    });

    testWidgets('a removed member is flagged and reassignment is prompted', (tester) async {
      await _pump(tester, _details(assigned(active: false)));
      await tester.pumpAndSettle();
      expect(assigneeText(tester), 'Sam Staff');
      expect(find.text('No longer on team · reassign'), findsOneWidget);
    });

    testWidgets('tenants only see that the property team has it, never who', (tester) async {
      await _pump(
        tester,
        _details({..._c('c', 'AC not working', '12'), 'is_assigned': true}),
        role: 'tenant',
      );
      await tester.pumpAndSettle();
      expect(assigneeText(tester), 'Assigned to property team');
      expect(find.byKey(const Key('complaint-assign-change')), findsNothing);
      expect(find.textContaining('Sam'), findsNothing);
    });

    testWidgets('a tenant view ignores assignee fields even if present', (tester) async {
      await _pump(
        tester,
        _details({...assigned(), 'is_assigned': false}),
        role: 'tenant',
      );
      await tester.pumpAndSettle();
      expect(assigneeText(tester), 'Not yet assigned');
      expect(find.textContaining('Sam Staff'), findsNothing);
    });

    testWidgets('picking a team member assigns through the property-scoped API',
        (tester) async {
      final repo = _FakeRepo()
        ..assignResult = (id) => {
              'assigned_to': id,
              'assignee_name': 'Maya Manager',
              'assignee_role': 'manager',
              'assignee_active': true,
            };
      await _pump(tester, _details(assigned()), repo: repo, assignees: team);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('complaint-assign-change')));
      await tester.pumpAndSettle();
      expect(find.text('Assign Complaint'), findsOneWidget);
      expect(find.byKey(const Key('assignee-unassign')), findsOneWidget);
      await tester.tap(find.byKey(const Key('assignee-option-$managerId')));
      await tester.pumpAndSettle();

      expect(repo.assignCalls, [(_p1, 'c', managerId)]);
      expect(find.text('Assign Complaint'), findsNothing);
      expect(assigneeText(tester), 'Maya Manager · Manager');
    });

    testWidgets('unassign clears the assignee', (tester) async {
      final repo = _FakeRepo()
        ..assignResult = (_) => {
              'assigned_to': null,
              'assignee_name': null,
              'assignee_role': null,
              'assignee_active': null,
            };
      await _pump(tester, _details(assigned()), repo: repo, assignees: team);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('complaint-assign-change')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('assignee-unassign')));
      await tester.pumpAndSettle();

      expect(repo.assignCalls, [(_p1, 'c', null)]);
      expect(assigneeText(tester), 'Unassigned');
    });

    testWidgets('an ineligible assignee shows a friendly error and keeps the sheet',
        (tester) async {
      final repo = _FakeRepo()..failWith = _dio(422, 'Not an eligible team member');
      await _pump(tester, _details(assigned()), repo: repo, assignees: team);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('complaint-assign-change')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('assignee-option-$managerId')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('assign-error')), findsOneWidget);
      expect(find.textContaining("isn't on this property's team"), findsOneWidget);
      expect(find.textContaining('eligible'), findsNothing);
      expect(find.text('Assign Complaint'), findsOneWidget);
    });
  });

  group('Comments', () {
    final teamComments = [
      {
        'id': 'k1',
        'kind': 'comment',
        'visibility': 'internal',
        'author_role': 'staff',
        'author_name': 'Sam Staff',
        'body': 'Checked wiring',
        'created_at': '2026-10-12T08:00:00Z',
      },
      {
        'id': 'k2',
        'kind': 'assigned',
        'visibility': 'internal',
        'author_role': 'owner',
        'author_name': 'Olivia Owner',
        'meta': {'assignee_name': 'Sam Staff', 'assignee_role': 'staff'},
        'created_at': '2026-10-12T07:00:00Z',
      },
      {
        'id': 'k3',
        'kind': 'comment',
        'visibility': 'tenant_visible',
        'author_role': 'manager',
        'author_name': 'Maya Manager',
        'body': 'Electrician visits tomorrow',
        'created_at': '2026-10-12T09:00:00Z',
      },
    ];
    final tenantComments = [
      {
        'id': 'k3',
        'kind': 'comment',
        'author_role': 'team',
        'body': 'Electrician visits tomorrow',
        'created_at': '2026-10-12T09:00:00Z',
      },
      {
        'id': 'k4',
        'kind': 'comment',
        'author_role': 'tenant',
        'body': 'Thanks',
        'created_at': '2026-10-12T10:00:00Z',
      },
    ];

    double y(WidgetTester tester, String key) => tester.getTopLeft(find.byKey(Key(key))).dy;

    testWidgets('the team sees comments and events in time order, with Internal marked',
        (tester) async {
      await _pump(tester, _details(_c('c', 'AC not working', '12')),
          comments: () => teamComments);
      await tester.pumpAndSettle();

      expect(find.text('Assigned to Sam Staff'), findsOneWidget);
      expect(find.text('Sam Staff · Staff'), findsOneWidget);
      expect(find.text('Checked wiring'), findsOneWidget);
      expect(find.byKey(const Key('comment-internal-k1')), findsOneWidget);
      expect(find.byKey(const Key('comment-internal-k3')), findsNothing);
      final raised = tester.getTopLeft(find.text('Complaint raised')).dy;
      expect(raised, lessThan(y(tester, 'complaint-event-k2')));
      expect(y(tester, 'complaint-event-k2'), lessThan(y(tester, 'complaint-comment-k1')));
      expect(y(tester, 'complaint-comment-k1'), lessThan(y(tester, 'complaint-comment-k3')));
      expect(find.byKey(const Key('complaint-edit')), findsOneWidget);
      expect(find.byKey(const Key('complaint-add-comment')), findsOneWidget);
    });

    testWidgets('tenants see "You" and "Property team", never names or Internal',
        (tester) async {
      await _pump(tester, _details(_c('c', 'AC not working', '12')),
          role: 'tenant', comments: () => tenantComments);
      await tester.pumpAndSettle();

      expect(find.text('Property team'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
      expect(find.text('Internal'), findsNothing);
      expect(find.byKey(const Key('complaint-edit')), findsNothing);
      expect(find.byKey(const Key('complaint-add-comment')), findsOneWidget);
    });

    testWidgets('unavailable comments hide Add Comment and keep Edit', (tester) async {
      await _pump(tester, _details(_c('c', 'AC not working', '12')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('complaint-add-comment')), findsNothing);
      expect(find.byKey(const Key('complaint-edit')), findsOneWidget);
    });

    testWidgets('a failed load offers retry without leaking server text', (tester) async {
      var calls = 0;
      await _pump(tester, _details(_c('c', 'AC not working', '12')), comments: () {
        calls++;
        if (calls == 1) throw _dio(500, 'relation "complaint_comments" does not exist');
        return teamComments;
      });
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('comments-error')), findsOneWidget);
      expect(find.textContaining('relation'), findsNothing);

      await tester.tap(find.descendant(
        of: find.byKey(const Key('comments-error')),
        matching: find.text('Retry'),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Checked wiring'), findsOneWidget);
    });

    testWidgets('team comments are internal unless shared with the tenant', (tester) async {
      final repo = _FakeRepo();
      var loads = 0;
      await _pump(tester, _details(_c('c', 'AC not working', '12')), repo: repo, comments: () {
        loads++;
        return const [];
      });
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('complaint-add-comment')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('comment-share-toggle')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('comment-input')), 'Internal note');
      await tester.tap(find.byKey(const Key('comment-submit')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('complaint-add-comment')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('comment-input')), 'Visit tomorrow');
      await tester.tap(find.byKey(const Key('comment-share-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('comment-submit')));
      await tester.pumpAndSettle();

      expect(repo.commentCalls, [
        (_p1, 'c', 'Internal note', 'internal'),
        (_p1, 'c', 'Visit tomorrow', 'tenant_visible'),
      ]);
      expect(loads, 3);
    });

    testWidgets('tenants comment without a visibility choice', (tester) async {
      final repo = _FakeRepo();
      await _pump(tester, _details(_c('c', 'AC not working', '12')),
          role: 'tenant', repo: repo, comments: () => const []);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('complaint-add-comment')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('comment-share-toggle')), findsNothing);
      await tester.enterText(find.byKey(const Key('comment-input')), 'Please hurry');
      await tester.tap(find.byKey(const Key('comment-submit')));
      await tester.pumpAndSettle();

      expect(repo.commentCalls, [(_p1, 'c', 'Please hurry', null)]);
    });

    testWidgets('empty comments are not sent', (tester) async {
      final repo = _FakeRepo();
      await _pump(tester, _details(_c('c', 'AC not working', '12')),
          repo: repo, comments: () => const []);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('complaint-add-comment')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('comment-input')), '   ');
      await tester.tap(find.byKey(const Key('comment-submit')));
      await tester.pumpAndSettle();

      expect(find.text('Write a comment first.'), findsOneWidget);
      expect(repo.commentCalls, isEmpty);
    });

    testWidgets('a refused comment shows a friendly error', (tester) async {
      final repo = _FakeRepo()..failWith = _dio(403, 'You can only access complaints you raised.');
      await _pump(tester, _details(_c('c', 'AC not working', '12')),
          role: 'tenant', repo: repo, comments: () => const []);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('complaint-add-comment')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('comment-input')), 'Hello');
      await tester.tap(find.byKey(const Key('comment-submit')));
      await tester.pumpAndSettle();

      expect(find.text("You can't comment on this complaint."), findsOneWidget);
      expect(find.textContaining('only access'), findsNothing);
    });

    testWidgets('fits a small phone with both actions and the comment sheet', (tester) async {
      await _pump(
        tester,
        _details({
          ..._c('c', 'AC not working', '12'),
          'assigned_to': 'x',
          'assignee_name': 'A very long team member name for a small phone',
          'assignee_role': 'staff',
          'assignee_active': false,
        }),
        comments: () => teamComments,
      );
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('complaint-add-comment')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const Key('comment-submit')));
      expect(find.byKey(const Key('comment-submit')), findsOneWidget);
    });
  });
}
