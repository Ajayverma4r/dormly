// features/auth/presentation/role_gate.dart
//
// Screen-level guard for deep links into management screens. The backend
// enforces every permission; this only avoids rendering screens whose API
// calls would be refused for the selected workspace's role.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../structure/presentation/dynamic_dashboard/dynamic_dashboard_screen.dart'
    show contextRoleProvider;

/// Roles the backend treats as the property team.
const propertyTeamRoles = {'owner', 'admin', 'manager', 'staff'};

/// Roles the backend lets change rooms, tenancies and billing.
const propertyManagerRoles = {'owner', 'admin', 'manager'};

class RoleGate extends ConsumerWidget {
  final Set<String> allowed;
  final Widget child;

  const RoleGate({super.key, required this.allowed, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(contextRoleProvider).when(
          loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (_, __) => const RestrictedAccessScreen(role: null),
          data: (role) =>
              allowed.contains(role) ? child : RestrictedAccessScreen(role: role),
        );
  }
}

class RestrictedAccessScreen extends StatelessWidget {
  final String? role;

  const RestrictedAccessScreen({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    final isTenant = role == 'tenant';
    return Scaffold(
      appBar: AppBar(title: const Text('Not available')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 48),
              const SizedBox(height: 16),
              const Text(
                "Your role in this workspace doesn't include this page.",
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => context.go(isTenant ? '/tenant/dashboard' : '/properties'),
                child: Text(isTenant ? 'Go to my stay' : 'Back to properties'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
