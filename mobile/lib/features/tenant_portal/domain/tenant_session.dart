// features/tenant_portal/domain/tenant_session.dart
//
// Global tenant session view-model: property archetype + unit details.

import '../../properties/domain/property_archetype.dart';
import 'tenant_property_profile.dart';
import 'tenant_unit_details.dart';

/// Active tenant session — prefer this over raw Map lookups in presentation.
class TenantSession {
  final Map<String, dynamic> tenancy;
  final TenantPropertyProfile profile;
  final TenantUnitDetails unitDetails;

  const TenantSession({
    required this.tenancy,
    required this.profile,
    required this.unitDetails,
  });

  factory TenantSession.fromTenancy(Map<String, dynamic> tenancy) {
    return TenantSession(
      tenancy: tenancy,
      profile: TenantPropertyProfile.fromTenancy(tenancy),
      unitDetails: TenantUnitDetails.fromTenancy(tenancy),
    );
  }

  String get propertyType => profile.canonicalType;
  PropertyArchetype get archetype => profile.archetype;
  TenantPropertyKind get kind => profile.kind;

  bool get isSharedLiving => archetype == PropertyArchetype.sharedLiving;
  bool get isGatedCommunity => archetype == PropertyArchetype.gatedCommunity;
  bool get isIndividualLease => archetype == PropertyArchetype.individualLease;

  // Back-compat aliases used across existing screens.
  bool get isHostel => isSharedLiving;
  bool get isApartment => isGatedCommunity;
  bool get isRentalHouse => isIndividualLease;
  bool get isCommercial => false;

  String get propertyId => tenancy['property_id']?.toString() ?? '';
  String get nodeId => tenancy['node_id']?.toString() ?? '';
  String get fullName => tenancy['full_name']?.toString() ?? 'Tenant';

  /// Header subtitle under "Hi [Name]".
  String get headerBadge => profile.headerBadge(tenancy, unitDetails);
}
