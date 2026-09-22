// features/properties/domain/property_archetype.dart
//
// Canonical 3-archetype model. All UI / feature branching should use this
// enum — never scatter raw property_type_key string checks.

/// Product UX families for owner + tenant surfaces.
enum PropertyArchetype {
  /// Hostel / PG / co-living — Building > Floor > Room > Bed
  sharedLiving,

  /// Flat / Apartment — Tower > Floor > Flat
  gatedCommunity,

  /// Rental house / villa / commercial lease — Property > Unit
  individualLease,
}

/// Canonical catalog keys stored on `properties.property_type_key`.
class PropertyTypeKeys {
  static const hostelPg = 'hostel_pg';
  static const apartment = 'apartment';
  static const rentalHouse = 'rental_house';

  static const allowed = {hostelPg, apartment, rentalHouse};
}

extension PropertyArchetypeX on PropertyArchetype {
  /// Backend catalog key used when creating a property.
  String get catalogKey {
    switch (this) {
      case PropertyArchetype.sharedLiving:
        return PropertyTypeKeys.hostelPg;
      case PropertyArchetype.gatedCommunity:
        return PropertyTypeKeys.apartment;
      case PropertyArchetype.individualLease:
        return PropertyTypeKeys.rentalHouse;
    }
  }

  String get label {
    switch (this) {
      case PropertyArchetype.sharedLiving:
        return 'Hostel / PG';
      case PropertyArchetype.gatedCommunity:
        return 'Flat / Apartment';
      case PropertyArchetype.individualLease:
        return 'Rental House';
    }
  }

  String get subtitle {
    switch (this) {
      case PropertyArchetype.sharedLiving:
        return 'Shared living — beds, mess menu, Wi‑Fi';
      case PropertyArchetype.gatedCommunity:
        return 'Gated community — towers, gate pass, meters';
      case PropertyArchetype.individualLease:
        return 'Individual lease — units, rent & utilities';
    }
  }

  bool get showsMessMenu => this == PropertyArchetype.sharedLiving;
  bool get showsWifi => this == PropertyArchetype.sharedLiving;
  bool get showsGatePass => this == PropertyArchetype.gatedCommunity;
  bool get showsSocietyNotices => this == PropertyArchetype.gatedCommunity;
  bool get showsMeterUpload =>
      this == PropertyArchetype.gatedCommunity ||
      this == PropertyArchetype.individualLease;
  bool get showsLeaseDetails =>
      this == PropertyArchetype.individualLease ||
      this == PropertyArchetype.gatedCommunity;

  String get peopleLabel {
    switch (this) {
      case PropertyArchetype.sharedLiving:
        return 'Residents';
      case PropertyArchetype.gatedCommunity:
      case PropertyArchetype.individualLease:
        return 'Tenants';
    }
  }
}

/// Strict mapping from any backend / legacy `property_type_key` → archetype.
PropertyArchetype propertyArchetypeFromKey(String? raw) {
  final key = (raw ?? '').trim().toLowerCase();
  switch (key) {
    case 'hostel_pg':
    case 'hostel':
    case 'pg':
    case 'coliving':
    case 'staff_housing':
    case 'hotel':
      return PropertyArchetype.sharedLiving;

    case 'apartment':
    case 'flat':
      return PropertyArchetype.gatedCommunity;

    case 'rental_house':
    case 'rental':
    case 'villa':
    case 'house':
    case 'independent':
    case 'commercial':
    case 'office':
    case 'warehouse':
    case 'factory':
    case 'parking':
    case 'school':
    case 'hospital':
    case 'resort':
    case 'custom':
      return PropertyArchetype.individualLease;

    default:
      if (key.isEmpty) return PropertyArchetype.sharedLiving;
      // Unknown leftovers collapse into individual lease (not a 4th UX family).
      return PropertyArchetype.individualLease;
  }
}

PropertyArchetype propertyArchetypeFromProperty(Map<String, dynamic>? property) {
  if (property == null) return PropertyArchetype.sharedLiving;
  return propertyArchetypeFromKey(
    (property['property_type_key'] ?? property['propertyTypeKey'])?.toString(),
  );
}
