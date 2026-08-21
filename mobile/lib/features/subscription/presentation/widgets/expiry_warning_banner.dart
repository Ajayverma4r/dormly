// features/subscription/presentation/widgets/expiry_warning_banner.dart
//
// Premium / trial expiry countdown for dashboards.
//
// • Manual renew (no AutoPay) + days_left ≤ 7 → orange CTA → PaywallScreen
// • AutoPay active → subtle info line (or hide when days_left > 7)
// • Free / expired → hidden

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/subscription_status.dart';
import '../paywall_screen.dart';
import '../subscription_provider.dart';

class ExpiryWarningBanner extends ConsumerWidget {
  const ExpiryWarningBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = ref.watch(subscriptionProvider).valueOrNull;
    if (record == null) return const SizedBox.shrink();

    final sub = record.subscription;
    if (!sub.isPro || sub.planSlug == 'free') return const SizedBox.shrink();

    final daysLeft = sub.daysLeftUntilExpiry;
    if (daysLeft == null || daysLeft < 0) return const SizedBox.shrink();

    final expiresAt = sub.expiresAt;
    final auto = sub.willAutoRenew;

    if (auto) {
      // Subtle AutoPay notice — only within the last 7 days (or always if desired)
      if (daysLeft > 7 || expiresAt == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.canvas,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(
            children: [
              const Icon(Icons.autorenew, size: 18, color: AppColors.slate),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Your plan will automatically renew on ${SubscriptionStatus.formatExpiryDate(expiresAt)}.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.slate,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Manual renew — eye-catching when ≤ 7 days
    if (daysLeft > 7) return const SizedBox.shrink();

    final dayLabel = daysLeft == 0
        ? 'today'
        : daysLeft == 1
            ? 'in 1 day'
            : 'in $daysLeft days';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PaywallScreen(
                  reason: daysLeft == 0
                      ? 'Your Premium plan expires today. Renew to keep access.'
                      : 'Your Premium plan expires $dayLabel. Tap a plan to renew.',
                ),
              ),
            );
          },
          child: Ink(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFDBA74)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFB45309), size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    daysLeft == 0
                        ? 'Your Premium plan expires today. Tap to renew.'
                        : 'Your Premium plan expires $dayLabel. Tap to renew.',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF9A3412),
                      height: 1.35,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right, color: Color(0xFFB45309)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
