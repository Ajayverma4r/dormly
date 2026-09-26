// features/tenancies/presentation/residents_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/tenancy_repository.dart';
import 'add_tenant_screen.dart';
import 'hostel_pg_tenants_body.dart';
import 'tenant_profile_screen.dart';
import 'tenancy_providers.dart';

export 'tenancy_providers.dart' show propertyResidentsProvider;

class ResidentsListScreen extends ConsumerStatefulWidget {
  final String propertyId;
  final String label;

  const ResidentsListScreen({
    super.key,
    required this.propertyId,
    required this.label,
  });

  @override
  ConsumerState<ResidentsListScreen> createState() =>
      _ResidentsListScreenState();
}

class _ResidentsListScreenState extends ConsumerState<ResidentsListScreen> {
  Future<void> _openAddGuest() async {
    await openAddTenantFlow(
      context: context,
      ref: ref,
      propertyId: widget.propertyId,
    );
    ref.invalidate(propertyResidentsProvider(widget.propertyId));
  }

  Future<void> _openGuestDetail(Map<String, dynamic> r) async {
    final tenancyId = r['id']?.toString() ?? '';
    if (tenancyId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open guest profile.')),
      );
      return;
    }

    await Navigator.of(context).push(
      TenantProfileScreen.route(
        propertyId: widget.propertyId,
        tenancyId: tenancyId,
        initialTenancy: r,
      ),
    );
    ref.invalidate(propertyResidentsProvider(widget.propertyId));
  }

  @override
  Widget build(BuildContext context) {
    final residentsAsync =
        ref.watch(propertyResidentsProvider(widget.propertyId));
    // Keep repository watch so image/base URL providers stay warm for profiles.
    ref.watch(tenancyRepositoryProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0D1623),
      body: SafeArea(
        child: residentsAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: Color(0xFF8B5CF6)),
          ),
          error: (err, _) => Center(
            child: Text(
              'Something went wrong: $err',
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          data: (residents) => HostelPgTenantsBody(
            residents: residents,
            onAdd: _openAddGuest,
            onOpen: _openGuestDetail,
          ),
        ),
      ),
    );
  }
}
