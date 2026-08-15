// features/subscription/presentation/widgets/quota_warning_banner.dart
//
// Displays a contextual warning when the org is approaching or has exceeded
// a plan quota (max_properties, max_rooms, max_staff_members).
//
// ▶  0%–79% of limit  → hidden
// ▶ 80%–99% of limit  → amber warning (approaching limit)
// ▶ 100%+ of limit    → red error  (read-only mode — creation blocked)
//
// USAGE:
//
//   QuotaWarningBanner(
//     quotaKey: 'max_properties',
//     currentCount: properties.length,
//     resourceName: 'properties',
//   )

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../subscription_provider.dart';
import '../paywall_screen.dart';

class QuotaWarningBanner extends ConsumerWidget {
  /// Feature key to check (e.g. 'max_properties').
  final String quotaKey;

  /// Current count of the resource (e.g. number of properties created).
  final int currentCount;

  /// Human-readable name for the resource (e.g. 'properties', 'rooms').
  final String resourceName;

  const QuotaWarningBanner({
    super.key,
    required this.quotaKey,
    required this.currentCount,
    required this.resourceName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entitlements = ref.watch(entitlementsProvider);
    final limit = entitlements.quota(quotaKey);

    // Hidden for unlimited plans or when quota is not defined
    if (limit <= 0) return const SizedBox.shrink();

    final ratio = currentCount / limit;

    // Under 80% — nothing to show
    if (ratio < 0.8) return const SizedBox.shrink();

    final isOver = currentCount >= limit;

    final bgColor = isOver
        ? AppColors.danger.withOpacity(0.08)
        : AppColors.caution.withOpacity(0.08);
    final borderColor =
        isOver ? AppColors.danger.withOpacity(0.3) : AppColors.caution.withOpacity(0.3);
    final iconColor = isOver ? AppColors.danger : AppColors.caution;
    final textColor = isOver ? AppColors.danger : AppColors.caution;

    final message = isOver
        ? 'You\'ve reached your $resourceName limit ($currentCount/$limit). Upgrade to create more.'
        : 'You\'re using $currentCount of $limit $resourceName. Consider upgrading soon.';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(
            isOver ? Icons.block_outlined : Icons.warning_amber_outlined,
            size: 18,
            color: iconColor,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                color: textColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PaywallScreen()),
            ),
            child: Text(
              'Upgrade',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.blueprint,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline,
                decorationColor: AppColors.blueprint,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
