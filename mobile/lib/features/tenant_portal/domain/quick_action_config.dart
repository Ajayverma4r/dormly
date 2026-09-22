// features/tenant_portal/domain/quick_action_config.dart
//
// Factory for property-type Quick Actions — keyed by PropertyArchetype.

import 'package:flutter/material.dart';
import '../../properties/domain/property_archetype.dart';
import 'tenant_property_profile.dart';

enum QuickActionRoute {
  raiseComplaint,
  wifi,
  messMenu,
  moveOut,
  gatePass,
  societyNotices,
  meterReading,
  leaseDetails,
  maintenance,
}

class QuickActionConfig {
  final QuickActionRoute route;
  final String label;
  final IconData icon;
  final Color tint;
  final Color iconColor;

  const QuickActionConfig({
    required this.route,
    required this.label,
    required this.icon,
    required this.tint,
    required this.iconColor,
  });

  static List<QuickActionConfig> getActionsForProperty(String type) {
    return forArchetype(propertyArchetypeFromKey(type));
  }

  static List<QuickActionConfig> forKind(TenantPropertyKind kind) =>
      forArchetype(kind);

  static List<QuickActionConfig> forArchetype(PropertyArchetype archetype) {
    switch (archetype) {
      case PropertyArchetype.sharedLiving:
        return const [
          QuickActionConfig(
            route: QuickActionRoute.raiseComplaint,
            label: 'Raise\nComplaint',
            icon: Icons.build_outlined,
            tint: Color(0xFFF3E8FF),
            iconColor: Color(0xFF5218D1),
          ),
          QuickActionConfig(
            route: QuickActionRoute.wifi,
            label: 'Wi-Fi\nDetails',
            icon: Icons.wifi_rounded,
            tint: Color(0xFFDBEAFE),
            iconColor: Color(0xFF2563EB),
          ),
          QuickActionConfig(
            route: QuickActionRoute.messMenu,
            label: 'Mess\nMenu',
            icon: Icons.restaurant_outlined,
            tint: Color(0xFFD1FAE5),
            iconColor: Color(0xFF059669),
          ),
          QuickActionConfig(
            route: QuickActionRoute.moveOut,
            label: 'Move-Out\n/ Notice',
            icon: Icons.logout_rounded,
            tint: Color(0xFFFFEDD5),
            iconColor: Color(0xFFEA580C),
          ),
        ];
      case PropertyArchetype.gatedCommunity:
        return const [
          QuickActionConfig(
            route: QuickActionRoute.raiseComplaint,
            label: 'Raise\nComplaint',
            icon: Icons.build_outlined,
            tint: Color(0xFFF3E8FF),
            iconColor: Color(0xFF5218D1),
          ),
          QuickActionConfig(
            route: QuickActionRoute.gatePass,
            label: 'Gate\nPass',
            icon: Icons.badge_outlined,
            tint: Color(0xFFDBEAFE),
            iconColor: Color(0xFF2563EB),
          ),
          QuickActionConfig(
            route: QuickActionRoute.societyNotices,
            label: 'Society\nNotices',
            icon: Icons.campaign_outlined,
            tint: Color(0xFFD1FAE5),
            iconColor: Color(0xFF059669),
          ),
          QuickActionConfig(
            route: QuickActionRoute.moveOut,
            label: 'Move-Out\n/ Notice',
            icon: Icons.logout_rounded,
            tint: Color(0xFFFFEDD5),
            iconColor: Color(0xFFEA580C),
          ),
        ];
      case PropertyArchetype.individualLease:
        return const [
          QuickActionConfig(
            route: QuickActionRoute.raiseComplaint,
            label: 'Raise\nComplaint',
            icon: Icons.build_outlined,
            tint: Color(0xFFF3E8FF),
            iconColor: Color(0xFF5218D1),
          ),
          QuickActionConfig(
            route: QuickActionRoute.meterReading,
            label: 'Upload Meter\nReading',
            icon: Icons.bolt_rounded,
            tint: Color(0xFFFEF3C7),
            iconColor: Color(0xFFD97706),
          ),
          QuickActionConfig(
            route: QuickActionRoute.leaseDetails,
            label: 'Lease\nDetails',
            icon: Icons.description_outlined,
            tint: Color(0xFFE0E7FF),
            iconColor: Color(0xFF4338CA),
          ),
          QuickActionConfig(
            route: QuickActionRoute.moveOut,
            label: 'Move-Out\n/ Notice',
            icon: Icons.logout_rounded,
            tint: Color(0xFFFFEDD5),
            iconColor: Color(0xFFEA580C),
          ),
        ];
    }
  }
}
