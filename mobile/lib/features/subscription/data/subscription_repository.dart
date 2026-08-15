// features/subscription/data/subscription_repository.dart
//
// All subscription-related API calls. Two logical groups:
//   1. Plans catalog (public, no auth)
//   2. Org subscription lifecycle (auth required)

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../domain/entitlement_snapshot.dart';
import '../domain/subscription_plan.dart';
import '../domain/subscription_status.dart';

final subscriptionRepositoryProvider = Provider<SubscriptionRepository>((ref) {
  return SubscriptionRepository(ref.watch(apiClientProvider));
});

class SubscriptionRepository {
  final ApiClient _client;
  SubscriptionRepository(this._client);

  // ---- Plans catalog (public) ----

  /// Fetches all publicly-listed active plans with their feature entitlements.
  /// Used by the paywall screen to render pricing cards dynamically.
  Future<List<SubscriptionPlan>> fetchPublicPlans() async {
    final res = await _client.dio.get('/v1/plans');
    final list = res.data['data'] as List;
    return list
        .map((e) => SubscriptionPlan.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---- Org subscription (auth required) ----

  /// Returns the active subscription state + full entitlement snapshot.
  /// Returns null for non-owner contexts (staff/manager tokens get 403).
  Future<({SubscriptionStatus subscription, EntitlementSnapshot entitlements})?> fetchMySubscription() async {
    final res = await _client.dio.get('/v1/subscriptions/me');
    final data = res.data['data'] as Map<String, dynamic>;

    final sub = SubscriptionStatus.fromJson(
        data['subscription'] as Map<String, dynamic>);
    final ent = EntitlementSnapshot.fromJson(
        data['entitlements'] as Map<String, dynamic>);

    return (subscription: sub, entitlements: ent);
  }

  /// Creates a Razorpay order for the given plan and billing cycle.
  /// Returns raw JSON with: orderId, amount (₹), amountPaise, currency, keyId.
  Future<Map<String, dynamic>> createOrder({
    required String planSlug,
    required String billingCycle, // 'monthly' | 'yearly'
  }) async {
    final res = await _client.dio.post('/v1/subscriptions/create-order', data: {
      'planSlug': planSlug,
      'billingCycle': billingCycle,
    });
    return Map<String, dynamic>.from(res.data['data']);
  }

  /// Cancels the subscription at the end of the current billing period.
  Future<void> cancelSubscription() async {
    await _client.dio.post('/v1/subscriptions/cancel');
  }

  /// Fetches the last 50 subscription change events for audit display.
  Future<List<Map<String, dynamic>>> fetchHistory() async {
    final res = await _client.dio.get('/v1/subscriptions/history');
    return List<Map<String, dynamic>>.from(res.data['data']);
  }
}
