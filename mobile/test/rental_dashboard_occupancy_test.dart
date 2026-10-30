import 'package:dormly/features/complaints/presentation/complaints_list_screen.dart'
    show complaintsProvider;
import 'package:dormly/features/dashboard/domain/property_dashboard.dart';
import 'package:dormly/features/dashboard/presentation/property_dashboard_provider.dart';
import 'package:dormly/features/structure/presentation/dynamic_dashboard/dynamic_dashboard_screen.dart'
    show hierarchyLevelsProvider;
import 'package:dormly/features/structure/presentation/hostel_pg_dashboard_body.dart';
import 'package:dormly/features/structure/presentation/rental_spaces_tab_screen.dart';
import 'package:dormly/features/structure/presentation/rooms/room_list_filter.dart';
import 'package:dormly/features/tenancies/domain/assignable_unit.dart';
import 'package:dormly/features/tenancies/presentation/assignable_units_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _p = 'p1';

const _spaces = [
  AssignableUnit(
    nodeId: 'n1',
    nodeName: 'Ground floor',
    levelName: 'Space',
    pathLabel: 'Ground floor',
    occupied: true,
    tenantName: 'Ravi Kumar',
  ),
  AssignableUnit(
    nodeId: 'n2',
    nodeName: 'First floor',
    levelName: 'Space',
    pathLabel: 'First floor',
    occupied: false,
  ),
];

// Server hero stats as on the reported screen: 1 occupied, no room level, so
// the old room-level count showed "Total Spaces 0".
const _dashboard = PropertyDashboard(
  heroStats: HeroStats(
    totalUnits: 1,
    occupiedUnits: 1,
    availableUnits: 0,
    expectedMonthlyRent: 0,
  ),
  overview: DashboardOverview(
    totalActiveTenants: 1,
    openComplaints: 0,
    totalExpenses: 0,
    rentReceived: 0,
    rentPending: 0,
  ),
  actionableInsights: ActionableInsights(
    defaulters: [],
    pendingKycCount: 0,
    upcomingVacancies: 0,
  ),
);

List<Override> _overrides() => [
      propertyDashboardProvider.overrideWith((ref, id) async => _dashboard),
      hierarchyLevelsProvider.overrideWith((ref, id) async => const []),
      assignableUnitsProvider.overrideWith((ref, id) async => _spaces),
      complaintsProvider.overrideWith((ref, id) async => const []),
      dashboardFinancialsProvider
          .overrideWith((ref, args) => Future.error(StateError('offline'))),
    ];

Finder _stat(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byType(InkWell),
    );

void main() {
  testWidgets(
      'rental dashboard counts spaces from the Spaces list and every stat opens Spaces filtered',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tapped = <RoomListFilter>[];

    await tester.pumpWidget(ProviderScope(
      overrides: _overrides(),
      child: MaterialApp(
        home: HostelPgDashboardBody(
          propertyId: _p,
          propertyName: 'SHYAM HOUSE',
          canManage: true,
          greeting: 'Good afternoon',
          firstName: 'there',
          profile: null,
          notificationCount: 0,
          avatarUrlResolver: (_) => '',
          propertySubtitle: 'Rental house · kompally',
          onNotifications: () {},
          onProfile: () {},
          onRefresh: () async {},
          onOccupancyStatTap: tapped.add,
          unitKind: 'Space',
          containerKind: 'Space',
          countFromSpaces: true,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(
        find.descendant(of: _stat('Occupied Spaces'), matching: find.text('1')),
        findsOneWidget);
    expect(
        find.descendant(of: _stat('Vacant Spaces'), matching: find.text('1')),
        findsOneWidget);
    // The hero stat and the Space Occupancy card both show the list total.
    expect(
        find.descendant(of: _stat('Total Spaces'), matching: find.text('2')),
        findsNWidgets(2));

    await tester.tap(find.text('Occupied Spaces'));
    await tester.tap(find.text('Vacant Spaces'));
    await tester.tap(find.text('Total Spaces').first);
    expect(tapped, [
      RoomListFilter.occupied,
      RoomListFilter.vacant,
      RoomListFilter.all,
    ]);
  });

  testWidgets('Spaces tab opens with the filter chosen on the dashboard',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: _overrides(),
      child: const MaterialApp(
        home: RentalSpacesTabScreen(propertyId: _p, canManage: true),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Ground floor'), findsWidgets);
    expect(find.text('First floor'), findsWidgets);

    final container = ProviderScope.containerOf(
        tester.element(find.byType(RentalSpacesTabScreen)));
    container.read(roomListFilterProvider(_p).notifier).state =
        RoomListFilter.vacant;
    await tester.pumpAndSettle();
    expect(find.text('Ground floor'), findsNothing);
    expect(find.text('First floor'), findsWidgets);

    container.read(roomListFilterProvider(_p).notifier).state =
        RoomListFilter.occupied;
    await tester.pumpAndSettle();
    expect(find.text('Ground floor'), findsWidgets);
    expect(find.text('First floor'), findsNothing);

    // The chips still change the filter, and write it back for the dashboard.
    await tester.tap(find.byKey(const Key('spaces-filter-all')));
    await tester.pumpAndSettle();
    expect(container.read(roomListFilterProvider(_p)), RoomListFilter.all);
    expect(find.text('Ground floor'), findsWidgets);
    expect(find.text('First floor'), findsWidgets);
  });
}
