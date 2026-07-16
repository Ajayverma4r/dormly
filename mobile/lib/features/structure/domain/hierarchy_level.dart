// features/structure/domain/hierarchy_level.dart
//
// Mirrors the backend HierarchyLevel exactly. The UI is built entirely from
// instances of this class — no screen ever hardcodes "Room" or "Bed".

class HierarchyLevel {
  final String id;
  final String propertyId;
  final String displayName;
  final String internalKey;
  final String? icon;
  final String? color;
  final int orderIndex;
  final String? parentLevelId;
  final bool isEnabled;
  final bool allowMultipleChildren;
  final bool supportsOccupancy;
  final bool supportsAssets;
  final bool supportsComplaints;

  const HierarchyLevel({
    required this.id,
    required this.propertyId,
    required this.displayName,
    required this.internalKey,
    required this.orderIndex,
    required this.isEnabled,
    required this.allowMultipleChildren,
    required this.supportsOccupancy,
    required this.supportsAssets,
    required this.supportsComplaints,
    this.icon,
    this.color,
    this.parentLevelId,
  });

  factory HierarchyLevel.fromJson(Map<String, dynamic> json) => HierarchyLevel(
        id: json['id'] as String,
        propertyId: json['propertyId'] as String,
        displayName: json['displayName'] as String,
        internalKey: json['internalKey'] as String,
        icon: json['icon'] as String?,
        color: json['color'] as String?,
        orderIndex: json['orderIndex'] as int,
        parentLevelId: json['parentLevelId'] as String?,
        isEnabled: json['isEnabled'] as bool,
        allowMultipleChildren: json['allowMultipleChildren'] as bool,
        supportsOccupancy: json['supportsOccupancy'] as bool,
        supportsAssets: json['supportsAssets'] as bool,
        supportsComplaints: json['supportsComplaints'] as bool,
      );

  HierarchyLevel copyWith({String? displayName, bool? isEnabled}) => HierarchyLevel(
        id: id,
        propertyId: propertyId,
        displayName: displayName ?? this.displayName,
        internalKey: internalKey,
        icon: icon,
        color: color,
        orderIndex: orderIndex,
        parentLevelId: parentLevelId,
        isEnabled: isEnabled ?? this.isEnabled,
        allowMultipleChildren: allowMultipleChildren,
        supportsOccupancy: supportsOccupancy,
        supportsAssets: supportsAssets,
        supportsComplaints: supportsComplaints,
      );
}
