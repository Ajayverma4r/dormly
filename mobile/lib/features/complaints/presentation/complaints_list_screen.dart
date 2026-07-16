// features/complaints/presentation/complaints_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/complaints_repository.dart';
import '../../../core/theme/app_theme.dart';
import 'package:go_router/go_router.dart';
import '../../auth/data/auth_repository.dart';

final complaintsProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, propertyId) => ref.watch(complaintsRepositoryProvider).listForProperty(propertyId),
);

class ComplaintsListScreen extends ConsumerWidget {
  final String propertyId;
  final bool isRoot;
  const ComplaintsListScreen({super.key, required this.propertyId, this.isRoot = false});

  Color _statusColor(String status) {
    switch (status) {
      case 'resolved': return AppColors.positive;
      case 'closed': return AppColors.slate;
      case 'in_progress': return AppColors.caution;
      default: return AppColors.danger; // open
    }
  }

  Future<void> _openStatusSheet(BuildContext context, WidgetRef ref, Map<String, dynamic> complaint) async {
    String? newStatus;
    final noteController = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: StatefulBuilder(
          builder: (context, setSheetState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(complaint['category'], style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(complaint['description'], style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: ['open', 'in_progress', 'resolved', 'closed'].map((s) {
                  return ChoiceChip(
                    label: Text(s.replaceAll('_', ' ')),
                    selected: (newStatus ?? complaint['status']) == s,
                    onSelected: (_) => setSheetState(() => newStatus = s),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(labelText: 'Resolution note (optional)', border: OutlineInputBorder()),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity, height: 48,
                child: ElevatedButton(
                  onPressed: () async {
                    await ref.read(complaintsRepositoryProvider).updateStatus(
                          propertyId, complaint['id'], newStatus ?? complaint['status'],
                          resolutionNote: noteController.text.trim().isEmpty ? null : noteController.text.trim(),
                        );
                    ref.invalidate(complaintsProvider(propertyId));
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final complaintsAsync = ref.watch(complaintsProvider(propertyId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Complaints'),
        actions: isRoot
            ? [
                IconButton(
                  icon: const Icon(Icons.logout),
                  tooltip: 'Logout',
                  onPressed: () async {
                    await ref.read(authRepositoryProvider).logout();
                    if (context.mounted) context.go('/login');
                  },
                ),
              ]
            : null,
      ),
      body: complaintsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Something went wrong: $err')),
        data: (complaints) {
          if (complaints.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.build_outlined, size: 48, color: AppColors.slate),
                    const SizedBox(height: 12),
                    Text('No complaints yet', style: theme.textTheme.bodyLarge),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: complaints.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final c = complaints[i];
              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: theme.dividerColor),
                ),
                child: ListTile(
                  title: Text(c['category'], style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${c['node_name']} · ${c['description']}', maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _statusColor(c['status']).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      c['status'].toString().replaceAll('_', ' ').toUpperCase(),
                      style: TextStyle(color: _statusColor(c['status']), fontSize: 10, fontWeight: FontWeight.w700),
                    ),
                  ),
                  onTap: () => _openStatusSheet(context, ref, c),
                ),
              );
            },
          );
        },
      ),
    );
  }
}