// features/tenancies/presentation/residents_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/tenancy_repository.dart';
import '../../../core/theme/app_theme.dart';
import 'resident_detail_screen.dart';

final propertyResidentsProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, propertyId) => ref.watch(tenancyRepositoryProvider).listByProperty(propertyId),
);

class ResidentsListScreen extends ConsumerWidget {
  final String propertyId;
  final String label; // dynamic: "Residents" / "Tenants" / "Employees" / etc.

  const ResidentsListScreen({super.key, required this.propertyId, required this.label});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final residentsAsync = ref.watch(propertyResidentsProvider(propertyId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(label)),
      body: residentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Something went wrong: $err')),
        data: (residents) {
          final active = residents.where((r) => r['status'] == 'active').toList();
          if (active.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.people_outline, size: 48, color: AppColors.slate),
                    const SizedBox(height: 12),
                    Text('No $label yet', style: theme.textTheme.bodyLarge),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: active.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final r = active[i];
              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: theme.dividerColor),
                ),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.canvas,
                    child: Icon(Icons.person, color: AppColors.blueprint),
                  ),
                  title: Text(r['full_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${r['node_name'] ?? ''} · ${r['phone'] ?? ''}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (context) => ResidentDetailScreen(propertyId: propertyId, tenancy: r),
                    ));
                    ref.invalidate(propertyResidentsProvider(propertyId));
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}