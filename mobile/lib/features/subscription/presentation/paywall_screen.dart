// features/subscription/presentation/paywall_screen.dart
//
// Early Bird pricing + 30-day free trial + test-mode payment bypass.
// Property monetization / free-tier ads are unchanged — trial & paid use
// existing isPaidPlan / FeatureGate / AdBannerGate paths.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../data/subscription_repository.dart';
import '../domain/subscription_plan.dart';
import 'subscription_provider.dart';

const _kComparisonFeatures = [
  ('max_properties', 'Properties', false),
  ('max_rooms', 'Rooms / Units', false),
  ('max_staff_members', 'Staff Members', false),
  ('can_use_analytics', 'Analytics Dashboard', true),
  ('can_access_reports', 'Reports', true),
  ('can_export_pdf', 'Export PDF', true),
  ('can_export_csv', 'Export CSV', true),
  ('can_send_reminders', 'Automated Reminders', true),
  ('can_use_bulk_actions', 'Bulk Actions', true),
  ('can_custom_charge_types', 'Custom Charges', true),
  ('can_view_audit_log', 'Audit Log', true),
  ('ads_enabled', 'Ad-Free', true),
];

class PaywallScreen extends ConsumerStatefulWidget {
  /// Optional context shown under the Early Bird header (e.g. expired lock).
  final String? reason;

  const PaywallScreen({super.key, this.reason});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  bool _yearly = false;
  bool _orderLoading = false;
  late final Razorpay _razorpay;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  void _onPaymentSuccess(PaymentSuccessResponse response) {
    ref.invalidate(subscriptionProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Payment successful! Your plan is being upgraded.'),
        backgroundColor: AppColors.positive,
      ),
    );
    Navigator.of(context).pop();
  }

  void _onPaymentError(PaymentFailureResponse response) {
    if (!mounted) return;
    setState(() => _orderLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Payment failed: ${response.message ?? 'Unknown error'}'),
        backgroundColor: AppColors.danger,
      ),
    );
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    if (!mounted) return;
    setState(() => _orderLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('External wallet: ${response.walletName}')),
    );
  }

  Future<void> _completeUpgrade({
    required String planSlug,
    required String billingCycle,
  }) async {
    try {
      await ref.read(subscriptionRepositoryProvider).testActivate(
            planSlug: planSlug,
            billingCycle: billingCycle,
          );
      ref.invalidate(subscriptionProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            billingCycle == 'yearly'
                ? '✅ Pro Yearly activated (test payment)!'
                : '✅ Pro Monthly activated (test payment)!',
          ),
          backgroundColor: AppColors.positive,
        ),
      );
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _orderLoading = false);
    }
  }

  Future<void> _upgrade(SubscriptionPlan plan) async {
    if (_orderLoading) return;
    setState(() => _orderLoading = true);

    final billingCycle =
        plan.slug == 'pro_yearly' || _yearly ? 'yearly' : 'monthly';
    final planSlug =
        billingCycle == 'yearly' ? 'pro_yearly' : 'pro_monthly';

    try {
      final order = await ref.read(subscriptionRepositoryProvider).createOrder(
            planSlug: planSlug,
            billingCycle: billingCycle,
          );

      // Test / placeholder keys: simulate Razorpay success → activate immediately.
      if (order['testMode'] == true) {
        await _completeUpgrade(planSlug: planSlug, billingCycle: billingCycle);
        return;
      }

      _razorpay.open({
        'key': order['keyId'] as String,
        'amount': order['amountPaise'] as int,
        'currency': 'INR',
        'name': 'Dormly',
        'description':
            '${plan.displayName} — ${billingCycle == 'yearly' ? 'Yearly' : 'Monthly'}',
        'order_id': order['orderId'] as String,
        'theme': {'color': '#2451B4'},
        'modal': {'confirm_close': true},
      });
      // Loading stays true until Razorpay success/error callback.
    } catch (e) {
      if (!mounted) return;
      setState(() => _orderLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start payment: $e')),
      );
    }
  }

  Future<void> _startTrial() async {
    if (_orderLoading) return;
    setState(() => _orderLoading = true);
    try {
      await ref.read(subscriptionRepositoryProvider).startFreeTrial();
      ref.invalidate(subscriptionProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎉 30-day free trial started — enjoy Pro!'),
          backgroundColor: AppColors.positive,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start trial: $e')),
      );
    } finally {
      if (mounted) setState(() => _orderLoading = false);
    }
  }

  Future<void> _testActivate() async {
    if (_orderLoading) return;
    setState(() => _orderLoading = true);
    try {
      await _completeUpgrade(
        planSlug: _yearly ? 'pro_yearly' : 'pro_monthly',
        billingCycle: _yearly ? 'yearly' : 'monthly',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Test activate failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _orderLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plansAsync = ref.watch(plansProvider);
    final currentSub = ref.watch(subscriptionProvider).valueOrNull;
    final currentSlug = currentSub?.subscription.planSlug ?? 'free';
    final isTrialing = currentSub?.subscription.isTrial ?? false;
    final trialEligible = currentSub?.trialEligible ?? false;
    final trialDaysLeft = currentSub?.subscription.trialDaysLeft ?? 0;

    // Active trial users should not need the paywall — show a short status card.
    if (isTrialing) {
      return Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: AppBar(
          title: const Text('Your Plan'),
          backgroundColor: AppColors.canvas,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.verified, size: 56, color: AppColors.positive),
                const SizedBox(height: 16),
                Text(
                  'Pro Trial Active',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$trialDaysLeft days left · full Pro access, no ads',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.slate, height: 1.4),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Continue'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('Choose a Plan'),
        backgroundColor: AppColors.canvas,
      ),
      body: plansAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off_outlined,
                    size: 48, color: AppColors.slate),
                const SizedBox(height: 16),
                const Text('Could not load plans',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: AppColors.ink)),
                const SizedBox(height: 8),
                Text('$err',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppColors.slate, fontSize: 13)),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => ref.invalidate(plansProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (plans) => _PlanBody(
          plans: plans,
          currentSlug: currentSlug,
          yearly: _yearly,
          trialEligible: trialEligible,
          reason: widget.reason,
          onToggleBilling: (v) => setState(() => _yearly = v),
          onUpgrade: _upgrade,
          onStartTrial: _startTrial,
          onTestActivate: _testActivate,
          orderLoading: _orderLoading,
        ),
      ),
    );
  }
}

class _PlanBody extends StatelessWidget {
  final List<SubscriptionPlan> plans;
  final String currentSlug;
  final bool yearly;
  final bool trialEligible;
  final String? reason;
  final ValueChanged<bool> onToggleBilling;
  final Future<void> Function(SubscriptionPlan) onUpgrade;
  final Future<void> Function() onStartTrial;
  final Future<void> Function() onTestActivate;
  final bool orderLoading;

  const _PlanBody({
    required this.plans,
    required this.currentSlug,
    required this.yearly,
    required this.trialEligible,
    this.reason,
    required this.onToggleBilling,
    required this.onUpgrade,
    required this.onStartTrial,
    required this.onTestActivate,
    required this.orderLoading,
  });

  @override
  Widget build(BuildContext context) {
    final monthly = plans.where((p) => p.slug == 'pro_monthly').toList();
    final yearlyPlans = plans.where((p) => p.slug == 'pro_yearly').toList();
    final paidPlans = [
      if (monthly.isNotEmpty) monthly.first,
      if (yearlyPlans.isNotEmpty) yearlyPlans.first,
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HeroHeader(currentSlug: currentSlug),
          if (reason != null && reason!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFDBA74)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lock_outline,
                      color: Color(0xFFB45309), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      reason!,
                      style: const TextStyle(
                        color: Color(0xFF9A3412),
                        fontSize: 13,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),

          if (trialEligible) ...[
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: orderLoading ? null : onStartTrial,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.positive,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: orderLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(
                        'Start 30-Day Free Trial (No Credit Card Required)',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 14),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Or unlock Early Bird pricing below',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.slate, fontSize: 12),
            ),
            const SizedBox(height: 16),
          ],

          _BillingToggle(yearly: yearly, onToggle: onToggleBilling),
          const SizedBox(height: 16),

          for (final plan in paidPlans) ...[
            _PricingCard(
              plan: plan,
              isCurrent: plan.slug == currentSlug,
              orderLoading: orderLoading,
              onUpgrade: () => onUpgrade(plan),
            ),
            const SizedBox(height: 12),
          ],

          _TestActivateButton(onTap: onTestActivate, loading: orderLoading),
          const SizedBox(height: 20),
          _FeatureTable(plans: plans),
          const SizedBox(height: 24),
          const _FooterNote(),
        ],
      ),
    );
  }
}

class _HeroHeader extends StatelessWidget {
  final String currentSlug;
  const _HeroHeader({required this.currentSlug});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A3A8F), AppColors.blueprint],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFC857),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'EARLY BIRD DEAL',
                  style: TextStyle(
                    color: Color(0xFF1A3A8F),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Current: ${currentSlug.replaceAll('_', ' ').toUpperCase()}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Launch pricing\nfor early adopters',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Unlimited commercial properties, reports, and an ad-free experience.',
            style:
                TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _BillingToggle extends StatelessWidget {
  final bool yearly;
  final ValueChanged<bool> onToggle;
  const _BillingToggle({required this.yearly, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          Expanded(child: _Tab('Monthly', !yearly, () => onToggle(false))),
          Expanded(
            child: Stack(
              alignment: Alignment.centerRight,
              children: [
                _Tab('Yearly', yearly, () => onToggle(true)),
                if (!yearly)
                  Positioned(
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.positive,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Best value',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _Tab(this.label, this.active, this.onTap);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: active ? AppColors.blueprint : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : AppColors.slate,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

class _PricingCard extends StatelessWidget {
  final SubscriptionPlan plan;
  final bool isCurrent;
  final bool orderLoading;
  final VoidCallback onUpgrade;

  const _PricingCard({
    required this.plan,
    required this.isCurrent,
    required this.orderLoading,
    required this.onUpgrade,
  });

  @override
  Widget build(BuildContext context) {
    final isYearly = plan.slug == 'pro_yearly';
    final price = isYearly ? plan.priceInrYearly : plan.priceInrMonthly;
    final strike = isYearly ? plan.strikeYearly : plan.strikeMonthly;
    final period = isYearly ? '/year' : '/month';
    final payLabel = isYearly
        ? 'Pay ₹${price.round()}/year'
        : 'Pay ₹${price.round()}/month';

    // Fallback display if DB still has old prices
    final displayPrice = price > 0
        ? price
        : (isYearly ? 999.0 : 99.0);
    final displayStrike = strike > displayPrice ? strike : (isYearly ? 1999.0 : 199.0);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCurrent ? AppColors.blueprint : AppColors.hairline,
          width: isCurrent ? 2 : 1,
        ),
        boxShadow: isCurrent
            ? [
                BoxShadow(
                  color: AppColors.blueprint.withOpacity(0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                )
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(plan.displayName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: AppColors.ink)),
                const Spacer(),
                if (isYearly && !isCurrent)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.positive.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('Best Value',
                        style: TextStyle(
                            color: AppColors.positive,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ),
                if (isCurrent)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.blueprint.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('Current',
                        style: TextStyle(
                            color: AppColors.blueprint,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₹${displayStrike.round()}',
                  style: const TextStyle(
                    fontSize: 18,
                    color: AppColors.slate,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '₹${displayPrice.round()}',
                  style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink),
                ),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(period,
                      style: const TextStyle(
                          color: AppColors.slate, fontSize: 14)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: isCurrent
                  ? OutlinedButton(
                      onPressed: null,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.hairline),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Current Plan',
                          style: TextStyle(color: AppColors.slate)),
                    )
                  : ElevatedButton(
                      onPressed: orderLoading ? null : onUpgrade,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.blueprint,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: orderLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Text(
                              payLabel,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700),
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureTable extends StatelessWidget {
  final List<SubscriptionPlan> plans;
  const _FeatureTable({required this.plans});

  @override
  Widget build(BuildContext context) {
    if (plans.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _TableHeader(plans: plans),
          const Divider(height: 1, color: AppColors.hairline),
          for (int i = 0; i < _kComparisonFeatures.length; i++) ...[
            _FeatureRow(
              feature: _kComparisonFeatures[i],
              plans: plans,
              shaded: i.isEven,
            ),
            if (i < _kComparisonFeatures.length - 1)
              const Divider(height: 1, color: AppColors.hairline),
          ],
        ],
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  final List<SubscriptionPlan> plans;
  const _TableHeader({required this.plans});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.canvas,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          const Expanded(
            flex: 3,
            child: Text('Feature',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: AppColors.slate,
                    letterSpacing: 0.4)),
          ),
          ...plans.map(
            (p) => Expanded(
              flex: 2,
              child: Text(
                p.displayName,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: p.isFree ? AppColors.slate : AppColors.blueprint,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final (String, String, bool) feature;
  final List<SubscriptionPlan> plans;
  final bool shaded;

  const _FeatureRow({
    required this.feature,
    required this.plans,
    required this.shaded,
  });

  @override
  Widget build(BuildContext context) {
    final (featureKey, label, isBool) = feature;

    return Container(
      color: shaded ? AppColors.canvas.withOpacity(0.5) : AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.ink, height: 1.3)),
          ),
          ...plans.map(
            (p) => Expanded(
              flex: 2,
              child: isBool
                  ? _BoolCell(
                      value: p.featureBool(featureKey), featureKey: featureKey)
                  : _QuotaCell(label: p.featureQuotaLabel(featureKey)),
            ),
          ),
        ],
      ),
    );
  }
}

class _BoolCell extends StatelessWidget {
  final bool value;
  final String featureKey;
  const _BoolCell({required this.value, required this.featureKey});

  @override
  Widget build(BuildContext context) {
    final displayPositive = featureKey == 'ads_enabled' ? !value : value;
    return Center(
      child: Icon(
        displayPositive ? Icons.check_circle_outline : Icons.remove,
        size: 18,
        color: displayPositive ? AppColors.positive : AppColors.hairline,
      ),
    );
  }
}

class _QuotaCell extends StatelessWidget {
  final String label;
  const _QuotaCell({required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: label == '∞' ? AppColors.positive : AppColors.ink,
        ),
      ),
    );
  }
}

class _TestActivateButton extends StatelessWidget {
  final Future<void> Function() onTap;
  final bool loading;
  const _TestActivateButton({required this.onTap, required this.loading});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: loading ? null : onTap,
      icon: const Icon(Icons.science_outlined, size: 16),
      label: const Text('Test: Activate Pro (no payment)'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.caution,
        side: BorderSide(color: AppColors.caution.withOpacity(0.5)),
        padding: const EdgeInsets.symmetric(vertical: 12),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _FooterNote extends StatelessWidget {
  const _FooterNote();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Early Bird prices are limited-time launch rates.\n'
      'In test mode, Pay buttons simulate a successful Razorpay checkout.',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 12, color: AppColors.slate, height: 1.6),
    );
  }
}
