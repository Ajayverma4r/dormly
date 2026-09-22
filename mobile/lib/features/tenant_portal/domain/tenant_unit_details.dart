// features/tenant_portal/domain/tenant_unit_details.dart
//
// Normalized unit address for header badges across property kinds.

class TenantUnitDetails {
  final String? roomNo;
  final String? bedId;
  final String? tower;
  final String? flatNo;
  final String? unitName;
  final String? propertyName;

  const TenantUnitDetails({
    this.roomNo,
    this.bedId,
    this.tower,
    this.flatNo,
    this.unitName,
    this.propertyName,
  });

  factory TenantUnitDetails.fromTenancy(Map<String, dynamic> t) {
    final node = (t['node_name'] ?? t['nodeName'])?.toString().trim();
    final parent =
        (t['parent_node_name'] ?? t['parentNodeName'])?.toString().trim();
    final grand = (t['grandparent_node_name'] ?? t['grandparentNodeName'])
        ?.toString()
        .trim();
    final level =
        (t['node_level_key'] ?? t['nodeLevelKey'])?.toString().toLowerCase() ??
            '';
    final property = t['property_name']?.toString().trim();

    final isBed = level == 'bed' || (parent != null && parent.isNotEmpty);

    return TenantUnitDetails(
      roomNo: isBed
          ? (parent?.isNotEmpty == true ? parent : null)
          : (node?.isNotEmpty == true ? node : null),
      bedId: isBed && node != null && node.isNotEmpty ? node : null,
      tower: grand?.isNotEmpty == true
          ? grand
          : (parent?.isNotEmpty == true ? parent : null),
      flatNo: node?.isNotEmpty == true ? node : null,
      unitName: node?.isNotEmpty == true
          ? node
          : (property?.isNotEmpty == true ? property : null),
      propertyName: property,
    );
  }
}
