// features/subscription/domain/entitlement_snapshot.dart
//
// Resolved entitlements for the active organization. Built from the
// `entitlements` field of GET /v1/subscriptions/me.
//
// GOLDEN RULE: screens/widgets NEVER check planSlug or subscriptionStatus
// directly. They call can() or hasQuota() only.

class EntitlementSnapshot {
  final String planSlug;
  final String subscriptionStatus;
  final DateTime? trialEndsAt;
  final DateTime? currentPeriodEnd;
  final DateTime? gracePeriodEndsAt;

  /// Boolean features (e.g. can_export_pdf → true/false).
  final Map<String, bool> boolFeatures;

  /// Numeric quota features (e.g. max_properties → 1 or -1 for unlimited).
  final Map<String, int> quotaFeatures;

  const EntitlementSnapshot({
    required this.planSlug,
    required this.subscriptionStatus,
    required this.boolFeatures,
    required this.quotaFeatures,
    this.trialEndsAt,
    this.currentPeriodEnd,
    this.gracePeriodEndsAt,
  });

  factory EntitlementSnapshot.fromJson(Map<String, dynamic> json) {
    final rawFeatures =
        (json['features'] as Map<String, dynamic>?) ?? {};

    final boolFeatures = <String, bool>{};
    final quotaFeatures = <String, int>{};

    rawFeatures.forEach((key, value) {
      if (value is bool) {
        boolFeatures[key] = value;
      } else if (value is num) {
        quotaFeatures[key] = value.toInt();
      }
    });

    return EntitlementSnapshot(
      planSlug: json['planSlug'] as String? ?? 'free',
      subscriptionStatus: json['subscriptionStatus'] as String? ?? 'expired',
      boolFeatures: boolFeatures,
      quotaFeatures: quotaFeatures,
      trialEndsAt: json['trialEndsAt'] != null
          ? DateTime.tryParse(json['trialEndsAt'] as String)
          : null,
      currentPeriodEnd: json['currentPeriodEnd'] != null
          ? DateTime.tryParse(json['currentPeriodEnd'] as String)
          : null,
      gracePeriodEndsAt: json['gracePeriodEndsAt'] != null
          ? DateTime.tryParse(json['gracePeriodEndsAt'] as String)
          : null,
    );
  }

  // ---- Feature checks — the ONLY API screens should call ----

  /// Returns true if the active plan grants the given boolean feature.
  ///
  /// Example:
  ///   if (entitlements.can('can_export_pdf')) { ... }
  bool can(String featureKey) => boolFeatures[featureKey] == true;

  /// Returns the numeric quota for a resource type.
  ///   -1 → unlimited
  ///    0 → feature not on plan (treat as no access)
  ///   >0 → concrete limit
  int quota(String quotaKey) => quotaFeatures[quotaKey] ?? 0;

  /// Returns true if the org can still create more of a resource.
  /// Handles -1 (unlimited) correctly. Apply only on CREATE paths — reads
  /// are never blocked (graceful downgrade policy).
  ///
  /// Example:
  ///   if (entitlements.hasQuota('max_properties', currentPropertyCount)) {
  ///     // allow creation
  ///   }
  bool hasQuota(String quotaKey, int currentCount) {
    final q = quota(quotaKey);
    if (q == -1) return true;  // unlimited
    if (q == 0) return false;  // not on plan
    return currentCount < q;
  }

  /// Returns the quota limit as a display string. "-1" becomes "∞".
  String quotaLabel(String quotaKey) {
    final q = quota(quotaKey);
    return q == -1 ? '∞' : q.toString();
  }

  /// Ratio of currentCount / quota. Returns 0.0 when quota is unlimited or 0.
  double quotaRatio(String quotaKey, int currentCount) {
    final q = quota(quotaKey);
    if (q <= 0) return 0.0;
    return (currentCount / q).clamp(0.0, 1.0);
  }

  /// Free plan with everything locked — used as safe fallback before data loads.
  static EntitlementSnapshot get empty => const EntitlementSnapshot(
        planSlug: 'free',
        subscriptionStatus: 'expired',
        boolFeatures: {},
        quotaFeatures: {},
      );
}
