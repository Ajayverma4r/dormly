import 'package:dormly/features/structure/domain/hierarchy_level.dart';
import 'package:dormly/features/structure/presentation/dynamic_dashboard/dynamic_dashboard_screen.dart'
    show contextRoleProvider;
import 'package:dormly/features/structure/presentation/rooms/rooms_tree_provider.dart';
import 'package:dormly/features/tenancies/presentation/room_beds_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

HierarchyLevel _level(String id, String name, String key,
        {String? parent, bool occupancy = false}) =>
    HierarchyLevel(
      id: id,
      propertyId: 'p1',
      displayName: name,
      internalKey: key,
      orderIndex: 0,
      isEnabled: true,
      allowMultipleChildren: true,
      supportsOccupancy: occupancy,
      supportsAssets: false,
      supportsComplaints: false,
      parentLevelId: parent,
    );

final _roomLevel = _level('lr', 'Room', 'room');
final _bedLevel = _level('lb', 'Bed', 'bed', parent: 'lr', occupancy: true);

RoomsTree _tree(List<RoomsTreeNode> beds) {
  final occupied = beds.where((b) => b.occupied).length;
  return RoomsTree(
    levels: [_roomLevel, _bedLevel],
    roots: [
      RoomsTreeNode(
        node: const {'id': 'room1', 'name': 'G01'},
        level: _roomLevel,
        children: beds,
        occupied: occupied > 0,
        isAssignable: false,
        totalBeds: beds.length,
        occupiedBeds: occupied,
      ),
    ],
  );
}

RoomsTreeNode _bed(String id, String name, {String? tenant}) => RoomsTreeNode(
      node: {'id': id, 'name': name},
      level: _bedLevel,
      children: const [],
      occupied: tenant != null,
      isAssignable: true,
      tenantDisplayName: tenant,
    );

Future<void> _pump(WidgetTester tester, RoomsTree tree, String role) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        roomsTreeProvider.overrideWith((ref, _) async => tree),
        contextRoleProvider.overrideWith((ref) async => role),
      ],
      child: MaterialApp(
        home: RoomBedsScreen(
          propertyId: 'p1',
          nodeId: 'room1',
          nodeName: 'G01',
          level: _roomLevel,
          levels: [_roomLevel, _bedLevel],
          onRename: () {},
          onDelete: () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('lists real beds with occupancy and tenant names',
      (tester) async {
    await _pump(
      tester,
      _tree([_bed('b1', 'A', tenant: 'Ravi Kumar'), _bed('b2', 'B')]),
      'owner',
    );
    await tester.pumpAndSettle();

    expect(find.text('Room G01'), findsOneWidget);
    expect(find.text('1/2 beds occupied'), findsOneWidget);
    expect(find.text('Occupied 1/2'), findsOneWidget);
    expect(find.text('Bed A'), findsOneWidget);
    expect(find.text('Ravi Kumar'), findsOneWidget);
    expect(find.text('Bed B'), findsOneWidget);
    expect(find.text('No tenant assigned'), findsOneWidget);
    expect(find.text('Assign Tenant'), findsOneWidget);
    expect(find.textContaining('Assign tenants to a specific'), findsNothing);
  });

  testWidgets('hides manage actions for non-manager roles', (tester) async {
    await _pump(tester, _tree([_bed('b2', 'B')]), 'tenant');
    await tester.pumpAndSettle();

    expect(find.text('Bed B'), findsOneWidget);
    expect(find.text('Assign Tenant'), findsNothing);
    expect(find.text('Add Bed'), findsNothing);
  });

  testWidgets('shows empty state with Add Bed when room has no beds',
      (tester) async {
    await _pump(tester, _tree(const []), 'manager');
    await tester.pumpAndSettle();

    expect(find.text('No beds in this room yet'), findsOneWidget);
    expect(find.text('Add Bed'), findsOneWidget);
  });
}
