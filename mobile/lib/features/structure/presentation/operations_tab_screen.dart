// features/structure/presentation/operations_tab_screen.dart
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../billing/presentation/invoices_list_screen.dart';
import '../../complaints/presentation/complaints_list_screen.dart';
import '../../reports/presentation/reports_screen.dart';
import '../../analytics/presentation/analytics_dashboard_screen.dart';

class OperationsTabScreen extends StatelessWidget {
  final String propertyId;
  final bool canManage;

  const OperationsTabScreen({super.key, required this.propertyId, required this.canManage});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Operations')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (canManage) ...[
            _tile(context, 'Rent & Billing', 'Invoices, payments, reminders', Icons.receipt_long_outlined, AppColors.caution,
                () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => InvoicesListScreen(propertyId: propertyId)))),
            const SizedBox(height: 12),
          ],
          _tile(context, 'Complaints', 'Maintenance & resident issues', Icons.build_outlined, AppColors.danger,
              () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => ComplaintsListScreen(propertyId: propertyId)))),
          if (canManage) ...[
            const SizedBox(height: 12),
            _tile(context, 'Analytics', 'Revenue, occupancy, trends', Icons.bar_chart_outlined, AppColors.positive,
                () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => AnalyticsDashboardScreen(propertyId: propertyId)))),
            const SizedBox(height: 12),
            _tile(context, 'Reports', 'Downloadable PDF/CSV reports', Icons.description_outlined, const Color(0xFF0891B2),
                () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => ReportsScreen(propertyId: propertyId)))),
          ],
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, String title, String subtitle, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(subtitle, style: const TextStyle(color: AppColors.slate, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}