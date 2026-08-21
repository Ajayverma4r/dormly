// features/subscription/presentation/subscription_provider.dart
//
// Global subscription state for the app session.
//
// USAGE:
//
//   // Full snapshot:
//   final subAsync = ref.watch(subscriptionProvider);
//
//   // Boolean feature check (instant, safe default = false while loading):
//   final canExport = ref.watch(canProvider('can_export_pdf'));
//
//   // Quota value (-1 = unlimited, 0 = no access):
//   final maxProperties = ref.watch(quotaProvider('max_properties'));
//
//   // Composite quota check:
//   final canCreate = ref.watch(hasQuotaProvider(('max_properties', 3)));
//
//   // Force refresh after payment:
//   ref.invalidate(subscriptionProvider);

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/subscription_repository.dart';
import '../domain/entitlement_snapshot.dart';
import '../domain/subscription_plan.dart';
import '../domain/subscription_status.dart';

// ---------------------------------------------------------------------------
// Core subscription record  (NOT autoDispose — cached for the whole session)
// ---------------------------------------------------------------------------

typedef SubscriptionRecord = ({
  SubscriptionStatus subscription,
  EntitlementSnapshot entitlements,
  bool trialEligible,
})?;

/// Fetches and caches the organization's subscription and entitlements.
/// Returns null when the user is not an org owner/admin (staff get 403).
/// Call `ref.invalidate(subscriptionProvider)` after a successful payment to
/// force a re-fetch.
final subscriptionProvider = FutureProvider<SubscriptionRecord>((ref) async {
  try {
    return await ref
        .watch(subscriptionRepositoryProvider)
        .fetchMySubscription();
  } on DioException catch (e) {
    // 401 = not logged in, 403 = staff/manager context — both are expected
    if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
      return null;
    }
    rethrow;
  }
});

// ---------------------------------------------------------------------------
// Public plans catalog  (autoDispose — only alive while paywall is open)
// ---------------------------------------------------------------------------

final plansProvider = FutureProvider.autoDispose<List<SubscriptionPlan>>((ref) {
  return ref.watch(subscriptionRepositoryProvider).fetchPublicPlans();
});

// ---------------------------------------------------------------------------
// Derived helpers — instant reads, safe defaults while loading
// ---------------------------------------------------------------------------

/// Convenience accessor for the EntitlementSnapshot (null-safe).
/// Returns EntitlementSnapshot.empty while loading or on error.
final entitlementsProvider = Provider<EntitlementSnapshot>((ref) {
  return ref.watch(subscriptionProvider).valueOrNull?.entitlements ??
      EntitlementSnapshot.empty;
});

/// `can('can_export_pdf')` — true only when feature is granted on the plan.
/// Safe default = false while loading.
final canProvider = Provider.family<bool, String>((ref, featureKey) {
  return ref.watch(entitlementsProvider).can(featureKey);
});

/// `quota('max_properties')` — numeric quota value, -1 = unlimited, 0 = locked.
final quotaProvider = Provider.family<int, String>((ref, quotaKey) {
  return ref.watch(entitlementsProvider).quota(quotaKey);
});

/// `hasQuotaProvider(('max_properties', currentCount))` — true when the org
/// can create more. Use on POST/CREATE actions only — reads are never blocked.
///
/// Example:
///   final ok = ref.watch(hasQuotaProvider(('max_properties', properties.length)));
///   if (!ok) { /* show upgrade prompt */ }
final hasQuotaProvider =
    Provider.family<bool, (String, int)>((ref, args) {
  final (quotaKey, currentCount) = args;
  return ref.watch(entitlementsProvider).hasQuota(quotaKey, currentCount);
});
