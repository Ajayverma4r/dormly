// features/properties/presentation/properties_list_screen.dart
//
// The real "home base" after login when the user has properties: shows every
// property they own, with a way to open any of them or add a new one.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/properties_repository.dart';
import '../domain/property_monetization.dart';
import '../../auth/data/auth_repository.dart';
import '../../../core/widgets/property_illustration.dart';
import '../../subscription/presentation/subscription_provider.dart';
import '../../subscription/presentation/paywall_screen.dart';
import '../../subscription/presentation/widgets/quota_warning_banner.dart';
import '../../subscription/presentation/widgets/expiry_warning_banner.dart';

final myPropertiesProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  final authRepo = ref.read(authRepositoryProvider);
  final repo = ref.read(propertiesRepositoryProvider);
  final orgId = await authRepo.getOrganizationId();
  try {
    // Backend resolves org from JWT context; orgId query is optional.
    return await repo.list(orgId);
  } catch (_) {
    final scopedPropertyId = await authRepo.getScopedPropertyId();
    if (scopedPropertyId != null) {
      final property = await repo.getById(scopedPropertyId);
      return [property];
    }
    rethrow;
  }
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
          final commercialCount = properties
              .where((p) =>
                  PropertyMonetization.isCommercial(p['property_type_key'] as String?))
              .length;
          final sub = ref.watch(subscriptionProvider).valueOrNull;
          final isPaid = PropertyMonetization.isPaidPlan(
            sub?.subscription.planSlug,
            sub?.subscription.status,
          );
          // Banner when free tier already has a commercial property, or surplus
          // commercials are frozen after expiry.
          final lockedCount = properties.where((raw) {
            final p = Map<String, dynamic>.from(raw as Map);
            return PropertyMonetization.isPropertyLocked(
              property: p,
              allProperties: properties
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList(),
              isPaid: isPaid,
            );
          }).length;
          final showCommercialHint =
              !isPaid && (commercialCount >= 1 || lockedCount > 0);

          return Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: ExpiryWarningBanner(),
              ),
              if (showCommercialHint)
                Material(
                  color: const Color(0xFFFFF7ED),
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.info_outline, color: Color(0xFFB45309)),
                    title: Text(
                      lockedCount > 0
                          ? 'Some commercial properties are locked after plan expiry. Your data is safe — upgrade to manage them again.'
                          : 'Free plan includes 1 commercial property. Residential types stay free forever.',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PaywallScreen(
                            reason: lockedCount > 0
                                ? PropertyMonetization.expiredLockMessage
                                : null,
                          ),
                        ),
                      ),
                      child: const Text('Upgrade'),
                    ),
                  ),
                )
              else
                QuotaWarningBanner(
                  quotaKey: 'max_properties',
                  currentCount: commercialCount,
                  resourceName: 'commercial properties',
                ),
              Expanded(
                child: properties.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const PropertyIllustration(),
                              const SizedBox(height: 20),
                              const Text('No Properties Yet',
                                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
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
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(20),
                        itemCount: properties.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final p = Map<String, dynamic>.from(properties[index] as Map);
                          final allMaps = properties
                              .map((e) => Map<String, dynamic>.from(e as Map))
                              .toList();
                          final locked = PropertyMonetization.isPropertyLocked(
                            property: p,
                            allProperties: allMaps,
                            isPaid: isPaid,
                          );
                          return Container(
                            decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: locked
                                    ? Border.all(color: const Color(0xFFFDBA74))
                                    : null),
                            child: ListTile(
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              leading: CircleAvatar(
                                backgroundColor: locked
                                    ? const Color(0xFFFFF7ED)
                                    : const Color(0xFFEFF2FF),
                                child: Icon(
                                  locked ? Icons.lock_outline : Icons.apartment,
                                  color: locked
                                      ? const Color(0xFFB45309)
                                      : const Color(0xFF2B5CFF),
                                ),
                              ),
                              title: Text(p['name'] ?? '',
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text(
                                  locked
                                      ? 'Locked — upgrade to manage'
                                      : (p['city'] ?? p['property_type_key'] ?? ''),
                                  style: TextStyle(
                                      color: locked
                                          ? const Color(0xFFB45309)
                                          : Colors.grey.shade600)),
                              trailing: Icon(
                                locked ? Icons.lock : Icons.chevron_right,
                                color: locked ? const Color(0xFFB45309) : null,
                              ),
                              onTap: () {
                                if (locked) {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const PaywallScreen(
                                        reason: PropertyMonetization
                                            .expiredLockMessage,
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                context.go('/property/${p['id']}',
                                    extra: {'propertyName': p['name']});
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF2B5CFF),
        onPressed: () {
          // Residential types are unlimited; commercial types are gated in the
          // wizard (and on the backend). Always open the create flow.
          context.push('/onboarding/create-property');
        },
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Property', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}