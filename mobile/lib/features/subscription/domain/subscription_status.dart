// features/subscription/domain/subscription_status.dart
//
// Represents the live subscription state for an organization.
// Built from the `subscription` field of GET /v1/subscriptions/me.
// All date arithmetic is computed here — screens never touch raw strings.

class SubscriptionStatus {
  final String planSlug;
  final String planName;

  /// 'trialing' | 'active' | 'past_due' | 'cancelled' | 'expired'
  final String status;

  final double priceInrMonthly;
  final double priceInrYearly;
  final DateTime? trialEndsAt;
  final DateTime? currentPeriodEnd;
  final DateTime? gracePeriodEndsAt;
  final bool cancelAtPeriodEnd;

  /// Razorpay AutoPay / eMandate will charge at period end.
  final bool autoRenew;

  /// Mandate token is linked (future AutoPay readiness).
  final bool mandateActive;

  const SubscriptionStatus({
    required this.planSlug,
    required this.planName,
    required this.status,
    required this.priceInrMonthly,
    required this.priceInrYearly,
    this.trialEndsAt,
    this.currentPeriodEnd,
    this.gracePeriodEndsAt,
    this.cancelAtPeriodEnd = false,
    this.autoRenew = false,
    this.mandateActive = false,
  });

  factory SubscriptionStatus.fromJson(Map<String, dynamic> json) {
    return SubscriptionStatus(
      planSlug: json['plan_slug'] as String? ?? 'free',
      planName: json['plan_name'] as String? ?? 'Free',
      status: json['status'] as String? ?? 'expired',
      priceInrMonthly:
          double.tryParse(json['price_inr_monthly']?.toString() ?? '0') ?? 0,
      priceInrYearly:
          double.tryParse(json['price_inr_yearly']?.toString() ?? '0') ?? 0,
      trialEndsAt: json['trial_ends_at'] != null
          ? DateTime.tryParse(json['trial_ends_at'] as String)
          : null,
      currentPeriodEnd: json['current_period_end'] != null
          ? DateTime.tryParse(json['current_period_end'] as String)
          : null,
      gracePeriodEndsAt: json['grace_period_ends_at'] != null
          ? DateTime.tryParse(json['grace_period_ends_at'] as String)
          : null,
      cancelAtPeriodEnd: json['cancel_at_period_end'] as bool? ?? false,
      autoRenew: json['auto_renew'] as bool? ?? false,
      mandateActive: json['mandate_active'] as bool? ?? false,
    );
  }

  // ---- Computed booleans ----

  bool get isTrial => status == 'trialing';
  bool get isActive => status == 'active';
  bool get isPastDue => status == 'past_due';
  bool get isCancelled => status == 'cancelled';
  bool get isExpired => status == 'expired';
  bool get isPro => isActive || isTrial || isPastDue || isCancelled;

  /// Effective AutoPay: mandate on and user has not cancelled at period end.
  bool get willAutoRenew =>
      (autoRenew || mandateActive) && !cancelAtPeriodEnd && isPro;

  /// Expiry used for countdown (trial end or paid period end).
  DateTime? get expiresAt {
    if (isTrial) return trialEndsAt ?? currentPeriodEnd;
    if (isActive || isCancelled || isPastDue) return currentPeriodEnd;
    return null;
  }

  /// Whole days remaining until [expiresAt]. Null when not applicable.
  int? get daysLeftUntilExpiry {
    final end = expiresAt;
    if (end == null || !isPro) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final endDay = DateTime(end.year, end.month, end.day);
    return endDay.difference(today).inDays;
  }

  /// Days remaining in the trial. 0 when not trialing or already expired.
  int get trialDaysLeft {
    if (!isTrial || trialEndsAt == null) return 0;
    return trialEndsAt!.difference(DateTime.now()).inDays.clamp(0, 30);
  }

  /// The next renewal date (null when on free or expired).
  DateTime? get renewsAt =>
      (isActive || isCancelled) ? currentPeriodEnd : null;

  /// Grace period days remaining after a payment failure.
  int get graceDaysLeft {
    if (!isPastDue || gracePeriodEndsAt == null) return 0;
    return gracePeriodEndsAt!.difference(DateTime.now()).inDays.clamp(0, 7);
  }

  /// Human-readable label shown in plan badges.
  String get statusLabel {
    switch (status) {
      case 'trialing':
        return 'Trial ($trialDaysLeft days left)';
      case 'active':
        return cancelAtPeriodEnd ? 'Cancels on expiry' : 'Active';
      case 'past_due':
        return 'Payment overdue';
      case 'cancelled':
        return 'Cancelled';
      case 'expired':
        return 'Expired';
      default:
        return status;
    }
  }

  static String formatExpiryDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}
