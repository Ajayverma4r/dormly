// features/analytics/presentation/analytics_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/analytics_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/blueprint_grid_painter.dart';

final analyticsProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, propertyId) => ref.watch(analyticsRepositoryProvider).getAnalytics(propertyId),
);

class AnalyticsDashboardScreen extends ConsumerWidget {
  final String propertyId;
  const AnalyticsDashboardScreen({super.key, required this.propertyId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsAsync = ref.watch(analyticsProvider(propertyId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Analytics')),
      body: analyticsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Something went wrong: $err')),
        data: (a) {
          final revenue = double.tryParse(a['totalRevenue'].toString()) ?? 0;
          final pending = double.tryParse(a['pendingRent'].toString()) ?? 0;
          final occupancyRate = a['occupancyRate'] as int;
          final occupied = a['occupiedUnits'] as int;
          final vacant = a['vacantUnits'] as int;
          final overdue = a['overdueCount'] as int;
          final payments = List<Map<String, dynamic>>.from(a['recentPayments']);

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  decoration: const BoxDecoration(color: AppColors.surface),
                  child: Stack(
                    children: [
                      Positioned.fill(child: CustomPaint(painter: BlueprintGridPainter())),
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('TOTAL REVENUE', style: theme.textTheme.labelSmall),
                            const SizedBox(height: 6),
                            Text('₹${_formatNumber(revenue)}', style: theme.textTheme.displaySmall),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Icon(Icons.hourglass_bottom, size: 16, color: AppColors.caution),
                                const SizedBox(width: 6),
                                Text('₹${_formatNumber(pending)} pending', style: theme.textTheme.bodyMedium),
                                if (overdue > 0) ...[
                                  const SizedBox(width: 16),
                                  Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.danger),
                                  const SizedBox(width: 6),
                                  Text('$overdue overdue', style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.danger)),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20)),
                child: Row(
                  children: [
                    SizedBox(
                      width: 76, height: 76,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 76, height: 76,
                            child: CircularProgressIndicator(
                              value: occupancyRate / 100,
                              strokeWidth: 8,
                              backgroundColor: AppColors.hairline,
                              valueColor: const AlwaysStoppedAnimation(AppColors.blueprint),
                            ),
                          ),
                          Text('$occupancyRate%', style: theme.textTheme.titleMedium),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Occupancy', style: theme.textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _dot(AppColors.blueprint),
                              const SizedBox(width: 6),
                              Text('$occupied occupied', style: theme.textTheme.bodyMedium),
                              const SizedBox(width: 16),
                              _dot(AppColors.hairline),
                              const SizedBox(width: 6),
                              Text('$vacant vacant', style: theme.textTheme.bodyMedium),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              Text('RECENT PAYMENTS', style: theme.textTheme.labelSmall),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20)),
                child: payments.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text('No payments recorded yet.', style: theme.textTheme.bodyMedium),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: payments.length,
                        separatorBuilder: (_, __) => const Divider(indent: 20, endIndent: 20),
                        itemBuilder: (context, i) {
                          final p = payments[i];
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            child: Row(
                              children: [
                                Container(
                                  width: 36, height: 36,
                                  decoration: BoxDecoration(
                                    color: AppColors.positive.withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.check, size: 18, color: AppColors.positive),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('${p['full_name']} · ${p['node_name']}', style: theme.textTheme.bodyLarge),
                                      Text(p['paid_at'].toString().split('T').first, style: theme.textTheme.bodyMedium),
                                    ],
                                  ),
                                ),
                                Text('₹${_formatNumber(double.tryParse(p['amount'].toString()) ?? 0)}',
                                    style: theme.textTheme.titleMedium),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _dot(Color color) => Container(
        width: 8, height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );

  String _formatNumber(double value) {
    final s = value.toStringAsFixed(0);
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write(',');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }
}