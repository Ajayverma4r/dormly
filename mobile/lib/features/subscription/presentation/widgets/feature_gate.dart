// features/subscription/presentation/widgets/feature_gate.dart
//
// Wraps any child widget with a plan-based access gate.
//
// USAGE:
//
//   FeatureGate(
//     featureKey: 'can_export_pdf',
//     child: ExportButton(),
//   )
//
//   // Custom locked UI:
//   FeatureGate(
//     featureKey: 'can_use_analytics',
//     lockedChild: MyCustomUpgradeCard(),
//     child: AnalyticsDashboard(),
//   )
//
// While the subscription is loading, the child is shown optimistically.
// Once loaded, the child is shown only if the feature is granted.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../subscription_provider.dart';
import '../paywall_screen.dart';

class FeatureGate extends ConsumerWidget {
  /// The feature key to check (e.g. 'can_export_pdf').
  final String featureKey;

  /// Widget shown when the feature IS granted (or while loading).
  final Widget child;

  /// Optional custom widget shown when the feature is NOT granted.
  /// Defaults to [_LockedCard].
  final Widget? lockedChild;

  /// Human-readable feature label for the lock card.
  final String? featureLabel;

  const FeatureGate({
    super.key,
    required this.featureKey,
    required this.child,
    this.lockedChild,
    this.featureLabel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subAsync = ref.watch(subscriptionProvider);

    return subAsync.when(
      // Show child while loading — prevents flicker/layout shift
      loading: () => child,
      // Show child on error — don't accidentally lock legitimate users
      error: (_, __) => child,
      data: (sub) {
        final granted =
            sub == null || sub.entitlements.can(featureKey);
        if (granted) return child;
        return lockedChild ??
            _LockedCard(featureKey: featureKey, label: featureLabel);
      },
    );
  }
}

class _LockedCard extends StatelessWidget {
  final String featureKey;
  final String? label;

  const _LockedCard({required this.featureKey, this.label});

  @override
  Widget build(BuildContext context) {
    final displayLabel = label ??
        featureKey
            .replaceAll('can_', '')
            .replaceAll('_', ' ')
            .split(' ')
            .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
            .join(' ');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.blueprint.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.lock_outline,
                size: 22, color: AppColors.blueprint),
          ),
          const SizedBox(height: 12),
          Text(
            displayLabel,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Not available on your current plan.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.slate),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.blueprint,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PaywallScreen()),
              ),
              child: const Text(
                'Upgrade to Pro',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
