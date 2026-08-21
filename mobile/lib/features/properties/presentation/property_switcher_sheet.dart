// features/properties/presentation/property_switcher_sheet.dart
//
// Global property context picker — modal bottom sheet (not a full-screen route).

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/data/auth_repository.dart';
import '../data/properties_repository.dart';

/// Fetches properties using the authenticated ApiClient + JWT org context.
final switcherPropertiesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final authRepo = ref.read(authRepositoryProvider);
  final repo = ref.read(propertiesRepositoryProvider);
  final orgId = await authRepo.getOrganizationId();

  try {
    final list = await repo.list(orgId);
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  } on DioException catch (e) {
    // Scoped property fallback (manager/staff) if org list is forbidden.
    if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
      final scopedId = await authRepo.getScopedPropertyId();
      if (scopedId != null) {
        final p = await repo.getById(scopedId);
        return [p];
      }
    }
    rethrow;
  }
});

Future<void> showPropertySwitcherSheet(
  BuildContext context,
  WidgetRef ref, {
  required String currentPropertyId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return Consumer(
        builder: (context, ref, _) {
          final async = ref.watch(switcherPropertiesProvider);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
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
                    'Switch property',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Choose which property you are managing',
                    style: TextStyle(fontSize: 13, color: AppColors.slate),
                  ),
                  const SizedBox(height: 12),
                  async.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (err, _) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Column(
                        children: [
                          Text(
                            _friendlyError(err),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: AppColors.danger, fontSize: 13),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () =>
                                ref.invalidate(switcherPropertiesProvider),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                    data: (properties) {
                      if (properties.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text('No properties yet.',
                              textAlign: TextAlign.center),
                        );
                      }
                      return ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.45,
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: properties.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final p = properties[i];
                            final id = p['id']?.toString() ?? '';
                            final name = p['name']?.toString() ?? 'Property';
                            final subtitle = p['city']?.toString() ??
                                p['property_type_key']?.toString() ??
                                '';
                            final selected = id == currentPropertyId;
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundColor: selected
                                    ? AppColors.blueprint.withOpacity(0.12)
                                    : AppColors.canvas,
                                child: Icon(
                                  Icons.apartment,
                                  color: selected
                                      ? AppColors.blueprint
                                      : AppColors.slate,
                                ),
                              ),
                              title: Text(
                                name,
                                style: TextStyle(
                                  fontWeight: selected
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                ),
                              ),
                              subtitle: subtitle.isEmpty
                                  ? null
                                  : Text(subtitle,
                                      style: const TextStyle(fontSize: 12)),
                              trailing: selected
                                  ? const Icon(Icons.check_circle,
                                      color: AppColors.blueprint)
                                  : null,
                              onTap: () {
                                Navigator.of(context).pop();
                                if (id.isEmpty || selected) return;
                                context.go('/property/$id',
                                    extra: {'propertyName': name});
                              },
                            );
                          },
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        context.push('/onboarding/create-property');
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Add New Property'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.blueprint,
                        side: const BorderSide(color: AppColors.blueprint),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

String _friendlyError(Object err) {
  if (err is DioException) {
    final data = err.response?.data;
    if (data is Map && data['error'] != null) {
      return data['error'].toString();
    }
    if (err.response?.statusCode == 401) {
      return 'Session expired. Please log out and sign in again.';
    }
  }
  return 'Could not load properties. Pull to retry.';
}
