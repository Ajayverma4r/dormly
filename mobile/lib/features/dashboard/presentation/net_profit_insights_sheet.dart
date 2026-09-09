// features/dashboard/presentation/net_profit_insights_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import 'property_dashboard_provider.dart';

const _accent = AppColors.primary;

final _currency =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

Future<void> showNetProfitInsightsSheet({
  required BuildContext context,
  required String propertyId,
  required double collected,
  required double expenses,
  required double netProfit,
  required double pendingDues,
  VoidCallback? onViewPendingDues,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => NetProfitInsightsSheet(
      propertyId: propertyId,
      collected: collected,
      expenses: expenses,
      netProfit: netProfit,
      pendingDues: pendingDues,
      onViewPendingDues: onViewPendingDues,
    ),
  );
}

class NetProfitInsightsSheet extends ConsumerWidget {
  final String propertyId;
  final double collected;
  final double expenses;
  final double netProfit;
  final double pendingDues;
  final VoidCallback? onViewPendingDues;

  const NetProfitInsightsSheet({
    super.key,
    required this.propertyId,
    required this.collected,
    required this.expenses,
    required this.netProfit,
    required this.pendingDues,
    this.onViewPendingDues,
  });

  void _onPrimary(BuildContext context) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    Navigator.pop(context);
    if (onViewPendingDues != null) {
      onViewPendingDues!();
      return;
    }
    messenger?.showSnackBar(
      const SnackBar(content: Text('Open Payments to follow up on dues')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(propertyDashboardProvider(propertyId)).maybeWhen(
          data: (d) => d.overview,
          orElse: () => null,
        );
    final collectedAmt = overview?.rentReceived ?? collected;
    final expensesAmt = overview?.totalExpenses ?? expenses;
    final netProfitAmt = overview?.netProfit ?? netProfit;
    final pendingAmt = overview?.rentPending ?? pendingDues;
    final potentialAmt = netProfitAmt + pendingAmt;
    final hasPending = pendingAmt > 0.009;
    final pendingText = _currency.format(pendingAmt);
    final potentialText = _currency.format(potentialAmt);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.hairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Profitability Insights',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 16),
              _MathRow(
                collected: collectedAmt,
                expenses: expensesAmt,
                netProfit: netProfitAmt,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Divider(height: 1),
              ),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text.rich(
                  hasPending
                      ? TextSpan(
                          style: const TextStyle(
                            color: AppColors.ink,
                            height: 1.45,
                            fontSize: 14,
                          ),
                          children: [
                            const TextSpan(text: 'You have '),
                            TextSpan(
                              text: pendingText,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: _accent,
                              ),
                            ),
                            const TextSpan(
                              text:
                                  ' in pending dues. Collect them to reach a potential net profit of ',
                            ),
                            TextSpan(
                              text: potentialText,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: _accent,
                              ),
                            ),
                            const TextSpan(text: ' this month!'),
                          ],
                        )
                      : TextSpan(
                          style: const TextStyle(
                            color: AppColors.ink,
                            height: 1.45,
                            fontSize: 14,
                          ),
                          children: [
                            const TextSpan(
                              text:
                                  'No pending dues right now. Your net profit this month is ',
                            ),
                            TextSpan(
                              text: _currency.format(netProfitAmt),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: _accent,
                              ),
                            ),
                            const TextSpan(text: '.'),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: () => _onPrimary(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        hasPending ? 'View Pending Dues' : 'Go to Payments',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MathRow extends StatelessWidget {
  final double collected;
  final double expenses;
  final double netProfit;

  const _MathRow({
    required this.collected,
    required this.expenses,
    required this.netProfit,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 10,
          child: _MathChip(
            label: 'Collected',
            amount: collected,
            color: AppColors.positive,
            bg: const Color(0xFFDCFCE7),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '−',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.slate,
            ),
          ),
        ),
        Expanded(
          flex: 10,
          child: _MathChip(
            label: 'Expenses',
            amount: expenses,
            color: AppColors.danger,
            bg: const Color(0xFFFEE2E2),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '=',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.slate,
            ),
          ),
        ),
        Expanded(
          flex: 12,
          child: _MathChip(
            label: 'Net Profit',
            amount: netProfit,
            color: netProfit >= 0 ? AppColors.primaryDark : AppColors.danger,
            bg: const Color(0xFFDDD6FE),
            prominent: true,
          ),
        ),
      ],
    );
  }
}

class _MathChip extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  final Color bg;
  final bool prominent;

  const _MathChip({
    required this.label,
    required this.amount,
    required this.color,
    required this.bg,
    this.prominent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: prominent
            ? Border.all(color: _accent.withValues(alpha: 0.45))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              fontWeight: prominent ? FontWeight.w800 : FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _currency.format(amount),
                maxLines: 1,
                style: TextStyle(
                  fontSize: prominent ? 15 : 13,
                  fontWeight: prominent ? FontWeight.w900 : FontWeight.w800,
                  color: color,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
