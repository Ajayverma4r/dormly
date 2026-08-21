// features/properties/domain/property_monetization.dart
//
// Mirrors backend/src/shared/property-monetization.ts.

/// Free forever (unlimited create, ads-supported).
const kFreeResidentialTypes = {
  'rental', // Rental Property
  'house', // Independent House
  'villa', // Villa
};

const kApartmentType = 'apartment';

/// Free Apartment structure caps (paid plans unlimited).
const kFreeApartmentMaxBuildings = 1;
const kFreeApartmentMaxRooms = 20;

const kBuildingLevelKeys = {'building', 'tower'};
const kRoomLevelKeys = {'room', 'flat', 'bed'};

class PropertyMonetization {
  static bool isFreeResidential(String? propertyTypeKey) {
    if (propertyTypeKey == null || propertyTypeKey.isEmpty) return false;
    return kFreeResidentialTypes.contains(propertyTypeKey);
  }

  static bool isApartment(String? propertyTypeKey) =>
      propertyTypeKey == kApartmentType;

  /// Apartment + Hostel/PG/etc. — not free-forever residential.
  static bool isCommercial(String? propertyTypeKey) {
    if (propertyTypeKey == null || propertyTypeKey.isEmpty) return true;
    return !isFreeResidential(propertyTypeKey);
  }

  static bool isPaidPlan(String? planSlug, String? status) {
    if (planSlug == null || planSlug == 'free') return false;
    return status == 'active' || status == 'trialing' || status == 'past_due';
  }

  static bool isBuildingLevel(String? internalKey) =>
      internalKey != null && kBuildingLevelKeys.contains(internalKey);

  static bool isRoomLevel(String? internalKey, {bool supportsOccupancy = false}) =>
      supportsOccupancy ||
      (internalKey != null && kRoomLevelKeys.contains(internalKey));

  static int get freeApartmentMaxBuildings => kFreeApartmentMaxBuildings;
  static int get freeApartmentMaxRooms => kFreeApartmentMaxRooms;

  static String badgeFor(String? propertyTypeKey) {
    if (isFreeResidential(propertyTypeKey)) return 'Free with Ads';
    if (isApartment(propertyTypeKey)) return '1 Building + 20 Rooms free';
    return '1 Free, Upgrade for Multi-property';
  }

  /// Whether creating another property of [typeKey] should open the paywall.
  static bool requiresUpgradeForCreate({
    required String? typeKey,
    required int commercialCount,
    required bool isPaid,
  }) {
    if (isFreeResidential(typeKey)) return false;
    if (isPaid) return false;
    return commercialCount >= 1;
  }

  /// Message shown when tapping a frozen surplus commercial property.
  static const expiredLockMessage =
      'Your Premium plan has expired. Upgrade to access all your properties.';

  /// Client-side lock: free residential always open; oldest commercial open;
  /// other commercial locked when not paid. Prefer server `is_locked` when present.
  static bool isPropertyLocked({
    required Map<String, dynamic> property,
    required List<Map<String, dynamic>> allProperties,
    required bool isPaid,
  }) {
    if (isPaid) return false;

    final serverLocked = property['is_locked'];
    if (serverLocked is bool) return serverLocked;
    final serverManageable = property['manageable'];
    if (serverManageable is bool) return !serverManageable;

    final typeKey = property['property_type_key'] as String?;
    if (isFreeResidential(typeKey)) return false;

    final commercials = allProperties
        .where((p) => isCommercial(p['property_type_key'] as String?))
        .toList()
      ..sort((a, b) {
        final aAt = DateTime.tryParse('${a['created_at'] ?? ''}') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bAt = DateTime.tryParse('${b['created_at'] ?? ''}') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return aAt.compareTo(bAt);
      });

    if (commercials.isEmpty) return false;
    return property['id'] != commercials.first['id'];
  }
}
