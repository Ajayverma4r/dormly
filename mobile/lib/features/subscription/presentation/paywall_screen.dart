// features/subscription/presentation/paywall_screen.dart
//
// Dynamic pricing / upgrade screen. Fetches live plan data from the backend
// so pricing and feature lists never need an app update.
//
// Flow:
//   1. Load plans from GET /v1/plans
//   2. User picks monthly / yearly toggle
//   3. Tap "Upgrade" → POST /v1/subscriptions/create-order
//   4. Open Razorpay checkout sheet
//   5. On success → invalidate subscriptionProvider + pop

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../data/subscription_repository.dart';
import '../domain/subscription_plan.dart';
import 'subscription_provider.dart';

// ── Feature rows shown in the comparison table ──────────────────────────────
// This list is the only place where feature display order is defined.
// The actual values come from the plan.features map (no hardcoding of limits).
const _kComparisonFeatures = [
  ('max_properties',          'Properties',          false),
  ('max_rooms',               'Rooms / Units',       false),
  ('max_staff_members',       'Staff Members',       false),
  ('can_use_analytics',       'Analytics Dashboard', true),
  ('can_access_reports',      'Reports',             true),
  ('can_export_pdf',          'Export PDF',          true),
  ('can_export_csv',          'Export CSV',          true),
  ('can_send_reminders',      'Automated Reminders', true),
  ('can_use_bulk_actions',    'Bulk Actions',        true),
  ('can_custom_charge_types', 'Custom Charges',      true),
  ('can_view_audit_log',      'Audit Log',           true),
  ('ads_enabled',             'Ad-Free',             true),
];
// (featureKey, displayLabel, isBool)
// isBool = false → render as quota label (∞, 1, 20…)
// isBool = true  → render as check / cross icon

// ── Paywall screen ───────────────────────────────────────────────────────────

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

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

  // ── Razorpay callbacks ────────────────────────────────────────────────────

  void _onPaymentSuccess(PaymentSuccessResponse response) {
    // The backend webhook processes the payment asynchronously.
    // Invalidate here so the subscription UI refreshes.
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

  // ── Order creation ────────────────────────────────────────────────────────

  Future<void> _upgrade(SubscriptionPlan plan) async {
    if (_orderLoading) return;
    setState(() => _orderLoading = true);

    try {
      final order = await ref
          .read(subscriptionRepositoryProvider)
          .createOrder(
            planSlug: plan.slug,
            billingCycle: _yearly ? 'yearly' : 'monthly',
          );

      _razorpay.open({
        'key': order['keyId'] as String,
        'amount': order['amountPaise'] as int,
        'currency': 'INR',
        'name': 'Dormly',
        'description':
            '${plan.displayName} — ${_yearly ? 'Yearly' : 'Monthly'}',
        'order_id': order['orderId'] as String,
        'theme': {'color': '#2451B4'},
        'modal': {'confirm_close': true},
      });
      // _orderLoading stays true until a Razorpay callback fires
    } catch (e) {
      if (!mounted) return;
      setState(() => _orderLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start payment: $e')),
      );
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final plansAsync = ref.watch(plansProvider);
    final currentSub = ref.watch(subscriptionProvider).valueOrNull;
    final currentSlug = currentSub?.subscription.planSlug ?? 'free';

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('Choose a Plan'),
        backgroundColor: AppColors.canvas,
      ),
      body: plansAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
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
          onToggleBilling: (v) => setState(() => _yearly = v),
          onUpgrade: _upgrade,
          orderLoading: _orderLoading,
        ),
      ),
    );
  }
}

// ── Plan body ─────────────────────────────────────────────────────────────────

class _PlanBody extends StatelessWidget {
  final List<SubscriptionPlan> plans;
  final String currentSlug;
  final bool yearly;
  final ValueChanged<bool> onToggleBilling;
  final Future<void> Function(SubscriptionPlan) onUpgrade;
  final bool orderLoading;

  const _PlanBody({
    required this.plans,
    required this.currentSlug,
    required this.yearly,
    required this.onToggleBilling,
    required this.onUpgrade,
    required this.orderLoading,
  });

  @override
  Widget build(BuildContext context) {
    // Filter to paid plans only for the upgrade CTA (free is shown in table)
    final paidPlans = plans
        .where((p) => !p.isFree && (p.slug == 'pro_monthly' || p.slug == 'pro_yearly'))
        .toList();

    // For comparison table, show free + first paid plan
    final allPlans = plans;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Hero header
          _HeroHeader(currentSlug: currentSlug),
          const SizedBox(height: 20),

          // Billing cycle toggle
          _BillingToggle(yearly: yearly, onToggle: onToggleBilling),
          const SizedBox(height: 20),

          // Pricing cards (paid plans only)
          for (final plan in paidPlans) ...[
            _PricingCard(
              plan: plan,
              yearly: yearly,
              isCurrent: plan.slug.contains(
                  currentSlug == 'pro_monthly' || currentSlug == 'pro_yearly'
                      ? currentSlug.replaceFirst('pro_', '')
                      : '__never__'),
              orderLoading: orderLoading,
              onUpgrade: () => onUpgrade(plan),
            ),
            const SizedBox(height: 12),
          ],

          const SizedBox(height: 8),

          // Feature comparison table
          _FeatureTable(plans: allPlans),

          const SizedBox(height: 24),
          _FooterNote(),
        ],
      ),
    );
  }
}

// ── Hero header ───────────────────────────────────────────────────────────────

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
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Unlock Your\nFull Potential',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Manage unlimited properties, automate reminders,\nand export professional reports.',
            style: TextStyle(
                color: Colors.white70, fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }
}

// ── Billing toggle ────────────────────────────────────────────────────────────

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
                        'Save 17%',
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

// ── Pricing card ──────────────────────────────────────────────────────────────

class _PricingCard extends StatelessWidget {
  final SubscriptionPlan plan;
  final bool yearly;
  final bool isCurrent;
  final bool orderLoading;
  final VoidCallback onUpgrade;

  const _PricingCard({
    required this.plan,
    required this.yearly,
    required this.isCurrent,
    required this.orderLoading,
    required this.onUpgrade,
  });

  @override
  Widget build(BuildContext context) {
    final price = yearly ? plan.priceInrYearly : plan.priceInrMonthly;
    final monthlyEquiv =
        yearly ? (plan.priceInrYearly / 12).round() : plan.priceInrMonthly.round();
    final isProYearly = plan.slug == 'pro_yearly';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCurrent
              ? AppColors.blueprint
              : AppColors.hairline,
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
                if (isCurrent)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
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
                if (isProYearly && !isCurrent)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
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
              ],
            ),
            if (plan.description != null) ...[
              const SizedBox(height: 4),
              Text(plan.description!,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.slate)),
            ],
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₹$monthlyEquiv',
                  style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink),
                ),
                const SizedBox(width: 4),
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Text('/mo',
                      style:
                          TextStyle(color: AppColors.slate, fontSize: 14)),
                ),
                if (yearly) ...[
                  const Spacer(),
                  Text(
                    '₹${price.round()} billed yearly',
                    style: const TextStyle(
                        color: AppColors.slate, fontSize: 12),
                  ),
                ],
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
                                  strokeWidth: 2,
                                  color: Colors.white),
                            )
                          : Text(
                              'Upgrade to ${plan.displayName}',
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

// ── Feature comparison table ──────────────────────────────────────────────────

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
          // Header row
          _TableHeader(plans: plans),
          const Divider(height: 1, color: AppColors.hairline),
          // Feature rows
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
                  color:
                      p.isFree ? AppColors.slate : AppColors.blueprint,
                  letterSpacing: 0.3,
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
                  ? _BoolCell(value: p.featureBool(featureKey), featureKey: featureKey)
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
    // Invert display for ads_enabled: free has ads (bad), pro has no ads (good)
    final displayPositive =
        featureKey == 'ads_enabled' ? !value : value;

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

// ── Footer ────────────────────────────────────────────────────────────────────

class _FooterNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Text(
      'Payments are processed securely via Razorpay.\n'
      'Cancel anytime — no questions asked.',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 12, color: AppColors.slate, height: 1.6),
    );
  }
}
