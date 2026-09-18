// features/tenant_portal/domain/tenant_property_profile.dart
//
// Resolves property_type_key into UX families for the tenant dashboard
// ("One Platform. Every Property.").

enum TenantPropertyKind {
  hostelPg,
  apartment,
  rentalHouse,
  commercial,
}

enum TenantQuickActionId {
  raiseComplaint,
  wifi,
  messMenu,
  moveOut,
  gatePass,
  societyDues,
  meterElectricity,
  leaseAgreement,
  gstInvoices,
  commercialEb,
  maintenance,
  leaseTerms,
}

class TenantPropertyProfile {
  final TenantPropertyKind kind;
  final String rawTypeKey;

  const TenantPropertyProfile({
    required this.kind,
    required this.rawTypeKey,
  });

  factory TenantPropertyProfile.fromTenancy(Map<String, dynamic> t) {
    final raw = (t['property_type_key'] ??
            t['propertyTypeKey'] ??
            t['unit_type'] ??
            t['unitType'] ??
            '')
        .toString()
        .trim()
        .toLowerCase();
    return TenantPropertyProfile(
      kind: resolveKind(raw),
      rawTypeKey: raw,
    );
  }

  static TenantPropertyKind resolveKind(String raw) {
    // Accept both seed keys and product aliases from the UX brief.
    switch (raw) {
      case 'hostel':
      case 'pg':
      case 'hostel_pg':
      case 'coliving':
      case 'staff_housing':
      case 'hotel':
        return TenantPropertyKind.hostelPg;
      case 'apartment':
      case 'flat':
        return TenantPropertyKind.apartment;
      case 'rental':
      case 'rental_house':
      case 'house':
      case 'villa':
      case 'independent':
        return TenantPropertyKind.rentalHouse;
      case 'office':
      case 'warehouse':
      case 'factory':
      case 'parking':
      case 'school':
      case 'hospital':
      case 'resort':
      case 'commercial':
      case 'custom':
        return TenantPropertyKind.commercial;
      default:
        if (raw.isEmpty) return TenantPropertyKind.hostelPg;
        return TenantPropertyKind.commercial;
    }
  }

  /// Subtitle under "Hi [Name]" on the tenant home header.
  String headerBadge(Map<String, dynamic> t) {
    final node = (t['node_name'] ?? t['nodeName'])?.toString().trim() ?? '';
    final parent =
        (t['parent_node_name'] ?? t['parentNodeName'])?.toString().trim() ??
            '';
    final grand = (t['grandparent_node_name'] ?? t['grandparentNodeName'])
            ?.toString()
            .trim() ??
        '';
    final level =
        (t['node_level_key'] ?? t['nodeLevelKey'])?.toString().toLowerCase() ??
            '';
    final property = t['property_name']?.toString().trim() ?? '';

    switch (kind) {
      case TenantPropertyKind.hostelPg:
        if ((level == 'bed' || parent.isNotEmpty) && parent.isNotEmpty) {
          return 'Room $parent • Bed $node';
        }
        if (node.isNotEmpty) return 'Room $node';
        return property.isNotEmpty ? property : 'Your stay';

      case TenantPropertyKind.apartment:
        final tower = grand.isNotEmpty
            ? grand
            : (parent.isNotEmpty ? parent : property);
        final flat = node.isNotEmpty ? node : '—';
        if (tower.isNotEmpty) return 'Tower $tower • Flat $flat';
        return 'Flat $flat';

      case TenantPropertyKind.rentalHouse:
        final unit =
            node.isNotEmpty ? node : (property.isNotEmpty ? property : 'Home');
        return 'Unit $unit • Full House';

      case TenantPropertyKind.commercial:
        final unit = node.isNotEmpty ? node : 'Unit';
        if (property.isNotEmpty) return '$property • $unit';
        return unit;
    }
  }

  List<TenantQuickActionId> get quickActions {
    switch (kind) {
      case TenantPropertyKind.hostelPg:
        return const [
          TenantQuickActionId.raiseComplaint,
          TenantQuickActionId.wifi,
          TenantQuickActionId.messMenu,
          TenantQuickActionId.moveOut,
        ];
      case TenantPropertyKind.apartment:
        return const [
          TenantQuickActionId.raiseComplaint,
          TenantQuickActionId.gatePass,
          TenantQuickActionId.societyDues,
          TenantQuickActionId.moveOut,
        ];
      case TenantPropertyKind.rentalHouse:
        return const [
          TenantQuickActionId.raiseComplaint,
          TenantQuickActionId.meterElectricity,
          TenantQuickActionId.leaseAgreement,
          TenantQuickActionId.moveOut,
        ];
      case TenantPropertyKind.commercial:
        return const [
          TenantQuickActionId.gstInvoices,
          TenantQuickActionId.commercialEb,
          TenantQuickActionId.maintenance,
          TenantQuickActionId.leaseTerms,
        ];
    }
  }

  bool get showsMessMenu => kind == TenantPropertyKind.hostelPg;
  bool get showsWifi => kind == TenantPropertyKind.hostelPg;
  bool get showsGatePass => kind == TenantPropertyKind.apartment;
}
