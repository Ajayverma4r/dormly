// features/tenant_portal/presentation/widgets/tenant_quick_actions_grid.dart
//
// Renders QuickActionConfig list — navigation stays in one router helper.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../complaints/presentation/raise_complaint_screen.dart';
import '../../data/tenant_portal_repository.dart';
import '../../domain/quick_action_config.dart';
import '../../domain/tenant_session.dart';
import '../gate_pass_screen.dart';
import '../mess_menu_screen.dart';
import '../meter_reading_screen.dart';
import '../move_out_notice_screen.dart';
import '../request_move_out_sheet.dart';
import '../tenant_payments_sheet.dart';
import '../tenant_portal_providers.dart';

const _ink = Color(0xFF0F172A);
const _brand = Color(0xFF5218D1);

class TenantQuickActionsGrid extends ConsumerWidget {
  final TenantSession session;
  final VoidCallback onSeeAll;

  const TenantQuickActionsGrid({
    super.key,
    required this.session,
    required this.onSeeAll,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions =
        QuickActionConfig.getActionsForProperty(session.propertyType);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Quick Actions',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: _ink,
                ),
              ),
            ),
            TextButton(
              onPressed: onSeeAll,
              style: TextButton.styleFrom(
                foregroundColor: _brand,
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'See All >',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(
                child: _Tile(
                  config: actions[i],
                  onTap: () => _dispatch(context, ref, actions[i].route),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Future<void> _dispatch(
    BuildContext context,
    WidgetRef ref,
    QuickActionRoute route,
  ) async {
    final tenancy = session.tenancy;

    switch (route) {
      case QuickActionRoute.raiseComplaint:
      case QuickActionRoute.maintenance:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RaiseComplaintScreen(
              propertyId: session.propertyId,
              nodeId: session.nodeId,
            ),
          ),
        );
        ref.invalidate(myComplaintsProvider);
        return;

      case QuickActionRoute.wifi:
        _showWifiSheet(context, tenancy);
        return;

      case QuickActionRoute.messMenu:
        if (!session.isHostel) return;
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MessMenuScreen()),
        );
        return;

      case QuickActionRoute.moveOut:
        final status = tenancy['move_out_request_status']?.toString() ?? '';
        final already = status == 'pending' ||
            status == 'approved' ||
            status == 'modified_by_mutual_agreement';
        if (already) {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MoveOutNoticeScreen(tenancy: tenancy),
            ),
          );
          return;
        }
        final ok = await showRequestMoveOutSheet(
          context: context,
          ref: ref,
          tenancy: tenancy,
        );
        if (ok) {
          ref.invalidate(myTenancyProvider);
          ref.invalidate(tenantSessionProvider);
        }
        return;

      case QuickActionRoute.gatePass:
        if (!session.isApartment) return;
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const GatePassScreen()),
        );
        return;

      case QuickActionRoute.societyNotices:
        await showTenantRentPaymentsSheet(context: context, ref: ref);
        return;

      case QuickActionRoute.meterReading:
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MeterReadingScreen()),
        );
        ref.invalidate(myInvoicesProvider);
        return;

      case QuickActionRoute.leaseDetails:
        final url = tenancy['agreement_pdf_url']?.toString();
        if (url == null || url.trim().isEmpty) {
          _showInfo(
            context,
            title: 'Lease Details',
            body: 'No lease PDF is on file yet. Ask your owner to upload it.',
          );
          return;
        }
        final base = ref.read(tenantPortalRepositoryProvider).baseUrl;
        final full = url.startsWith('http') ? url : '$base$url';
        final uri = Uri.tryParse(full);
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
        return;
    }
  }

  void _showWifiSheet(BuildContext context, Map<String, dynamic> tenancy) {
    final node = tenancy['node_name']?.toString() ?? 'Room';
    final ssid = 'Dormly_${node.replaceAll(RegExp(r'\s+'), '')}';
    _showInfo(
      context,
      title: 'Wi-Fi Details',
      body:
          'Network: $ssid\nPassword: Ask your warden or check the notice board.',
    );
  }

  void _showInfo(
    BuildContext context, {
    required String title,
    required String body,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                body,
                style: const TextStyle(color: Color(0xFF64748B), height: 1.4),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: FilledButton.styleFrom(backgroundColor: _brand),
                  child: const Text('Got it'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final QuickActionConfig config;
  final VoidCallback onTap;

  const _Tile({required this.config, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE9E0FF)),
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: config.tint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(config.icon, color: config.iconColor, size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                config.label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
