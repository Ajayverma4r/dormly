// features/properties/presentation/welcome_screen.dart
//
// Entry for owners with ZERO properties. If properties already exist, this
// screen immediately routes to the property dashboard / picker — never the
// create-property wizard.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/login_flow.dart';
import '../data/properties_repository.dart';
import '../domain/property_setup_state.dart';

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  bool _checking = true;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _redirectIfHasProperties());
  }

  Future<List<dynamic>> _loadProperties() async {
    final authRepo = ref.read(authRepositoryProvider);
    final repo = ref.read(propertiesRepositoryProvider);
    final orgId = await authRepo.getOrganizationId();
    try {
      return await repo.list(orgId);
    } catch (_) {
      final scopedId = await authRepo.getScopedPropertyId();
      if (scopedId == null) return const [];
      final property = await repo.getById(scopedId);
      return [property];
    }
  }

  Future<void> _redirectIfHasProperties() async {
    try {
      final properties = await _loadProperties();
      if (!mounted) return;
      if (properties.isNotEmpty) {
        goByPropertyCount(context, properties);
        return;
      }
    } catch (e) {
      debugPrint('WelcomeScreen property check failed: $e');
    }
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _onGetStarted() async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      final properties = await _loadProperties();
      if (!mounted) return;
      if (properties.isNotEmpty) {
        // Existing property — open it (or picker). Never reopen create wizard.
        goByPropertyCount(context, properties);
        return;
      }
      // Fresh create only.
      ref.read(propertySetupProvider.notifier).reset();
      context.push('/onboarding/create-property');
    } catch (e) {
      debugPrint('WelcomeScreen Get Started failed: $e');
      if (!mounted) return;
      ref.read(propertySetupProvider.notifier).reset();
      context.push('/onboarding/create-property');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.black54),
            tooltip: 'Logout',
            onPressed: () async {
              await ref.read(authRepositoryProvider).logout();
              if (context.mounted) context.go('/splash');
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Icon(Icons.location_city,
                    size: 84, color: AppColors.blueprint),
              ),
              const SizedBox(height: 32),
              const Text(
                'Welcome to Dormly 👋',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Text(
                "Let's set up your property in just a few steps.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey.shade600,
                  height: 1.4,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.blueprint,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: _starting ? null : _onGetStarted,
                  child: _starting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Get Started',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  // Skip-for-now: goes to property list / empty home without
                  // forcing property creation.
                  onPressed: () => context.go('/home'),
                  child: const Text(
                    "I'll Do It Later",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
