// features/home/presentation/profile_screen.dart
//
// Settings / profile for signed-in owners — edit name/email and see plan.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/user_profile.dart';
import '../../auth/presentation/profile_creation_screen.dart';
import '../../subscription/presentation/paywall_screen.dart';
import '../../subscription/presentation/subscription_provider.dart';
import '../../../core/theme/app_theme.dart';

final myProfileProvider = FutureProvider.autoDispose<UserProfile>((ref) {
  return ref.watch(authRepositoryProvider).fetchMe();
});

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  String _resolveAvatarUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    const base = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://dormly-backend.onrender.com',
    );
    return '$base$path';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(myProfileProvider);
    final sub = ref.watch(subscriptionProvider).valueOrNull;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile & Settings')),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not load profile: $err'),
          ),
        ),
        data: (profile) {
          final planLabel = sub?.subscription.planName ??
              profile.planName ??
              profile.displayPlan;
          final statusLabel =
              sub?.subscription.statusLabel ?? profile.subscriptionStatus ?? '';
          final avatarUrl = _resolveAvatarUrl(profile.avatarUrl);

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: AppColors.canvas,
                      backgroundImage:
                          avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                      child: avatarUrl.isEmpty
                          ? Text(
                              (profile.name ?? '?')
                                  .substring(0, 1)
                                  .toUpperCase(),
                              style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.blueprint),
                            )
                          : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile.name ?? 'No name set',
                            style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(profile.phone,
                              style: const TextStyle(
                                  color: AppColors.slate, fontSize: 13)),
                          if (profile.email != null &&
                              profile.email!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(profile.email!,
                                style: const TextStyle(
                                    color: AppColors.slate, fontSize: 13)),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.workspace_premium_outlined,
                        color: AppColors.blueprint),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(planLabel,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 15)),
                          if (statusLabel.isNotEmpty)
                            Text(statusLabel,
                                style: const TextStyle(
                                    color: AppColors.slate, fontSize: 12)),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const PaywallScreen()),
                      ),
                      child: const Text('Manage'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                tileColor: AppColors.surface,
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit profile'),
                subtitle: const Text('Name, email, photo'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final updated = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) =>
                          const ProfileCreationScreen(fromOnboarding: false),
                    ),
                  );
                  if (updated == true) {
                    ref.invalidate(myProfileProvider);
                  }
                },
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await ref.read(authRepositoryProvider).logout();
                    if (context.mounted) context.go('/login');
                  },
                  icon: const Icon(Icons.logout, color: AppColors.danger),
                  label: const Text('Logout',
                      style: TextStyle(color: AppColors.danger)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
