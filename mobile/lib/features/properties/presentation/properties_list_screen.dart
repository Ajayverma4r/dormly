// features/properties/presentation/properties_list_screen.dart
//
// The real "home base" after login when the user has properties: shows every
// property they own, with a way to open any of them or add a new one.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/properties_repository.dart';
import '../../auth/data/auth_repository.dart';
import '../../../core/widgets/property_illustration.dart';

final myPropertiesProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  final authRepo = ref.watch(authRepositoryProvider);
  final orgId = await authRepo.getOrganizationId();
  if (orgId != null) {
    return ref.watch(propertiesRepositoryProvider).list(orgId);
  }
  final scopedPropertyId = await authRepo.getScopedPropertyId();
  if (scopedPropertyId != null) {
    final property = await ref.watch(propertiesRepositoryProvider).getById(scopedPropertyId);
    return [property];
  }
  return [];
});

class PropertiesListScreen extends ConsumerWidget {
  const PropertiesListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final propertiesAsync = ref.watch(myPropertiesProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
     appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Your Properties', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.black54),
            tooltip: 'Logout',
            onPressed: () async {
              await ref.read(authRepositoryProvider).logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: propertiesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Something went wrong: $err')),
        data: (properties) {
          if (properties.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const PropertyIllustration(),
                    const SizedBox(height: 20),
                    const Text('No Properties Yet', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text(
                      'Create your first property to start managing\nhostels, apartments, offices, or any other property.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2B5CFF)),
                      onPressed: () => context.push('/onboarding/create-property'),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        child: Text('Create Property', style: TextStyle(color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: properties.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final p = properties[index];
              return Container(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFEFF2FF),
                    child: Icon(Icons.apartment, color: Color(0xFF2B5CFF)),
                  ),
                  title: Text(p['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(p['city'] ?? p['property_type_key'] ?? '', style: TextStyle(color: Colors.grey.shade600)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/dashboard/${p['id']}', extra: {'propertyName': p['name']}),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF2B5CFF),
        onPressed: () => context.push('/onboarding/create-property'),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Property', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}