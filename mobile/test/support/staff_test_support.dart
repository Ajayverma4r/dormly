// Fakes shared by staff-app widget tests: no network, deterministic data.

import 'package:dio/dio.dart';
import 'package:dormly/features/auth/data/auth_repository.dart';
import 'package:dormly/features/auth/domain/user_profile.dart';
import 'package:dormly/features/auth/presentation/login_flow.dart'
    show otherWorkspacesProvider;
import 'package:dormly/features/complaints/presentation/complaints_list_screen.dart';
import 'package:dormly/features/gate_passes/data/gate_passes_repository.dart';
import 'package:dormly/features/home/presentation/profile_screen.dart'
    show myProfileProvider;
import 'package:dormly/features/notifications/presentation/notifications_providers.dart';
import 'package:dormly/features/staff_home/presentation/staff_ui.dart';
import 'package:dormly/features/structure/domain/hierarchy_level.dart';
import 'package:dormly/features/structure/presentation/property_shell_screen.dart'
    show propertyDetailProvider;
import 'package:dormly/features/structure/presentation/rooms/rooms_tree_provider.dart';
import 'package:dormly/features/tenant_portal/data/tenant_portal_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const staffUserId = 'u-staff';

class FakeAuthRepo implements AuthRepository {
  String? role;
  String? userId;
  FakeAuthRepo(this.role, {this.userId});

  @override
  Future<String?> getContextRole() async => role;

  @override
  Future<String?> getUserId() async => userId;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeGatePassesRepository implements GatePassesRepository {
  final decisions = <(String, String)>[];
  Object? error;
  Future<void>? hold;

  @override
  Future<Map<String, dynamic>> decide(
      String propertyId, String gatePassId, String status) async {
    decisions.add((gatePassId, status));
    if (hold != null) await hold;
    if (error != null) throw error!;
    return {'id': gatePassId, 'status': status};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeTenantPortalRepository implements TenantPortalRepository {
  /// (unitId, readingValue, ratePerUnit) per submit.
  final submitted = <(String, double, double?)>[];

  /// Thrown by the next submit, when set.
  Object? submitError;

  @override
  Future<Map<String, dynamic>> submitMeterReadingForProperty({
    required String propertyId,
    required String unitId,
    required double readingValue,
    String? tenancyId,
    String? billingCycle,
    double? ratePerUnit,
    String? imagePath,
  }) async {
    final error = submitError;
    if (error != null) throw error;
    submitted.add((unitId, readingValue, ratePerUnit));
    return {'id': 'r-new'};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeUnreadCount extends UnreadNotificationsCount {
  @override
  Future<int> build() async => 0;
}

DioException httpError(int? status, {Object? data}) {
  final options = RequestOptions(path: '/v1/test');
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

HierarchyLevel level(String id, String key, String name,
        {String? parent, bool occupancy = false}) =>
    HierarchyLevel(
      id: id,
      propertyId: 'p',
      displayName: name,
      internalKey: key,
      orderIndex: 0,
      isEnabled: true,
      allowMultipleChildren: true,
      supportsOccupancy: occupancy,
      supportsAssets: false,
      supportsComplaints: true,
      parentLevelId: parent,
    );

final _building = level('l-b', 'building', 'Building');
final _floor = level('l-f', 'floor', 'Floor', parent: 'l-b');
final _room = level('l-r', 'room', 'Room', parent: 'l-f');
final _bed = level('l-bed', 'bed', 'Bed', parent: 'l-r', occupancy: true);
final _tower = level('l-t', 'tower', 'Tower');
final _flat = level('l-flat', 'flat', 'Flat', parent: 'l-t', occupancy: true);

RoomsTreeNode _bedNode(String id, bool occupied) => RoomsTreeNode(
      node: {'id': id, 'name': 'Bed $id'},
      level: _bed,
      children: const [],
      occupied: occupied,
      isAssignable: true,
      tenantDisplayName: occupied ? 'Resident $id' : null,
    );

RoomsTreeNode _roomNode(String id, List<bool> beds) {
  final kids = [
    for (var i = 0; i < beds.length; i++) _bedNode('$id-${i + 1}', beds[i])
  ];
  return RoomsTreeNode(
    node: {'id': id, 'name': 'Room $id'},
    level: _room,
    children: kids,
    occupied: beds.any((b) => b),
    isAssignable: false,
    totalBeds: beds.length,
    occupiedBeds: beds.where((b) => b).length,
  );
}

/// Block A › Floor 1 › Room 101 (2 beds, 1 taken), Room 102 (3 beds, all free).
RoomsTree hostelTree() => RoomsTree(
      levels: [_building, _floor, _room, _bed],
      roots: [
        RoomsTreeNode(
          node: const {'id': 'b-a', 'name': 'Block A'},
          level: _building,
          isAssignable: false,
          occupied: true,
          children: [
            RoomsTreeNode(
              node: const {'id': 'f-1', 'name': 'Floor 1'},
              level: _floor,
              isAssignable: false,
              occupied: true,
              children: [
                _roomNode('101', [true, false]),
                _roomNode('102', [false, false, false]),
              ],
            ),
          ],
        ),
      ],
    );

RoomsTreeNode _flatNode(String id, bool occupied) => RoomsTreeNode(
      node: {'id': id, 'name': 'Flat $id'},
      level: _flat,
      children: const [],
      occupied: occupied,
      isAssignable: true,
    );

/// Tower 1 › Flat 1A (occupied), Flat 1B (vacant).
RoomsTree apartmentTree() => RoomsTree(
      levels: [_tower, _flat],
      roots: [
        RoomsTreeNode(
          node: const {'id': 't-1', 'name': 'Tower 1'},
          level: _tower,
          isAssignable: false,
          occupied: true,
          children: [_flatNode('1A', true), _flatNode('1B', false)],
        ),
      ],
    );

/// Overrides for every network-backed provider the staff shell watches.
List<Override> staffOverrides({
  String role = 'staff',
  String typeKey = 'apartment',
  String propertyName = 'Sky Towers',
  String? staffName = 'Ravi Kumar',
  Future<List<Map<String, dynamic>>> Function()? complaints,
  RoomsTree? tree,
  List<Map<String, dynamic>> gatePasses = const [],
  List<Map<String, dynamic>> tenancies = const [],
  List<Map<String, dynamic>> meterReadings = const [],
  FakeGatePassesRepository? gateRepo,
  FakeTenantPortalRepository? portalRepo,
}) =>
    [
      authRepositoryProvider
          .overrideWithValue(FakeAuthRepo(role, userId: staffUserId)),
      complaintsProvider.overrideWith(
          (ref, id) => complaints?.call() ?? Future.value(const [])),
      propertyDetailProvider.overrideWith(
        (ref, id) async =>
            {'id': id, 'name': propertyName, 'property_type_key': typeKey},
      ),
      roomsTreeProvider
          .overrideWith((ref, id) async => tree ?? apartmentTree()),
      myProfileProvider.overrideWith(
        (ref) async => UserProfile(
          id: staffUserId,
          phone: '',
          name: staffName,
          profileComplete: true,
          propertyCount: 0,
        ),
      ),
      unreadNotificationsCountProvider.overrideWith(FakeUnreadCount.new),
      otherWorkspacesProvider.overrideWith((ref) async => const []),
      staffGatePassesProvider.overrideWith((ref, id) async => gatePasses),
      staffTenanciesProvider.overrideWith((ref, id) async => tenancies),
      staffMeterReadingsProvider.overrideWith((ref, id) async => meterReadings),
      gatePassesRepositoryProvider
          .overrideWithValue(gateRepo ?? FakeGatePassesRepository()),
      tenantPortalRepositoryProvider
          .overrideWithValue(portalRepo ?? FakeTenantPortalRepository()),
    ];
