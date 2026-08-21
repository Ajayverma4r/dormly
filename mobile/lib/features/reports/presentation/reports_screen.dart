// features/reports/presentation/reports_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/reports_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../subscription/presentation/widgets/feature_gate.dart';
import '../../subscription/presentation/subscription_provider.dart';
import '../../subscription/presentation/paywall_screen.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  final String propertyId;
  const ReportsScreen({super.key, required this.propertyId});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  DateTime _start = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _end = DateTime(DateTime.now().year, DateTime.now().month + 1, 0);

  Future<void> _pickDate(DateTime initial, ValueChanged<DateTime> onPicked) async {
    final picked = await showDatePicker(
      context: context, initialDate: initial, firstDate: DateTime(2020), lastDate: DateTime(2100),
    );
    if (picked != null) onPicked(picked);
  }

  Future<void> _guardedExport(String featureKey, Future<void> Function() action) async {
    final allowed = ref.read(canProvider(featureKey));
    if (!allowed) {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PaywallScreen()),
      );
      return;
    }
    await action();
  }

  Future<void> _openRentCollection(String format) async {
    final featureKey = format == 'pdf' ? 'can_export_pdf' : 'can_export_csv';
    await _guardedExport(featureKey, () async {
      final url = await ref.read(reportsRepositoryProvider).rentCollectionUrl(widget.propertyId, _start, _end, format);
      await launchUrl(url, mode: LaunchMode.externalApplication);
    });
  }

  Future<void> _openOccupancy(String format) async {
    final featureKey = format == 'pdf' ? 'can_export_pdf' : 'can_export_csv';
    await _guardedExport(featureKey, () async {
      final url = await ref.read(reportsRepositoryProvider).occupancyUrl(widget.propertyId, format);
      await launchUrl(url, mode: LaunchMode.externalApplication);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: FeatureGate(
        featureKey: 'can_access_reports',
        featureLabel: 'Reports & Exports',
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Rent Collection Report', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('Choose a period, then download as PDF or CSV.', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('From: ${_start.toString().split(' ').first}'),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: () => _pickDate(_start, (d) => setState(() => _start = d)),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('To: ${_end.toString().split(' ').first}'),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: () => _pickDate(_end, (d) => setState(() => _end = d)),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openRentCollection('pdf'),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('PDF'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openRentCollection('csv'),
                    icon: const Icon(Icons.table_chart_outlined),
                    label: const Text('CSV'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 20),
            Text('Occupancy Report', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('Current occupancy status of every unit.', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openOccupancy('pdf'),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('PDF'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openOccupancy('csv'),
                    icon: const Icon(Icons.table_chart_outlined),
                    label: const Text('CSV'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
