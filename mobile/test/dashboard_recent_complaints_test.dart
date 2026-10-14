import 'dart:async';

import 'package:dio/dio.dart';
import 'package:dormly/features/complaints/presentation/complaint_details_screen.dart';
import 'package:dormly/features/complaints/presentation/complaint_ui.dart';
import 'package:dormly/features/complaints/presentation/complaints_list_screen.dart';
import 'package:dormly/features/structure/presentation/dashboard_recent_complaints.dart';
import 'package:dormly/features/structure/presentation/property_shell_screen.dart'
    show propertyDetailProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _p1 = '11000000-0000-4000-8000-000000000001';
const _p2 = '12000000-0000-4000-8000-000000000002';

Map<String, dynamic> _c(
  String id,
  String description,
  String createdAt, {
  String status = 'open',
  String? room = 'Room 101',
  String category = 'Electricity',
  String propertyId = _p1,
}) =>
    {
      'id': id,
      'property_id': propertyId,
      'category': category,
      'description': description,
      'status': status,
      if (room != null) 'node_name': room,
      'created_at': createdAt,
    };

final _byProperty = <String, List<Map<String, dynamic>>>{
  _p1: [
    _c('a', 'Oldest', '2026-10-01T04:00:00Z', status: 'resolved'),
    _c('b', 'Fan not working', '2026-10-13T04:00:00Z', status: 'in_progress'),
    _c('c', 'Water leakage', '2026-10-10T04:00:00Z', category: 'Plumbing'),
    _c('d', 'Newest AC issue', '2026-10-14T04:00:00Z', category: 'AC / Cooling'),
  ],
  _p2: [
    _c('x', 'Door lock issue', '2026-10-12T04:00:00Z', room: 'Room 202', propertyId: _p2),
  ],
};

final _properties = {
  _p1: {'id': _p1, 'name': 'Sky Hostel', 'address': 'Shamirpet', 'city': 'Hyderabad'},
  _p2: {'id': _p2, 'name': 'Lake View PG', 'address': 'Madhapur', 'city': 'Hyderabad'},
};

final _selectedProperty = StateProvider<String>((ref) => _p1);

class _Host extends ConsumerWidget {
  const _Host();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: DashboardRecentComplaints(
          propertyId: ref.watch(_selectedProperty),
        ),
      ),
    );
  }
}

Future<(List<String>, ProviderContainer)> _pump(
  WidgetTester tester, {
  FutureOr<List<Map<String, dynamic>>> Function(String propertyId)? load,
}) async {
  final requested = <String>[];
  final container = ProviderContainer(
    overrides: [
      complaintsProvider.overrideWith((ref, propertyId) async {
        requested.add(propertyId);
        return (load ?? (id) => _byProperty[id] ?? const [])(propertyId);
      }),
      complaintViewerRoleProvider.overrideWith((ref) async => 'owner'),
      propertyDetailProvider.overrideWith((ref, id) async => _properties[id]!),
      complaintCommentsProvider.overrideWith((ref, key) async => null),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: _Host()),
    ),
  );
  return (requested, container);
}

void main() {
  test('latestComplaints keeps the three newest by submission time', () {
    final latest = latestComplaints([
      ..._byProperty[_p1]!,
      {'id': 'undated', 'description': 'No date'},
    ]);
    expect(latest.map((c) => c['id']), ['d', 'b', 'c']);
  });

  testWidgets('renders the latest three complaints in order', (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();

    expect(find.text('Recent Complaints'), findsOneWidget);
    expect(find.text('View All →'), findsOneWidget);
    expect(find.text('Oldest'), findsNothing);
    final titles = ['Newest AC issue', 'Fan not working', 'Water leakage'];
    final ys = [for (final t in titles) tester.getTopLeft(find.text(t)).dy];
    expect(ys, orderedEquals([...ys]..sort()));
    expect(find.text('In Progress'), findsOneWidget);
    expect(find.text('Open'), findsNWidgets(2));
    expect(find.textContaining('Room 101 · '), findsNWidgets(3));
  });

  testWidgets('shows only the selected property and refetches on switch',
      (tester) async {
    final (requested, container) = await _pump(tester);
    await tester.pumpAndSettle();
    expect(find.text('Door lock issue'), findsNothing);

    container.read(_selectedProperty.notifier).state = _p2;
    await tester.pumpAndSettle();

    expect(requested, [_p1, _p2]);
    expect(find.text('Door lock issue'), findsOneWidget);
    expect(find.text('Newest AC issue'), findsNothing);
  });

  testWidgets('tapping a complaint opens its details', (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Water leakage'));
    await tester.pumpAndSettle();

    final details = tester.widget<ComplaintDetailsScreen>(
      find.byType(ComplaintDetailsScreen),
    );
    expect(details.complaint['id'], 'c');
    expect(find.text('Complaint Details'), findsOneWidget);
    expect(find.text('Room 101 · Sky Hostel'), findsOneWidget);
    expect(find.text('Shamirpet, Hyderabad'), findsOneWidget);
  });

  testWidgets('details after switching property show the new property only',
      (tester) async {
    final (_, container) = await _pump(tester);
    await tester.pumpAndSettle();
    container.read(_selectedProperty.notifier).state = _p2;
    await tester.pumpAndSettle();

    await tester.tap(find.text('Door lock issue'));
    await tester.pumpAndSettle();

    expect(find.text('Room 202 · Lake View PG'), findsOneWidget);
    expect(find.text('Madhapur, Hyderabad'), findsOneWidget);
    expect(find.textContaining('Sky Hostel'), findsNothing);
  });

  testWidgets('View All opens the complaints list for the property',
      (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('recent-complaints-view-all')));
    await tester.pumpAndSettle();

    final list = tester.widget<ComplaintsListScreen>(
      find.byType(ComplaintsListScreen),
    );
    expect(list.propertyId, _p1);
    expect(find.text('All Complaints'), findsOneWidget);
    expect(find.text('All (4)'), findsOneWidget);
  });

  testWidgets('loading state', (tester) async {
    final pending = Completer<List<Map<String, dynamic>>>();
    await _pump(tester, load: (_) => pending.future);
    await tester.pump();
    expect(find.byKey(const Key('recent-complaints-loading')), findsOneWidget);
  });

  testWidgets('empty state', (tester) async {
    await _pump(tester, load: (_) => const []);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recent-complaints-empty')), findsOneWidget);
    expect(find.text('No complaints yet'), findsOneWidget);
  });

  testWidgets('error shows a friendly message and Retry reloads',
      (tester) async {
    var calls = 0;
    await _pump(tester, load: (id) {
      calls++;
      if (calls == 1) {
        throw DioException(
          requestOptions: RequestOptions(path: '/x'),
          response: Response(
            requestOptions: RequestOptions(path: '/x'),
            statusCode: 500,
            data: {'error': 'relation complaints does not exist'},
          ),
          type: DioExceptionType.badResponse,
        );
      }
      return _byProperty[id]!;
    });
    await tester.pumpAndSettle();

    expect(find.text("Couldn't load complaints right now."), findsOneWidget);
    expect(find.textContaining('relation'), findsNothing);
    expect(find.textContaining('DioException'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Newest AC issue'), findsOneWidget);
  });

  testWidgets('missing room, category or date does not break a row',
      (tester) async {
    await _pump(tester, load: (_) => [
          {'id': 'm', 'status': 'open'},
        ]);
    await tester.pumpAndSettle();
    expect(find.text('Complaint'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
