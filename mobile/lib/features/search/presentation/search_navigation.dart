// features/search/presentation/search_navigation.dart
//
// Opens a global-search result in the screen that already shows that record.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../billing/presentation/invoice_detail_screen.dart';
import '../../complaints/presentation/complaint_details_screen.dart';
import '../../complaints/presentation/complaints_list_screen.dart';
import '../../staff/presentation/staff_list_screen.dart';
import '../../staff_home/presentation/staff_gate_passes_screen.dart';
import '../../staff_home/presentation/staff_meter_readings_screen.dart';
import '../../staff_home/presentation/staff_rooms_screen.dart';
import '../../staff_home/presentation/staff_tenants_screen.dart';
import '../../tenancies/presentation/node_detail_screen.dart';
import '../../tenancies/presentation/rental_space_detail_screen.dart';
import '../../tenancies/presentation/tenant_profile_screen.dart';
import '../../tenant_portal/presentation/gate_pass_screen.dart';
import '../../tenant_portal/presentation/mess_menu_screen.dart';
import '../../tenant_portal/presentation/meter_reading_screen.dart';
import '../../tenant_portal/presentation/owner_mess_menu_screen.dart';
import '../../tenant_portal/presentation/tenant_payment_history_screen.dart';
import '../../tenant_portal/presentation/tenant_portal_providers.dart'
    show myComplaintsProvider;
import '../domain/global_search.dart';

typedef SearchResultOpener = Future<void> Function(
  BuildContext context,
  WidgetRef ref,
  SearchDestination destination, {
  required bool canManage,
});

/// Overridable in tests so result taps can be observed without the targets.
final searchResultOpenerProvider =
    Provider<SearchResultOpener>((ref) => openSearchDestination);

Future<void> _push(BuildContext context, Widget screen) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

Map<String, dynamic>? _findById(List<Map<String, dynamic>> rows, String? id) {
  for (final row in rows) {
    if (row['id']?.toString() == id) return row;
  }
  return null;
}

Future<void> openSearchDestination(
  BuildContext context,
  WidgetRef ref,
  SearchDestination d, {
  required bool canManage,
}) async {
  final p = d.propertyId;
  final id = d.targetId ?? '';
  switch (d.kind) {
    case SearchDestinationKind.property:
      context.go('/property/$p', extra: {'propertyName': d.label ?? 'Dashboard'});
    case SearchDestinationKind.nodeDetail:
      await Navigator.of(context).push(NodeDetailScreen.route(
        propertyId: p,
        nodeId: id,
        nodeName: d.label ?? '',
        levelName: d.levelName ?? 'Room',
      ));
    case SearchDestinationKind.rentalSpaceDetail:
      await Navigator.of(context).push(RentalSpaceDetailScreen.route(
          propertyId: p, nodeId: id, canManage: canManage));
    case SearchDestinationKind.staffRooms:
      await _push(context, StaffRoomsScreen(propertyId: p));
    case SearchDestinationKind.tenantProfile:
      await Navigator.of(context)
          .push(TenantProfileScreen.route(propertyId: p, tenancyId: id));
    case SearchDestinationKind.staffTenants:
      await _push(context, StaffTenantsScreen(propertyId: p));
    case SearchDestinationKind.teamList:
      await _push(context, StaffListScreen(propertyId: p));
    case SearchDestinationKind.teamComplaint:
      Map<String, dynamic>? complaint;
      try {
        complaint =
            _findById(await ref.read(complaintsProvider(p).future), id);
      } catch (_) {}
      if (!context.mounted) return;
      await _push(
        context,
        complaint == null
            ? ComplaintsListScreen(propertyId: p)
            : ComplaintDetailsScreen(complaint: complaint, propertyName: d.label),
      );
      ref.invalidate(complaintsProvider(p));
    case SearchDestinationKind.tenantComplaint:
      Map<String, dynamic>? complaint;
      try {
        complaint = _findById(await ref.read(myComplaintsProvider.future), id);
      } catch (_) {}
      if (!context.mounted) return;
      if (complaint == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('This complaint could not be opened. Try again.')));
        return;
      }
      await _push(context, ComplaintDetailsScreen(complaint: complaint));
    case SearchDestinationKind.teamGatePasses:
      await _push(context, StaffGatePassesScreen(propertyId: p));
    case SearchDestinationKind.tenantGatePasses:
      await _push(context, const GatePassScreen());
    case SearchDestinationKind.invoiceDetail:
      await _push(context, InvoiceDetailScreen(propertyId: p, invoiceId: id));
    case SearchDestinationKind.teamMeterReadings:
      await _push(context, StaffMeterReadingsScreen(propertyId: p));
    case SearchDestinationKind.tenantMeterReadings:
      await _push(context, const MeterReadingScreen());
    case SearchDestinationKind.teamMessMenu:
      await _push(context, OwnerMessMenuScreen(propertyId: p));
    case SearchDestinationKind.tenantMessMenu:
      await _push(context, const MessMenuScreen());
    case SearchDestinationKind.tenantPayments:
      await _push(context, const TenantPaymentHistoryScreen());
    case SearchDestinationKind.tenantHome:
      Navigator.of(context).maybePop();
  }
}
