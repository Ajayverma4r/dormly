// features/properties/domain/property_setup_state.dart
//
// Local progressive-disclosure state for the property onboarding wizard.
// Held in memory until the final create API call.

import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'property_archetype.dart';

enum OrgStructurePreset {
  multipleBuildings,
  singleBuilding,
  roomsAndBeds,
}

enum RoomNamingPreference { automatic, custom }

String _newId() =>
    '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 32)}';

class SetupBuilding {
  final String id;
  final String name;
  final int floorCount;

  const SetupBuilding({
    required this.id,
    required this.name,
    required this.floorCount,
  });

  SetupBuilding copyWith({String? name, int? floorCount}) => SetupBuilding(
        id: id,
        name: name ?? this.name,
        floorCount: floorCount ?? this.floorCount,
      );

  String floorLabel(int index) {
    if (index == 0) return 'Ground Floor';
    return 'Floor $index';
  }
}

/// Named rental portion for individual-lease (Property → Unit) flow.
class SetupRentalUnit {
  final String id;
  final String name;

  const SetupRentalUnit({required this.id, required this.name});

  SetupRentalUnit copyWith({String? name}) =>
      SetupRentalUnit(id: id, name: name ?? this.name);
}

/// How a rental house is divided during onboarding.
/// Aligns with CreateSpaceScreen space kinds.
enum RentalDivisionMode {
  entireProperty,
  floorPortion,
  room,
  commercial,
}

/// Flexible space types stored on hierarchy_nodes.space_type.
enum RentalSpaceType {
  entireProperty,
  floor,
  portion,
  room,
  shop,
}

extension RentalSpaceTypeX on RentalSpaceType {
  String get apiValue {
    switch (this) {
      case RentalSpaceType.entireProperty:
        return 'entire_property';
      case RentalSpaceType.floor:
        return 'floor';
      case RentalSpaceType.portion:
        return 'portion';
      case RentalSpaceType.room:
        return 'room';
      case RentalSpaceType.shop:
        return 'shop';
    }
  }
}

/// A rentable (or structural) space planned during rental onboarding.
class SetupRentalSpace {
  final String id;
  final String name;
  final RentalSpaceType type;
  /// Local parent space id (room under floor).
  final String? parentId;

  const SetupRentalSpace({
    required this.id,
    required this.name,
    required this.type,
    this.parentId,
  });

  SetupRentalSpace copyWith({
    String? name,
    RentalSpaceType? type,
    String? parentId,
    bool clearParent = false,
  }) =>
      SetupRentalSpace(
        id: id,
        name: name ?? this.name,
        type: type ?? this.type,
        parentId: clearParent ? null : (parentId ?? this.parentId),
      );
}

/// One floor's room plan under a building.
class SetupFloorPlan {
  final String buildingId;
  final int floorIndex;
  final int roomCount;
  /// Custom names when [RoomNamingPreference.custom]; length may be < roomCount.
  final List<String> customRoomNames;
  /// Beds per room index (same length as roomCount when beds configured).
  final List<int> bedsPerRoom;

  const SetupFloorPlan({
    required this.buildingId,
    required this.floorIndex,
    required this.roomCount,
    this.customRoomNames = const [],
    this.bedsPerRoom = const [],
  });

  SetupFloorPlan copyWith({
    int? roomCount,
    List<String>? customRoomNames,
    List<int>? bedsPerRoom,
  }) =>
      SetupFloorPlan(
        buildingId: buildingId,
        floorIndex: floorIndex,
        roomCount: roomCount ?? this.roomCount,
        customRoomNames: customRoomNames ?? this.customRoomNames,
        bedsPerRoom: bedsPerRoom ?? this.bedsPerRoom,
      );

  String floorKey() => '$buildingId:$floorIndex';

  String roomNameAt(int roomIndex, RoomNamingPreference naming) {
    if (naming == RoomNamingPreference.custom &&
        roomIndex < customRoomNames.length &&
        customRoomNames[roomIndex].trim().isNotEmpty) {
      return customRoomNames[roomIndex].trim();
    }
    final floorCode = floorIndex == 0 ? 'G' : '$floorIndex';
    final n = (roomIndex + 1).toString().padLeft(2, '0');
    return '$floorCode$n';
  }

  int bedsAt(int roomIndex, {required bool addBedsNow, required int defaultBeds}) {
    if (!addBedsNow) return 0;
    if (roomIndex < bedsPerRoom.length) return bedsPerRoom[roomIndex];
    return defaultBeds;
  }
}

class PropertySetupState {
  final String propertyName;
  final String city;
  final String? propertyTypeKey;
  final OrgStructurePreset? structurePreset;
  final List<SetupBuilding> buildings;
  final Map<String, SetupFloorPlan> floorPlans; // key = buildingId:floorIndex
  final List<SetupRentalUnit> rentalUnits;
  final RentalDivisionMode? rentalDivisionMode;
  final List<SetupRentalSpace> rentalSpaces;
  final RoomNamingPreference roomNaming;
  final bool? addBedsNow;
  final int defaultBedsPerRoom;

  const PropertySetupState({
    this.propertyName = '',
    this.city = '',
    this.propertyTypeKey,
    this.structurePreset,
    this.buildings = const [],
    this.floorPlans = const {},
    this.rentalUnits = const [],
    this.rentalDivisionMode,
    this.rentalSpaces = const [],
    this.roomNaming = RoomNamingPreference.automatic,
    this.addBedsNow,
    this.defaultBedsPerRoom = 1,
  });

  PropertyArchetype get archetype => propertyArchetypeFromKey(propertyTypeKey);

  bool get isRentalHouse => archetype == PropertyArchetype.individualLease;
  bool get isApartment => archetype == PropertyArchetype.gatedCommunity;
  bool get isHostel => archetype == PropertyArchetype.sharedLiving;

  PropertySetupState copyWith({
    String? propertyName,
    String? city,
    String? propertyTypeKey,
    OrgStructurePreset? structurePreset,
    List<SetupBuilding>? buildings,
    Map<String, SetupFloorPlan>? floorPlans,
    List<SetupRentalUnit>? rentalUnits,
    RentalDivisionMode? rentalDivisionMode,
    List<SetupRentalSpace>? rentalSpaces,
    RoomNamingPreference? roomNaming,
    bool? addBedsNow,
    bool clearAddBedsNow = false,
    int? defaultBedsPerRoom,
  }) =>
      PropertySetupState(
        propertyName: propertyName ?? this.propertyName,
        city: city ?? this.city,
        propertyTypeKey: propertyTypeKey ?? this.propertyTypeKey,
        structurePreset: structurePreset ?? this.structurePreset,
        buildings: buildings ?? this.buildings,
        floorPlans: floorPlans ?? this.floorPlans,
        rentalUnits: rentalUnits ?? this.rentalUnits,
        rentalDivisionMode: rentalDivisionMode ?? this.rentalDivisionMode,
        rentalSpaces: rentalSpaces ?? this.rentalSpaces,
        roomNaming: roomNaming ?? this.roomNaming,
        addBedsNow: clearAddBedsNow ? null : (addBedsNow ?? this.addBedsNow),
        defaultBedsPerRoom: defaultBedsPerRoom ?? this.defaultBedsPerRoom,
      );

  int get totalFloors => buildings.fold(0, (sum, b) => sum + b.floorCount);

  int get totalRooms => isRentalHouse
      ? rentalSpaces
          .where((s) =>
              s.type == RentalSpaceType.entireProperty ||
              s.type == RentalSpaceType.portion ||
              s.type == RentalSpaceType.floor ||
              s.type == RentalSpaceType.room ||
              s.type == RentalSpaceType.shop)
          .length
      : floorPlans.values.fold(0, (sum, f) => sum + f.roomCount);

  /// Occupancy-assignable spaces (excludes container floors that have child rooms).
  List<SetupRentalSpace> get assignableRentalSpaces {
    final roomParentIds = rentalSpaces
        .where((s) => s.type == RentalSpaceType.room && s.parentId != null)
        .map((s) => s.parentId!)
        .toSet();
    return rentalSpaces.where((s) {
      if (s.type == RentalSpaceType.floor && roomParentIds.contains(s.id)) {
        return false;
      }
      return true;
    }).toList();
  }

  int get totalBeds {
    if (addBedsNow != true) return 0;
    var n = 0;
    for (final f in floorPlans.values) {
      for (var i = 0; i < f.roomCount; i++) {
        n += f.bedsAt(i, addBedsNow: true, defaultBeds: defaultBedsPerRoom);
      }
    }
    return n;
  }

  String get summaryLine {
    if (isRentalHouse) {
      final n = assignableRentalSpaces.length;
      return '$n Space${n == 1 ? "" : "s"}';
    }
    final buildingLabel = isApartment ? 'Tower' : 'Building';
    final roomLabel = isApartment ? 'Flat' : 'Room';
    final b = buildings.isEmpty ? 0 : buildings.length;
    return '${buildings.isEmpty ? "Property" : (b == 1 ? buildings.first.name : "$b ${buildingLabel}s")}'
        ' • $totalFloors Floor${totalFloors == 1 ? "" : "s"}'
        ' • $totalRooms $roomLabel${totalRooms == 1 ? "" : "s"}';
  }

  /// Level overrides for property create (enable hierarchy levels).
  Map<String, dynamic> levelOverridesForApi() {
    if (isRentalHouse) {
      return {
        'building': {'enabled': false},
        'tower': {'enabled': false},
        'property': {'enabled': true},
        'floor': {'enabled': false},
        'room': {'enabled': false},
        'flat': {'enabled': false},
        'unit': {'enabled': true},
        'bed': {'enabled': false},
      };
    }

    if (isApartment) {
      return {
        'building': {'enabled': false},
        'tower': {'enabled': true},
        'property': {'enabled': false},
        'floor': {'enabled': true},
        'room': {'enabled': false},
        'flat': {'enabled': true},
        'unit': {'enabled': false},
        'bed': {'enabled': false},
      };
    }

    final preset = structurePreset ?? OrgStructurePreset.multipleBuildings;
    const bedEnabled = true;
    switch (preset) {
      case OrgStructurePreset.multipleBuildings:
        return {
          'building': {'enabled': true},
          'tower': {'enabled': true},
          'property': {'enabled': true},
          'floor': {'enabled': true},
          'room': {'enabled': true},
          'flat': {'enabled': true},
          'unit': {'enabled': true},
          'bed': {'enabled': bedEnabled},
        };
      case OrgStructurePreset.singleBuilding:
        return {
          'building': {'enabled': false},
          'tower': {'enabled': false},
          'property': {'enabled': true},
          'floor': {'enabled': true},
          'room': {'enabled': true},
          'flat': {'enabled': true},
          'unit': {'enabled': true},
          'bed': {'enabled': bedEnabled},
        };
      case OrgStructurePreset.roomsAndBeds:
        return {
          'building': {'enabled': false},
          'tower': {'enabled': false},
          'property': {'enabled': true},
          'floor': {'enabled': false},
          'room': {'enabled': true},
          'flat': {'enabled': true},
          'unit': {'enabled': true},
          'bed': {'enabled': bedEnabled},
        };
    }
  }
}

class PropertySetupNotifier extends StateNotifier<PropertySetupState> {
  PropertySetupNotifier() : super(const PropertySetupState());

  void reset() => state = const PropertySetupState();

  void setDetails({
    required String name,
    required String city,
    required String propertyTypeKey,
  }) {
    state = state.copyWith(
      propertyName: name,
      city: city,
      propertyTypeKey: propertyTypeKey,
    );
  }

  /// Starts rental spaces setup (division chosen on next screen).
  void initRentalSpacesFlow() {
    state = state.copyWith(
      structurePreset: OrgStructurePreset.roomsAndBeds,
      addBedsNow: false,
      buildings: const [],
      floorPlans: const {},
      rentalUnits: const [],
      rentalSpaces: const [],
      rentalDivisionMode: null,
    );
  }

  @Deprecated('Use initRentalSpacesFlow')
  void initRentalZeroStructureFlow() => initRentalSpacesFlow();

  @Deprecated('Use initRentalSpacesFlow')
  void initRentalUnitsFlow() => initRentalSpacesFlow();

  /// Seeds apartment tower flow (skips structure; beds never shown).
  void initApartmentFlow() {
    state = state.copyWith(
      structurePreset: OrgStructurePreset.multipleBuildings,
      addBedsNow: false,
      rentalUnits: const [],
      rentalSpaces: const [],
    );
  }

  void setRentalDivisionMode(RentalDivisionMode mode) {
    List<SetupRentalSpace> spaces;
    switch (mode) {
      case RentalDivisionMode.entireProperty:
        spaces = [
          SetupRentalSpace(
            id: _newId(),
            name: 'Entire Property',
            type: RentalSpaceType.entireProperty,
          ),
        ];
      case RentalDivisionMode.floorPortion:
      case RentalDivisionMode.room:
      case RentalDivisionMode.commercial:
        spaces = state.rentalDivisionMode == mode ? state.rentalSpaces : [];
    }
    state = state.copyWith(
      rentalDivisionMode: mode,
      rentalSpaces: spaces,
    );
  }

  void upsertRentalSpace({
    String? id,
    required String name,
    required RentalSpaceType type,
    String? parentId,
  }) {
    final list = [...state.rentalSpaces];
    if (id == null) {
      list.add(SetupRentalSpace(
        id: _newId(),
        name: name,
        type: type,
        parentId: parentId,
      ));
    } else {
      final i = list.indexWhere((s) => s.id == id);
      if (i >= 0) {
        list[i] = list[i].copyWith(
          name: name,
          type: type,
          parentId: parentId,
          clearParent: parentId == null,
        );
      }
    }
    state = state.copyWith(rentalSpaces: list);
  }

  void removeRentalSpace(String id) {
    final list = state.rentalSpaces
        .where((s) => s.id != id && s.parentId != id)
        .toList();
    state = state.copyWith(rentalSpaces: list);
  }

  void upsertRentalUnit({String? id, required String name}) {
    upsertRentalSpace(
      id: id,
      name: name,
      type: RentalSpaceType.portion,
    );
  }

  void removeRentalUnit(String id) => removeRentalSpace(id);

  void setStructurePreset(OrgStructurePreset preset) {
    var next = state.copyWith(structurePreset: preset);

    if (preset == OrgStructurePreset.singleBuilding) {
      final id =
          next.buildings.length == 1 ? next.buildings.first.id : _newId();
      final floors = next.buildings.length == 1
          ? next.buildings.first.floorCount.clamp(1, 50)
          : 2;
      next = next.copyWith(
        buildings: [
          SetupBuilding(id: id, name: 'Main Building', floorCount: floors),
        ],
      );
      next = _ensureFloorPlans(next);
    } else if (preset == OrgStructurePreset.roomsAndBeds) {
      final id = next.buildings.isEmpty ? _newId() : next.buildings.first.id;
      next = next.copyWith(
        buildings: [
          SetupBuilding(id: id, name: 'Main Building', floorCount: 1),
        ],
      );
      next = _ensureFloorPlans(next);
      final key = '$id:0';
      final existing = next.floorPlans[key];
      final roomCount =
          (existing != null && existing.roomCount > 0) ? existing.roomCount : 4;
      next = next.copyWith(
        floorPlans: {
          ...next.floorPlans,
          key: (existing ??
                  SetupFloorPlan(buildingId: id, floorIndex: 0, roomCount: 4))
              .copyWith(roomCount: roomCount),
        },
      );
    }

    state = next;
  }

  void setMainBuildingFloorCount(int floors) {
    if (state.buildings.isEmpty) return;
    final b = state.buildings.first;
    state = _ensureFloorPlans(
      state.copyWith(
        buildings: [
          b.copyWith(name: 'Main Building', floorCount: floors.clamp(1, 50)),
        ],
      ),
    );
  }

  PropertySetupState _ensureFloorPlans(PropertySetupState s) {
    final plans = Map<String, SetupFloorPlan>.from(s.floorPlans);
    for (final b in s.buildings) {
      for (var i = 0; i < b.floorCount; i++) {
        final key = '${b.id}:$i';
        plans.putIfAbsent(
          key,
          () => SetupFloorPlan(
            buildingId: b.id,
            floorIndex: i,
            roomCount: 0,
          ),
        );
      }
      plans.removeWhere(
        (k, v) => v.buildingId == b.id && v.floorIndex >= b.floorCount,
      );
    }
    final ids = s.buildings.map((b) => b.id).toSet();
    plans.removeWhere((k, v) => !ids.contains(v.buildingId));
    return s.copyWith(floorPlans: plans);
  }

  void upsertBuilding({String? id, required String name, required int floors}) {
    final list = [...state.buildings];
    if (id == null) {
      list.add(SetupBuilding(id: _newId(), name: name, floorCount: floors));
    } else {
      final i = list.indexWhere((b) => b.id == id);
      if (i >= 0) {
        list[i] = list[i].copyWith(name: name, floorCount: floors);
      }
    }
    state = _ensureFloorPlans(state.copyWith(buildings: list));
  }

  void removeBuilding(String id) {
    final list = state.buildings.where((b) => b.id != id).toList();
    state = _ensureFloorPlans(state.copyWith(buildings: list));
  }

  void setRoomCount({
    required String buildingId,
    required int floorIndex,
    required int roomCount,
  }) {
    final key = '$buildingId:$floorIndex';
    final existing = state.floorPlans[key] ??
        SetupFloorPlan(
          buildingId: buildingId,
          floorIndex: floorIndex,
          roomCount: 0,
        );
    final plans = Map<String, SetupFloorPlan>.from(state.floorPlans);
    plans[key] = existing.copyWith(roomCount: roomCount.clamp(0, 200));
    state = state.copyWith(floorPlans: plans);
  }

  void setRoomNaming(RoomNamingPreference naming) {
    state = state.copyWith(roomNaming: naming);
  }

  void setCustomRoomName({
    required String buildingId,
    required int floorIndex,
    required int roomIndex,
    required String name,
  }) {
    final key = '$buildingId:$floorIndex';
    final plan = state.floorPlans[key];
    if (plan == null) return;
    final names = List<String>.generate(
      plan.roomCount,
      (i) => i < plan.customRoomNames.length ? plan.customRoomNames[i] : '',
    );
    if (roomIndex >= names.length) return;
    names[roomIndex] = name;
    final plans = Map<String, SetupFloorPlan>.from(state.floorPlans);
    plans[key] = plan.copyWith(customRoomNames: names);
    state = state.copyWith(floorPlans: plans);
  }

  void setAddBedsNow(bool value) {
    state = state.copyWith(addBedsNow: value);
    if (value) {
      final plans = <String, SetupFloorPlan>{};
      for (final e in state.floorPlans.entries) {
        final beds = List<int>.filled(
          e.value.roomCount,
          state.defaultBedsPerRoom,
        );
        plans[e.key] = e.value.copyWith(bedsPerRoom: beds);
      }
      state = state.copyWith(floorPlans: plans);
    }
  }

  void setDefaultBedsPerRoom(int n) {
    final beds = n.clamp(0, 20);
    final plans = <String, SetupFloorPlan>{};
    for (final e in state.floorPlans.entries) {
      plans[e.key] = e.value.copyWith(
        bedsPerRoom: List<int>.filled(e.value.roomCount, beds),
      );
    }
    state = state.copyWith(
      defaultBedsPerRoom: beds,
      floorPlans: plans,
    );
  }

  void setBedsForRoom({
    required String buildingId,
    required int floorIndex,
    required int roomIndex,
    required int beds,
  }) {
    final key = '$buildingId:$floorIndex';
    final plan = state.floorPlans[key];
    if (plan == null) return;
    final list = List<int>.generate(
      plan.roomCount,
      (i) => i < plan.bedsPerRoom.length
          ? plan.bedsPerRoom[i]
          : state.defaultBedsPerRoom,
    );
    if (roomIndex >= list.length) return;
    list[roomIndex] = beds.clamp(0, 20);
    final plans = Map<String, SetupFloorPlan>.from(state.floorPlans);
    plans[key] = plan.copyWith(bedsPerRoom: list);
    state = state.copyWith(floorPlans: plans);
  }
}

final propertySetupProvider =
    StateNotifierProvider<PropertySetupNotifier, PropertySetupState>((ref) {
  return PropertySetupNotifier();
});
