import 'dart:async';

import 'package:dormly/features/complaints/presentation/complaint_ui.dart';
import 'package:dormly/features/complaints/presentation/complaints_list_screen.dart';
import 'package:dormly/features/staff_home/domain/staff_rooms_summary.dart';
import 'package:dormly/features/staff_home/domain/staff_tasks.dart';
import 'package:dormly/features/staff_home/presentation/staff_gate_passes_screen.dart';
import 'package:dormly/features/staff_home/presentation/staff_meter_readings_screen.dart';
import 'package:dormly/features/staff_home/presentation/staff_shell_screen.dart';
import 'package:dormly/features/staff_home/presentation/staff_tenants_screen.dart';
import 'package:dormly/features/staff_home/presentation/staff_ui.dart';
import 'package:dormly/features/tenant_portal/presentation/owner_mess_menu_screen.dart'
    show messMenuErrorMessage;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/staff_test_support.dart';

const _p = '22000000-0000-4000-8000-000000000002';

Map<String, dynamic> _complaint(
  String id, {
  String status = 'open',
  Object? assignedTo,
  String priority = 'medium',
  String created = '2026-10-10T10:00:00Z',
  String? title,
}) =>
    {
      'id': id,
      'description': title ?? 'Issue $id',
      'status': status,
      'priority': priority,
      'assigned_to': assignedTo,
      'created_at': created,
    };

Future<void> _pump(
    WidgetTester tester, Widget home, List<Override> overrides) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(overrides: overrides, child: MaterialApp(home: home)),
  );
  await tester.pumpAndSettle();
}

Widget _shell() =>
    const StaffShellScreen(propertyId: _p, propertyName: 'Sky Towers');

void main() {
  group('staff task queue', () {
    final complaints = [
      _complaint('other', assignedTo: 'someone-else', priority: 'high'),
      _complaint('free-low', priority: 'low', created: '2026-10-12T10:00:00Z'),
      _complaint('mine-old',
          assignedTo: staffUserId, created: '2026-10-01T10:00:00Z'),
      _complaint('done', status: 'resolved', assignedTo: staffUserId),
      _complaint('free-high',
          priority: 'high', created: '2026-10-02T10:00:00Z'),
      _complaint('mine-new',
          assignedTo: staffUserId,
          status: 'in_progress',
          created: '2026-10-11T10:00:00Z'),
    ];

    test('mine first, then unassigned by priority; resolved work is excluded',
        () {
      final ids =
          staffTaskQueue(complaints, staffUserId).map((c) => c['id']).toList();
      expect(ids, ['mine-new', 'mine-old', 'free-high', 'free-low', 'other']);
    });

    test('counts active complaints and the ones assigned to me', () {
      final counts = staffComplaintCounts(complaints, staffUserId);
      expect(counts.active, 5);
      expect(counts.mine, 2);
      expect(staffComplaintCounts(complaints, null).mine, 0);
    });

    test('assignment labels only when the server reports assignment', () {
      expect(complaintAssignmentLabel({'id': 'x'}, staffUserId), isNull);
      expect(complaintAssignmentLabel({'assigned_to': null}, staffUserId),
          ('Unassigned', false));
      expect(
          complaintAssignmentLabel({'assigned_to': staffUserId}, staffUserId),
          ('Assigned to you', true));
      expect(
        complaintAssignmentLabel(
            {'assigned_to': 'x', 'assignee_name': 'Mohan'}, staffUserId),
        ('Assigned to Mohan', false),
      );
    });
  });

  group('rooms summary', () {
    test('hostel counts rooms and beds with building/floor path', () {
      final s = summarizeRooms(hostelTree());
      expect(s.totalRooms, 2);
      expect(s.totalBeds, 5);
      expect(s.occupiedBeds, 1);
      expect(s.vacantBeds, 4);
      expect(s.usesBeds, isTrue);
      expect(s.buildings, ['Block A']);
      expect(s.rooms.first.section, 'Block A · Floor 1');
      expect(s.rooms.first.beds.length, 2);
    });

    test('apartments count whole units', () {
      final s = summarizeRooms(apartmentTree());
      expect(s.totalRooms, 2);
      expect(s.totalBeds, 0);
      expect(s.usesBeds, isFalse);
      expect(s.occupiedRooms, 1);
    });
  });

  group('meter readings and errors', () {
    test('a reading must be a positive number not below the previous one', () {
      expect(validateMeterReading('', 10), isNotNull);
      expect(validateMeterReading('abc', 10), isNotNull);
      expect(validateMeterReading('0', null), isNotNull);
      expect(validateMeterReading('9.5', 10), contains('previous reading'));
      expect(validateMeterReading('10', 10), isNull);
      expect(validateMeterReading('125.5', null), isNull);
    });

    test('latest reading per unit keeps the newest row', () {
      final latest = latestReadingByUnit([
        {'unit_id': 'u1', 'meter_reading_value': 200},
        {'unit_id': 'u1', 'meter_reading_value': 150},
        {'unit_id': 'u2', 'meter_reading_value': 80},
      ]);
      expect(latest['u1']!['meter_reading_value'], 200);
      expect(latest.length, 2);
    });

    test('friendly messages never echo server or Dio text', () {
      expect(
          staffErrorMessage(httpError(401)), contains('session has expired'));
      expect(staffErrorMessage(httpError(403)),
          "Your staff role doesn't include this action.");
      expect(staffErrorMessage(httpError(null)),
          contains('Could not reach the server'));
      expect(staffErrorMessage(httpError(500), fallback: 'Try again'),
          'Try again');
      expect(
          staffErrorMessage(StateError('secret db detail'),
              fallback: 'Try again'),
          'Try again');
      expect(messMenuErrorMessage(httpError(403), fallback: 'x'),
          contains("don't have access"));
      expect(messMenuErrorMessage(httpError(500), fallback: 'x'), 'x');
    });

    test('meter validation codes map to app wording, never the server text',
        () {
      rejected(String code) =>
          httpError(400, data: {'error': 'server detail $code', 'code': code});
      for (final code in [
        'invalid_reading',
        'reading_below_previous',
        'amount_out_of_range',
        'invalid_rate',
      ]) {
        final text = meterReadingErrorMessage(rejected(code));
        expect(text, isNot(contains('server detail')));
        expect(text, isNot(contains(code)));
      }
      expect(meterReadingErrorMessage(rejected('reading_below_previous')),
          contains('lower than the latest one'));
      expect(meterReadingErrorMessage(rejected('invalid_reading')),
          'Enter a reading greater than 0.');
      // Unknown codes, other bodies and other statuses fall back safely.
      expect(meterReadingErrorMessage(rejected('sql_error')),
          'Could not save the reading. Please try again.');
      expect(
          meterReadingErrorMessage(
              httpError(400, data: 'Validation failed: secret')),
          'Could not save the reading. Please try again.');
      expect(
          meterReadingErrorMessage(httpError(500, data: {
            'code': 'invalid_reading',
          })),
          'Could not save the reading. Please try again.');
      expect(meterReadingErrorMessage(httpError(403)),
          "Your staff role doesn't include this action.");
    });

    test('gate pass statuses map to the three tabs', () {
      expect(gatePassTabOf({'status': 'pending'}), GatePassTab.pending);
      expect(gatePassTabOf({}), GatePassTab.pending);
      expect(gatePassTabOf({'status': 'approved'}), GatePassTab.approved);
      expect(gatePassTabOf({'status': 'denied'}), GatePassTab.rejected);
      expect(gatePassTabOf({'status': 'expired'}), GatePassTab.rejected);
    });
  });

  group('staff shell', () {
    testWidgets('shows the five staff tabs and a real-data home',
        (tester) async {
      await _pump(
        tester,
        _shell(),
        staffOverrides(
          complaints: () async => [
            _complaint('c1', assignedTo: staffUserId, title: 'Leaking tap'),
            _complaint('c2', assignedTo: null, title: 'Broken fan'),
            _complaint('c3', status: 'resolved', assignedTo: staffUserId),
          ],
        ),
      );

      for (final label in [
        'Home',
        'Complaints',
        'Rooms',
        'Gate Passes',
        'More'
      ]) {
        expect(
            find.descendant(
                of: find.byType(NavigationBar), matching: find.text(label)),
            findsOneWidget);
      }
      expect(find.byKey(const Key('staff-greeting-name')), findsOneWidget);
      expect(find.text('Ravi Kumar'), findsWidgets);
      expect(find.byKey(const Key('staff-property-name')), findsOneWidget);
      expect(find.text('Staff'), findsWidgets);

      String value(String key) => tester
          .widget<Text>(find.byKey(Key('staff-summary-$key-value')))
          .data!;
      expect(value('open'), '2');
      expect(value('mine'), '1');
      expect(value('rooms'), '2');
      expect(value('beds'), '1', reason: 'apartments show occupied units');

      expect(find.byKey(const Key('staff-task-c1')), findsOneWidget);
      expect(find.byKey(const Key('staff-task-c2')), findsOneWidget);
      expect(find.byKey(const Key('staff-task-c3')), findsNothing);
      expect(find.text('Assigned to you'), findsOneWidget);
    });

    testWidgets('home fits a phone screen without overflow', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: staffOverrides(
            typeKey: 'apartment',
            complaints: () async => [
              _complaint('c1',
                  assignedTo: staffUserId,
                  priority: 'high',
                  title: 'Water leaking from bathroom ceiling'),
              _complaint('c2', title: 'Fan not working'),
            ],
          ),
          child: MaterialApp(home: _shell()),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('staff-home')), findsOneWidget);
    });

    testWidgets('hostel summary shows beds and hostel-only shortcuts',
        (tester) async {
      await _pump(tester, _shell(),
          staffOverrides(typeKey: 'hostel_pg', tree: hostelTree()));

      expect(
          tester
              .widget<Text>(find.byKey(const Key('staff-summary-beds-value')))
              .data,
          '5');
      expect(find.byKey(const Key('staff-action-Mess Menu')), findsOneWidget);
      expect(find.byKey(const Key('staff-action-Gate Passes')), findsNothing);
      expect(
          find.byKey(const Key('staff-action-Meter Readings')), findsNothing);
    });

    testWidgets(
        'apartment shortcuts show gate passes and meters, not mess menu',
        (tester) async {
      await _pump(tester, _shell(), staffOverrides(typeKey: 'apartment'));

      expect(find.byKey(const Key('staff-action-Gate Passes')), findsOneWidget);
      expect(
          find.byKey(const Key('staff-action-Meter Readings')), findsOneWidget);
      expect(find.byKey(const Key('staff-action-Mess Menu')), findsNothing);
    });

    testWidgets('an empty task list explains itself', (tester) async {
      await _pump(tester, _shell(), staffOverrides());
      expect(find.byKey(const Key('staff-tasks-empty')), findsOneWidget);
    });

    testWidgets('a failed task list shows a friendly error and retry',
        (tester) async {
      await _pump(tester, _shell(),
          staffOverrides(complaints: () => Future.error(httpError(403))));
      expect(find.byKey(const Key('staff-tasks-error')), findsOneWidget);
      expect(find.text("Your staff role doesn't include this action."),
          findsOneWidget);
      expect(find.text('Retry'), findsWidgets);
    });

    testWidgets('switching tabs keeps each tab state', (tester) async {
      await _pump(
        tester,
        _shell(),
        staffOverrides(
          complaints: () async => [
            _complaint('c1', assignedTo: staffUserId),
            _complaint('c2', status: 'resolved'),
          ],
        ),
      );
      final nav = find.byType(NavigationBar);
      await tester
          .tap(find.descendant(of: nav, matching: find.text('Complaints')));
      await tester.pumpAndSettle();
      await tester
          .ensureVisible(find.byKey(const Key('complaint-filter-resolved')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('complaint-filter-resolved')));
      await tester.pumpAndSettle();
      expect(find.text('Issue c1'), findsNothing);

      await tester.tap(find.descendant(of: nav, matching: find.text('Home')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.descendant(of: nav, matching: find.text('Complaints')));
      await tester.pumpAndSettle();
      expect(find.text('Issue c2'), findsOneWidget);
      expect(find.text('Issue c1'), findsNothing,
          reason: 'filter survived the tab switch');
    });

    testWidgets('More has staff tools and no billing or subscription entries',
        (tester) async {
      await _pump(tester, _shell(),
          staffOverrides(typeKey: 'hostel_pg', tree: hostelTree()));
      await tester.tap(find.descendant(
          of: find.byType(NavigationBar), matching: find.text('More')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('staff-more-mess-menu')), findsOneWidget);
      expect(find.byKey(const Key('staff-more-meter-readings')), findsNothing);
      expect(find.byKey(const Key('staff-more-tenants')), findsOneWidget);
      expect(find.byKey(const Key('staff-more-logout')), findsOneWidget);
      for (final word in [
        'Billing',
        'Payments',
        'Subscription',
        'Plan',
        'Staff management',
        'Expenses'
      ]) {
        expect(find.textContaining(word), findsNothing,
            reason: '$word must not be offered to staff');
      }
    });
  });

  group('complaints list for staff', () {
    testWidgets('My Tasks filter shows only complaints assigned to me',
        (tester) async {
      await _pump(
        tester,
        const ComplaintsListScreen(propertyId: _p, asTab: true),
        staffOverrides(
          complaints: () async => [
            _complaint('c1', assignedTo: staffUserId),
            _complaint('c2', assignedTo: null),
          ],
        ),
      );
      expect(find.text('Issue c2'), findsOneWidget);
      expect(find.text('Unassigned'), findsOneWidget);

      await tester.tap(find.byKey(const Key('complaint-filter-mine')));
      await tester.pumpAndSettle();
      expect(find.text('Issue c1'), findsOneWidget);
      expect(find.text('Issue c2'), findsNothing);
    });

    testWidgets('managers keep the original list without My Tasks',
        (tester) async {
      await _pump(
        tester,
        const ComplaintsListScreen(propertyId: _p),
        staffOverrides(
            role: 'manager',
            complaints: () async => [_complaint('c1', assignedTo: 'x')]),
      );
      expect(find.byKey(const Key('complaint-filter-mine')), findsNothing);
      expect(find.byKey(const Key('complaint-assignment')), findsNothing);
    });

    testWidgets('empty state offers a refresh', (tester) async {
      await _pump(
          tester,
          const ComplaintsListScreen(propertyId: _p, asTab: true),
          staffOverrides());
      expect(find.byKey(const Key('complaints-empty')), findsOneWidget);
      expect(find.byKey(const Key('complaints-empty-refresh')), findsOneWidget);
    });
  });

  group('gate passes', () {
    final pending = {
      'id': 'gp1',
      'status': 'pending',
      'visitor_name': 'Asha',
      'purpose': 'delivery',
      'unit_name': 'Flat 1A',
      'requested_by_name': 'Neha',
      'created_at': '2026-10-14T09:00:00Z',
    };

    testWidgets('approving calls the server once even on double tap',
        (tester) async {
      final repo = FakeGatePassesRepository()..hold = Completer<void>().future;
      await _pump(
        tester,
        const StaffGatePassesScreen(propertyId: _p),
        staffOverrides(gatePasses: [pending], gateRepo: repo),
      );
      expect(find.text('Asha'), findsOneWidget);
      expect(find.text('Flat 1A'), findsOneWidget);

      await tester.tap(find.byKey(const Key('gate-pass-approve-gp1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('gate-pass-approve-gp1')),
          warnIfMissed: false);
      await tester.pump();
      expect(repo.decisions, [('gp1', 'approved')]);
    });

    testWidgets('a 403 shows a friendly message', (tester) async {
      final repo = FakeGatePassesRepository()..error = httpError(403);
      await _pump(
        tester,
        const StaffGatePassesScreen(propertyId: _p),
        staffOverrides(gatePasses: [pending], gateRepo: repo),
      );
      await tester.tap(find.byKey(const Key('gate-pass-reject-gp1')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Reject'));
      await tester.pumpAndSettle();
      expect(repo.decisions, [('gp1', 'denied')]);
      expect(find.text("Your staff role doesn't include this action."),
          findsOneWidget);
    });

    testWidgets('tabs split approved and rejected passes', (tester) async {
      await _pump(
        tester,
        const StaffGatePassesScreen(propertyId: _p),
        staffOverrides(gatePasses: [
          pending,
          {'id': 'gp2', 'status': 'approved', 'visitor_name': 'Ram'},
          {'id': 'gp3', 'status': 'denied', 'visitor_name': 'Shyam'},
        ]),
      );
      expect(find.text('Ram'), findsNothing);
      await tester.tap(find.byKey(const Key('gate-pass-tab-rejected')));
      await tester.pumpAndSettle();
      expect(find.text('Shyam'), findsOneWidget);
      expect(find.byKey(const Key('gate-pass-approve-gp3')), findsNothing);
    });

    testWidgets('hostels explain that gate passes are not used',
        (tester) async {
      await _pump(
        tester,
        const StaffGatePassesScreen(propertyId: _p),
        staffOverrides(typeKey: 'hostel_pg'),
      );
      expect(find.byKey(const Key('staff-gate-passes-unsupported')),
          findsOneWidget);
    });
  });

  group('limited screens', () {
    testWidgets('tenant list shows name, room and status only', (tester) async {
      await _pump(
        tester,
        const StaffTenantsScreen(propertyId: _p),
        staffOverrides(tenancies: [
          {
            'id': 't1',
            'full_name': 'Priya Shah',
            'floor_name': 'Tower 1',
            'node_name': 'Flat 1A',
            'status': 'active',
            'email': 'priya@example.com',
          },
          {'id': 't2', 'user_name': 'Old Tenant', 'status': 'ended'},
        ]),
      );
      expect(find.text('Priya Shah'), findsOneWidget);
      expect(find.text('Tower 1 · Flat 1A'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('priya@example.com'), findsNothing);
      expect(find.text('Old Tenant'), findsNothing,
          reason: 'current residents by default');
    });

    testWidgets(
        'meter reading below the previous one is rejected without a request',
        (tester) async {
      final portal = FakeTenantPortalRepository();
      await _pump(
        tester,
        const StaffMeterReadingsScreen(propertyId: _p),
        staffOverrides(
          portalRepo: portal,
          meterReadings: [
            {
              'unit_id': '1A',
              'meter_reading_value': 500,
              'created_at': '2026-10-01T10:00:00Z'
            },
          ],
        ),
      );
      expect(find.byKey(const Key('staff-meter-last-1A')), findsOneWidget);

      await tester.tap(find.byKey(const Key('staff-meter-enter-1A')));
      await tester.pumpAndSettle();
      expect(find.text('Previous reading: 500'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('staff-meter-input')), '450');
      await tester.tap(find.byKey(const Key('staff-meter-save')));
      await tester.pumpAndSettle();
      expect(
          find.textContaining('at least the previous reading'), findsOneWidget);
      expect(portal.submitted, isEmpty);

      await tester.enterText(find.byKey(const Key('staff-meter-input')), '520');
      await tester.tap(find.byKey(const Key('staff-meter-save')));
      await tester.pumpAndSettle();
      expect(portal.submitted, [('1A', 520.0, null)]);
      expect(find.text('Reading saved for Flat 1A'), findsOneWidget);
    });

    testWidgets(
        'a server-side rejection shows the app message and keeps the sheet open',
        (tester) async {
      final portal = FakeTenantPortalRepository()
        ..submitError = httpError(400, data: {
          'error': 'Reading cannot be less than the previous reading (530).',
          'code': 'reading_below_previous',
        });
      await _pump(
        tester,
        const StaffMeterReadingsScreen(propertyId: _p),
        staffOverrides(
          portalRepo: portal,
          meterReadings: [
            {
              'unit_id': '1A',
              'meter_reading_value': 500,
              'created_at': '2026-10-01T10:00:00Z'
            },
          ],
        ),
      );

      await tester.tap(find.byKey(const Key('staff-meter-enter-1A')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('staff-meter-input')), '520');
      await tester.tap(find.byKey(const Key('staff-meter-save')));
      await tester.pumpAndSettle();

      expect(find.textContaining('lower than the latest one'), findsOneWidget);
      expect(find.textContaining('cannot be less'), findsNothing);
      expect(find.textContaining('reading_below_previous'), findsNothing);
      expect(find.byKey(const Key('staff-meter-input')), findsOneWidget);
      expect(find.text('Reading saved for Flat 1A'), findsNothing);
    });

    testWidgets('meters are hidden for hostels', (tester) async {
      await _pump(
        tester,
        const StaffMeterReadingsScreen(propertyId: _p),
        staffOverrides(typeKey: 'hostel_pg'),
      );
      expect(find.byKey(const Key('staff-meters-unsupported')), findsOneWidget);
    });
  });
}
