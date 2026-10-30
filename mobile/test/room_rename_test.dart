import 'package:dio/dio.dart';
import 'package:dormly/features/properties/domain/property_setup_state.dart';
import 'package:dormly/features/structure/data/structure_repository.dart';
import 'package:dormly/features/structure/domain/hierarchy_level.dart';
import 'package:dormly/features/structure/presentation/hostel_pg_rooms_body.dart';
import 'package:dormly/features/structure/presentation/property_shell_screen.dart'
    show propertyDetailProvider;
import 'package:dormly/features/structure/presentation/rename_node_dialog.dart';
import 'package:dormly/features/structure/presentation/rooms/rooms_tree_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _duplicateMessage =
    'A Room named "G02" already exists in Floor 1. Choose a different name.';

DioException _conflict(String message) {
  final options = RequestOptions(path: '/v1/properties/p1/structure/nodes/x');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response(
      requestOptions: options,
      statusCode: 409,
      data: {'error': message},
    ),
  );
}

class _FakeStructureRepository implements StructureRepository {
  final renames = <(String, String, String)>[];
  Object? failWith;

  @override
  Future<Map<String, dynamic>> renameNode(
      String propertyId, String nodeId, String name) async {
    final error = failWith;
    if (error != null) throw error;
    renames.add((propertyId, nodeId, name));
    return {'id': nodeId, 'name': name};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

// One room, one of its two beds occupied.
RoomsTree _tree(String roomName) => RoomsTree(
      levels: [_roomLevel, _bedLevel],
      roots: [
        RoomsTreeNode(
          node: {'id': 'room1', 'name': roomName},
          level: _roomLevel,
          occupied: true,
          isAssignable: false,
          totalBeds: 2,
          occupiedBeds: 1,
          children: [
            RoomsTreeNode(
              node: const {'id': 'b1', 'name': 'A'},
              level: _bedLevel,
              children: const [],
              occupied: true,
              isAssignable: true,
              tenantDisplayName: 'Ravi Kumar',
            ),
            RoomsTreeNode(
              node: const {'id': 'b2', 'name': 'B'},
              level: _bedLevel,
              children: const [],
              occupied: false,
              isAssignable: true,
            ),
          ],
        ),
      ],
    );

void main() {
  group('node name rules', () {
    test('normalizes spacing and compares names ignoring case', () {
      expect(normalizeNodeName('  Room   101 '), 'Room 101');
      expect(nodeNameKey('ROOM 101'), nodeNameKey(' room  101'));
    });

    test('reports clashes with existing names and within the new batch', () {
      expect(
        findNodeNameClashes(['101', 'Room 102'], ['100', ' 101', '103', '103']),
        ['101', '103'],
      );
      expect(findNodeNameClashes(['101'], ['102', '104']), isEmpty);
    });

    test('a bare number and "Room <number>" are the same room', () {
      expect(nodeDisplayLabel('109', 'Room'), 'Room 109');
      expect(nodeDisplayLabel('Room 109', 'Room'), 'Room 109');
      expect(nodeDisplayLabel('Deluxe Room', 'Room'), 'Deluxe Room');
      expect(nodeNameKey('109', 'Room'), nodeNameKey('room 109', 'Room'));
      expect(
        findNodeNameClashes(['Room 101', '102'], ['101', 'Room 102', '103'],
            levelName: 'Room'),
        ['101', 'Room 102'],
      );
    });
  });

  group('wizard duplicate checks', () {
    SetupRentalSpace space(String id, String name, {String? floor}) =>
        SetupRentalSpace(
          id: id,
          name: name,
          type: RentalSpaceType.room,
          floorLabel: floor,
          monthlyRent: 5000,
        );

    test('rental spaces must be unique on the same floor only', () {
      expect(
        duplicateRentalSpaceNames([
          space('a', 'Room 1', floor: 'Ground'),
          space('b', 'room 1 ', floor: 'ground'),
        ]),
        ['room 1'],
      );
      expect(
        duplicateRentalSpaceNames([
          space('a', 'Room 1', floor: 'Ground'),
          space('b', 'Room 1', floor: 'First'),
        ]),
        isEmpty,
      );
      // Floors are created at the top level next to unfloored spaces.
      expect(
        duplicateRentalSpaceNames([
          space('a', 'Room 1', floor: 'Shop'),
          space('b', 'Shop'),
        ]),
        ['Shop'],
      );
    });

    test('custom hostel room names must be unique per floor', () {
      const building = SetupBuilding(id: 'b', name: 'Main', floorCount: 2);
      PropertySetupState setup(List<String> ground, List<String> first) =>
          PropertySetupState(
            structurePreset: OrgStructurePreset.singleBuilding,
            roomNaming: RoomNamingPreference.custom,
            buildings: const [building],
            floorPlans: {
              'b:0': SetupFloorPlan(
                buildingId: 'b',
                floorIndex: 0,
                roomCount: ground.length,
                customRoomNames: ground,
              ),
              'b:1': SetupFloorPlan(
                buildingId: 'b',
                floorIndex: 1,
                roomCount: first.length,
                customRoomNames: first,
              ),
            },
          );

      expect(duplicateStructureNames(setup(['A', 'B'], ['A', 'B'])), isEmpty);
      expect(duplicateStructureNames(setup(['A', 'a'], ['C'])), ['a']);
    });
  });

  group('rename dialog', () {
    testWidgets('shows the server duplicate error inline and stays open',
        (tester) async {
      String? result = 'not closed';
      final submitted = <String>[];
      var fail = true;

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showRenameNodeDialog(
                context: context,
                currentName: 'G01',
                kind: 'Room',
                onSubmit: (name) async {
                  submitted.add(name);
                  if (fail) throw _conflict(_duplicateMessage);
                },
              );
            },
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Rename Room'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('rename-node-field')), '  G02 ');
      await tester.tap(find.byKey(const Key('rename-node-save')));
      await tester.pumpAndSettle();

      expect(submitted, ['G02']);
      expect(find.text(_duplicateMessage), findsOneWidget);
      expect(find.text('Rename Room'), findsOneWidget);
      expect(result, 'not closed');

      fail = false;
      await tester.enterText(find.byKey(const Key('rename-node-field')), 'G03');
      await tester.pumpAndSettle();
      expect(find.text(_duplicateMessage), findsNothing);
      expect(find.text('Shows as "Room G03"'), findsOneWidget);
      await tester.tap(find.byKey(const Key('rename-node-save')));
      await tester.pumpAndSettle();

      expect(submitted, ['G02', 'G03']);
      expect(find.text('Rename Room'), findsNothing);
      expect(result, 'G03');
    });

    testWidgets('refuses an empty name without calling the server',
        (tester) async {
      final submitted = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RenameNodeDialog(
            currentName: 'G01',
            onSubmit: (name) async => submitted.add(name),
          ),
        ),
      ));
      await tester.enterText(find.byKey(const Key('rename-node-field')), '   ');
      await tester.tap(find.byKey(const Key('rename-node-save')));
      await tester.pump();

      expect(find.text('Name cannot be empty.'), findsOneWidget);
      expect(submitted, isEmpty);
    });
  });

  group('Rooms list', () {
    // What the server returns for the room on the next tree load.
    var roomName = 'G01';
    setUp(() => roomName = 'G01');

    Future<_FakeStructureRepository> pump(WidgetTester tester,
        {required bool canManage}) async {
      final repo = _FakeStructureRepository();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          structureRepositoryProvider.overrideWithValue(repo),
          roomsTreeProvider.overrideWith((ref, _) async => _tree(roomName)),
          propertyDetailProvider.overrideWith(
              (ref, _) async => {'property_type_key': 'hostel_pg'}),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: HostelPgRoomsBody(propertyId: 'p1', canManage: canManage),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('a manager can rename an occupied room from its card menu',
        (tester) async {
      final repo = await pump(tester, canManage: true);
      expect(find.text('Room G01'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('Rename room'), findsOneWidget);
      await tester.tap(find.text('Rename room'));
      await tester.pumpAndSettle();

      repo.failWith = _conflict(_duplicateMessage);
      await tester.enterText(find.byKey(const Key('rename-node-field')), 'G02');
      await tester.tap(find.byKey(const Key('rename-node-save')));
      await tester.pumpAndSettle();
      expect(find.text(_duplicateMessage), findsOneWidget);
      expect(repo.renames, isEmpty);

      repo.failWith = null;
      roomName = 'Deluxe 1';
      await tester.enterText(
          find.byKey(const Key('rename-node-field')), 'Deluxe   1');
      await tester.tap(find.byKey(const Key('rename-node-save')));
      await tester.pumpAndSettle();

      expect(repo.renames, [('p1', 'room1', 'Deluxe 1')]);
      expect(find.text('Room renamed to "Deluxe 1".'), findsOneWidget);
      expect(find.text('Room Deluxe 1'), findsOneWidget);
    });

    testWidgets('changes the room number, Room 108 to Room 109',
        (tester) async {
      roomName = '108';
      final repo = await pump(tester, canManage: true);
      expect(find.text('Room 108'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename room'));
      await tester.pumpAndSettle();
      expect(find.text('Room name or number'), findsOneWidget);
      expect(find.text('Shows as "Room 108"'), findsOneWidget);

      roomName = '109';
      await tester.enterText(find.byKey(const Key('rename-node-field')), '109');
      await tester.pump();
      expect(find.text('Shows as "Room 109"'), findsOneWidget);
      await tester.tap(find.byKey(const Key('rename-node-save')));
      await tester.pumpAndSettle();

      expect(repo.renames, [('p1', 'room1', '109')]);
      expect(find.text('Room 109'), findsOneWidget);
      expect(find.text('Room 108'), findsNothing);
    });

    testWidgets('staff without manage rights do not see Rename',
        (tester) async {
      await pump(tester, canManage: false);
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('View room'), findsOneWidget);
      expect(find.text('Rename room'), findsNothing);
    });
  });
}
