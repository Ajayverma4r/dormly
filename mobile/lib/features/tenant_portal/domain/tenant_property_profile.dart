// features/tenant_portal/domain/tenant_property_profile.dart
//
// Thin adapter over PropertyArchetype for tenant portal surfaces.

import '../../properties/domain/property_archetype.dart';
import 'tenant_unit_details.dart';

/// @Deprecated — prefer [PropertyArchetype]. Kept as a typedef alias for
/// call sites that still say "kind".
typedef TenantPropertyKind = PropertyArchetype;

class TenantPropertyProfile {
  final PropertyArchetype archetype;
  final String rawTypeKey;

  const TenantPropertyProfile({
    required this.archetype,
    required this.rawTypeKey,
  });

  /// Back-compat getter used across tenant portal.
  PropertyArchetype get kind => archetype;

  factory TenantPropertyProfile.fromTenancy(Map<String, dynamic> t) {
    final raw = (t['property_type_key'] ??
            t['propertyTypeKey'] ??
            t['property_type'] ??
            t['propertyType'] ??
            t['unit_type'] ??
            t['unitType'] ??
            '')
        .toString()
        .trim()
        .toLowerCase();
    return TenantPropertyProfile(
      archetype: propertyArchetypeFromKey(raw),
      rawTypeKey: raw,
    );
  }

  /// Canonical catalog key for this archetype.
  String get canonicalType => archetype.catalogKey;

  bool get isHostel => archetype == PropertyArchetype.sharedLiving;
  bool get isApartment => archetype == PropertyArchetype.gatedCommunity;
  bool get isRentalHouse => archetype == PropertyArchetype.individualLease;

  /// Legacy commercial UX collapsed into individual lease.
  bool get isCommercial => false;

  bool get showsMessMenu => archetype.showsMessMenu;
  bool get showsWifi => archetype.showsWifi;
  bool get showsGatePass => archetype.showsGatePass;
  bool get showsMeterUpload => archetype.showsMeterUpload;

  static PropertyArchetype resolveKind(String raw) =>
      propertyArchetypeFromKey(raw);

  /// Subtitle under "Hi [Name]" on the tenant home header.
  String headerBadge(
    Map<String, dynamic> t, [
    TenantUnitDetails? details,
  ]) {
    final u = details ?? TenantUnitDetails.fromTenancy(t);

    switch (archetype) {
      case PropertyArchetype.sharedLiving:
        if (u.roomNo != null && u.bedId != null) {
          return 'Room ${u.roomNo} • Bed ${u.bedId}';
        }
        if (u.roomNo != null) return 'Room ${u.roomNo}';
        if (u.bedId != null) return 'Bed ${u.bedId}';
        return u.propertyName?.isNotEmpty == true
            ? u.propertyName!
            : 'Your stay';

      case PropertyArchetype.gatedCommunity:
        final tower = u.tower;
        final flat = u.flatNo ?? '—';
        if (tower != null && tower.isNotEmpty) {
          return 'Tower $tower • Flat $flat';
        }
        return 'Flat $flat';

      case PropertyArchetype.individualLease:
        final unit = u.unitName ?? u.propertyName ?? 'Home';
        return 'Unit $unit';
    }
  }
}
