// features/subscription/domain/subscription_plan.dart
//
// A single plan from GET /v1/plans. Plans are used by the paywall screen
// to render pricing cards and the feature comparison table dynamically.

class SubscriptionPlan {
  final String id;
  final String slug;
  final String displayName;
  final String? description;
  final double priceInrMonthly;
  final double priceInrYearly;
  final double? originalPriceInrMonthly;
  final double? originalPriceInrYearly;
  final int trialDays;
  final int sortOrder;

  /// Feature entitlement map for this plan.
  ///   bool features  → bool  (e.g. 'can_export_pdf': true)
  ///   quota features → int   (e.g. 'max_properties': -1)
  final Map<String, dynamic> features;

  const SubscriptionPlan({
    required this.id,
    required this.slug,
    required this.displayName,
    this.description,
    required this.priceInrMonthly,
    required this.priceInrYearly,
    this.originalPriceInrMonthly,
    this.originalPriceInrYearly,
    required this.trialDays,
    required this.sortOrder,
    required this.features,
  });

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) {
    double? parseOptional(dynamic v) {
      if (v == null) return null;
      return double.tryParse(v.toString());
    }

    return SubscriptionPlan(
      id: json['id'] as String,
      slug: json['slug'] as String,
      displayName: json['displayName'] as String? ??
          json['display_name'] as String? ??
          '',
      description: json['description'] as String?,
      priceInrMonthly: double.tryParse(
              json['priceInrMonthly']?.toString() ??
                  json['price_inr_monthly']?.toString() ??
                  '0') ??
          0,
      priceInrYearly: double.tryParse(
              json['priceInrYearly']?.toString() ??
                  json['price_inr_yearly']?.toString() ??
                  '0') ??
          0,
      originalPriceInrMonthly: parseOptional(
          json['originalPriceInrMonthly'] ?? json['original_price_inr_monthly']),
      originalPriceInrYearly: parseOptional(
          json['originalPriceInrYearly'] ?? json['original_price_inr_yearly']),
      trialDays: (json['trialDays'] ?? json['trial_days'] ?? 0) as int,
      sortOrder: (json['sortOrder'] ?? json['sort_order'] ?? 0) as int,
      features: Map<String, dynamic>.from(
          (json['features'] as Map<String, dynamic>?) ?? {}),
    );
  }

  bool get isFree => priceInrMonthly == 0 && priceInrYearly == 0;

  /// Early Bird strike-through fallbacks when API has not migrated yet.
  double get strikeMonthly =>
      originalPriceInrMonthly ?? (slug == 'pro_monthly' ? 199 : 199);

  double get strikeYearly =>
      originalPriceInrYearly ?? (slug == 'pro_yearly' ? 1999 : 1999);

  bool featureBool(String key) => features[key] == true;

  int featureQuota(String key) {
    final v = features[key];
    if (v is num) return v.toInt();
    return 0;
  }

  String featureQuotaLabel(String key) {
    final q = featureQuota(key);
    return q == -1 ? '∞' : q.toString();
  }
}
