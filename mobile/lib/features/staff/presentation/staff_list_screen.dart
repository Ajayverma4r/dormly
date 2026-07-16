// features/staff/presentation/staff_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/staff_repository.dart';
import '../../../core/theme/app_theme.dart';

final staffListProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, propertyId) => ref.watch(staffRepositoryProvider).listForProperty(propertyId),
);

class StaffListScreen extends ConsumerWidget {
  final String propertyId;
  const StaffListScreen({super.key, required this.propertyId});

  Future<void> _inviteStaff(BuildContext context, WidgetRef ref) async {
    final phoneController = TextEditingController();
    String role = 'staff';
    String? error;

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
              Text('Invite Team Member', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                decoration: const InputDecoration(
                  labelText: 'Mobile Number',
                  hintText: '9876543210',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              const Text('Role', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: ['manager', 'staff'].map((r) => ChoiceChip(
                      label: Text(r),
                      selected: role == r,
                      onSelected: (_) => setSheetState(() => role = r),
                    )).toList(),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(color: AppColors.danger)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity, height: 48,
                child: ElevatedButton(
                  onPressed: () async {
                    if (phoneController.text.trim().isEmpty) {
                      setSheetState(() => error = 'Enter a phone number.');
                      return;
                    }
                    try {
                     await ref.read(staffRepositoryProvider).assign(propertyId, '+91${phoneController.text.trim()}', role);
                      ref.invalidate(staffListProvider(propertyId));
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      setSheetState(() => error = 'Could not invite: $e');
                    }
                  },
                  child: const Text('Send Invite'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref, Map<String, dynamic> member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${member['name'] ?? member['phone']}?'),
        content: const Text('They will lose access to this property immediately.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(staffRepositoryProvider).remove(propertyId, member['id']);
      ref.invalidate(staffListProvider(propertyId));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staffAsync = ref.watch(staffListProvider(propertyId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Team')),
      body: staffAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Something went wrong: $err')),
        data: (staff) {
          if (staff.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.badge_outlined, size: 48, color: AppColors.slate),
                    const SizedBox(height: 12),
                    Text('No team members yet', style: theme.textTheme.bodyLarge),
                    const SizedBox(height: 4),
                    Text('Invite a Manager or Staff member to help run this property.',
                        textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: staff.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final m = staff[i];
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
                  title: Text(m['name'] ?? m['phone'], style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(m['phone']),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.blueprint.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(m['role'].toString().toUpperCase(),
                            style: const TextStyle(color: AppColors.blueprint, fontSize: 10, fontWeight: FontWeight.w700)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => _confirmRemove(context, ref, m),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _inviteStaff(context, ref),
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Invite'),
      ),
    );
  }
}