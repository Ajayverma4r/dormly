// features/auth/presentation/tenancy_unavailable_screen.dart
//
// Shown when the server lists no usable workspace and the user's only
// tenancies are pending or ended. No tenant data is loaded here.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../data/auth_repository.dart';
import '../domain/workspace_resolver.dart';
import 'login_flow.dart';

class TenancyUnavailableScreen extends ConsumerStatefulWidget {
  /// `pending` or `ended`.
  final String status;

  const TenancyUnavailableScreen({super.key, required this.status});

  @override
  ConsumerState<TenancyUnavailableScreen> createState() =>
      _TenancyUnavailableScreenState();
}

class _TenancyUnavailableScreenState
    extends ConsumerState<TenancyUnavailableScreen> {
  bool _busy = false;

  bool get _pending => widget.status == 'pending';

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Something went wrong. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkAgain() => _run(() => completeLogin(context, ref));

  Future<void> _setUpProperty() => _run(() async {
        final me = await ref.read(authRepositoryProvider).fetchMe();
        if (!mounted) return;
        await openLoginDestination(context, ref, const OwnerSetup(null), me);
      });

  Future<void> _logout() async {
    await ref.read(authRepositoryProvider).logout();
    if (mounted) context.go('/splash');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              CircleAvatar(
                radius: 36,
                backgroundColor: AppColors.primarySoft,
                child: Icon(
                  _pending ? Icons.hourglass_top_rounded : Icons.home_outlined,
                  size: 34,
                  color: AppColors.blueprint,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _pending ? 'Your stay is not active yet' : 'Your stay has ended',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _pending
                    ? 'Your property owner has added you, but your tenancy is '
                        'still pending. You will get access to your tenant '
                        'dashboard once they activate it.'
                    : 'This number has no active tenancy. Ask your property '
                        'owner if you have moved in again.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: Color(0xFF6B7280),
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _busy ? null : _checkAgain,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Check again'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : _setUpProperty,
                child: const Text('I own a property — set it up'),
              ),
              TextButton(
                onPressed: _busy ? null : _logout,
                child: const Text('Log out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
