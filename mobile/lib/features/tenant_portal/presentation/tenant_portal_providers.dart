// features/tenant_portal/presentation/tenant_portal_providers.dart
//
// Base providers always load. Feature providers skip API calls when the
// property type does not support that module (bandwidth + 403 safety).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/data/auth_repository.dart';
import '../../complaints/data/complaints_repository.dart';
import '../../properties/domain/property_archetype.dart';
import '../data/tenant_portal_repository.dart';
import '../domain/tenant_session.dart';

// ─── Always-on base queries ──────────────────────────────────────────────────

final myTenancyProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return ref.watch(tenantPortalRepositoryProvider).getMyTenancy();
});

final myInvoicesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return ref.watch(tenantPortalRepositoryProvider).listMyInvoices();
});

final myComplaintsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return ref.watch(complaintsRepositoryProvider).myComplaints();
});

final hasOwnerContextProvider = FutureProvider.autoDispose<bool>((ref) async {
  final contexts = await ref.watch(authRepositoryProvider).listContexts();
  return contexts.any((c) {
    final role = c['role']?.toString();
    return role == 'owner' || role == 'admin' || role == 'manager';
  });
});

final tenantSessionProvider =
    FutureProvider.autoDispose<TenantSession>((ref) async {
  final tenancy = await ref.watch(myTenancyProvider.future);
  return TenantSession.fromTenancy(tenancy);
});

// ─── Conditional feature providers (isolated errors) ─────────────────────────

/// Shared living only. Empty list if wrong archetype — never hits the API.
final tenantMessMenuProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final session = await ref.watch(tenantSessionProvider.future);
  if (!session.isSharedLiving) return const [];
  return ref.watch(tenantPortalRepositoryProvider).getMessMenu();
});

/// Gated community only.
final tenantGatePassesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final session = await ref.watch(tenantSessionProvider.future);
  if (!session.isGatedCommunity) return const [];
  return ref.watch(tenantPortalRepositoryProvider).myGatePasses();
});

/// Gated community only.
final tenantSocietyNoticesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final session = await ref.watch(tenantSessionProvider.future);
  if (!session.isGatedCommunity) return const [];
  return ref.watch(tenantPortalRepositoryProvider).societyNotices();
});

/// Gated community + individual lease.
final tenantMeterReadingsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final session = await ref.watch(tenantSessionProvider.future);
  if (!(session.isGatedCommunity || session.isIndividualLease)) {
    return const [];
  }
  return ref.watch(tenantPortalRepositoryProvider).myMeterReadings();
});

/// Individual lease + gated community.
final tenantLeaseDetailsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final session = await ref.watch(tenantSessionProvider.future);
  if (!(session.isIndividualLease || session.isGatedCommunity)) {
    return null;
  }
  return ref.watch(tenantPortalRepositoryProvider).leaseDetails();
});

/// Soft live-sync: invalidate only modules relevant to this archetype.
extension TenantLiveSync on WidgetRef {
  void refreshTenantLiveChannels(TenantSession session) {
    invalidate(myTenancyProvider);
    invalidate(tenantSessionProvider);
    invalidate(myComplaintsProvider);
    invalidate(myInvoicesProvider);

    switch (session.archetype) {
      case PropertyArchetype.sharedLiving:
        invalidate(tenantMessMenuProvider);
        break;
      case PropertyArchetype.gatedCommunity:
        invalidate(tenantGatePassesProvider);
        invalidate(tenantSocietyNoticesProvider);
        invalidate(tenantMeterReadingsProvider);
        invalidate(tenantLeaseDetailsProvider);
        break;
      case PropertyArchetype.individualLease:
        invalidate(tenantMeterReadingsProvider);
        invalidate(tenantLeaseDetailsProvider);
        break;
    }
  }
}
