// features/tenancies/presentation/resident_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/tenancy_repository.dart';
import '../../../core/theme/app_theme.dart';

class ResidentDetailScreen extends ConsumerWidget {
  final String propertyId;
  final Map<String, dynamic> tenancy;

  const ResidentDetailScreen({super.key, required this.propertyId, required this.tenancy});

  Future<void> _endTenancy(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End this tenancy?'),
        content: const Text('This marks them as moved out. Their records stay for history.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('End Tenancy')),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await ref.read(tenancyRepositoryProvider).endTenancy(propertyId, tenancy['id']);
        if (context.mounted) Navigator.of(context).pop();
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not end tenancy: $e')));
        }
      }
    }
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(label, style: const TextStyle(color: AppColors.slate))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(tenancy['full_name'] ?? '')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.hairline),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _row('Unit', tenancy['node_name'] ?? ''),
                _row('Phone', tenancy['phone'] ?? ''),
                if (tenancy['email'] != null) _row('Email', tenancy['email']),
                if (tenancy['address'] != null) _row('Address', tenancy['address']),
                if (tenancy['company_name'] != null) _row('Company', tenancy['company_name']),
                if (tenancy['aadhaar_number'] != null) _row('Aadhaar', tenancy['aadhaar_number']),
                if (tenancy['move_in_at'] != null)
                  _row('Move-in', tenancy['move_in_at'].toString().split('T').first),
                if (tenancy['security_deposit'] != null)
                  _row('Security Deposit', '₹${tenancy['security_deposit']}'),
              ],
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.danger),
              minimumSize: const Size.fromHeight(50),
            ),
            onPressed: () => _endTenancy(context, ref),
            child: const Text('End Tenancy', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }
}