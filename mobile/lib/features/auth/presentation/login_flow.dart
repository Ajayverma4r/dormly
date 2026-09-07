// features/auth/presentation/login_flow.dart
//
// Post-login routing (frictionless):
//   invitations → auto-pick primary context → profile (if needed) → first property shell
//
// Session restore (app restart):
//   refresh token → restore context → route to dashboard / wizard
//
// Role/property list screens are bypassed; switching lives in-app (Menu / Dashboard).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/auth_repository.dart';
import '../../staff/data/staff_repository.dart';
import '../../properties/data/properties_repository.dart';

/// Fresh login after OTP — always resolves context from the server.
Future<void> completeLogin(BuildContext context, WidgetRef ref) async {
  final authRepo = ref.read(authRepositoryProvider);
  final staffRepo = ref.read(staffRepositoryProvider);

  final invitations = await staffRepo.listMyInvitations();
  if (invitations.isNotEmpty) {
    if (context.mounted) context.go('/invitations', extra: invitations);
    return;
  }

  final contexts = await authRepo.listContexts();
  if (contexts.isEmpty) {
    throw Exception('No accessible workspace found for this account.');
  }

  // Frictionless: never show ContextPicker — auto-select primary workspace.
  final chosen = _pickPrimaryContext(contexts);
  await authRepo.selectContext(chosen['type'], chosen['id']);
  if (context.mounted) await routeAfterContextSelection(context, ref, chosen);
}

/// Cold start — reuse persisted refresh token + last workspace context.
Future<void> restoreSession(BuildContext context, WidgetRef ref) async {
  final authRepo = ref.read(authRepositoryProvider);

  final ok = await authRepo.ensureValidSession();
  if (!ok) {
    await authRepo.logout();
    throw Exception('Session expired');
  }

  if (await authRepo.hasStoredContext()) {
    final restored = await authRepo.restoreContextIfNeeded();
    if (!restored) {
      // Stored context invalid — fall back to full login resolution.
      if (context.mounted) await completeLogin(context, ref);
      return;
    }
  } else {
    if (context.mounted) await completeLogin(context, ref);
    return;
  }

  final staffRepo = ref.read(staffRepositoryProvider);
  final invitations = await staffRepo.listMyInvitations();
  if (invitations.isNotEmpty) {
    if (context.mounted) context.go('/invitations', extra: invitations);
    return;
  }

  if (context.mounted) await routeAuthenticatedUser(context, ref);
}

/// Route an already-authenticated user (restore or post-context-select).
Future<void> routeAuthenticatedUser(
  BuildContext context,
  WidgetRef ref,
) async {
  final authRepo = ref.read(authRepositoryProvider);
  final role = await authRepo.getContextRole();

  if (role == 'tenant') {
    if (context.mounted) context.go('/tenant/dashboard');
    return;
  }

  if (role == 'owner' || role == 'admin') {
    try {
      final me = await authRepo.fetchMe();
      if (!me.profileComplete) {
        if (context.mounted) context.go('/onboarding/profile');
        return;
      }
    } catch (_) {
      // If /me fails (old backend), fall through to property routing.
    }
  }

  if (context.mounted) await continueAfterProfileComplete(context, ref);
}

/// Called after profile is saved during onboarding when user already has properties.
Future<void> continueAfterProfileComplete(
  BuildContext context,
  WidgetRef ref,
) async {
  final authRepo = ref.read(authRepositoryProvider);
  final orgId = await authRepo.getOrganizationId();
  final scopedPropertyId = await authRepo.getScopedPropertyId();
  if (!context.mounted) return;

  if (orgId != null) {
    final properties =
        await ref.read(propertiesRepositoryProvider).list(orgId);
    if (!context.mounted) return;
    _goByPropertyCount(context, properties);
    return;
  }

  if (scopedPropertyId != null) {
    final property =
        await ref.read(propertiesRepositoryProvider).getById(scopedPropertyId);
    if (!context.mounted) return;
    context.go('/property/$scopedPropertyId',
        extra: {'propertyName': property['name']});
    return;
  }

  context.go('/onboarding/welcome');
}

Future<void> routeAfterContextSelection(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> selectedContext,
) async {
  final role = selectedContext['role'];

  if (role == 'tenant') {
    if (context.mounted) context.go('/tenant/dashboard');
    return;
  }

  final authRepo = ref.read(authRepositoryProvider);

  // Owners/admins must complete profile before property flows.
  if (role == 'owner' || role == 'admin') {
    try {
      final me = await authRepo.fetchMe();
      if (!me.profileComplete) {
        if (context.mounted) {
          context.go('/onboarding/profile');
        }
        return;
      }
    } catch (_) {
      // If /me fails (old backend), fall through to property routing.
    }
  }

  final orgId = await authRepo.getOrganizationId();
  final scopedPropertyId = await authRepo.getScopedPropertyId();

  if (!context.mounted) return;

  if (orgId != null) {
    final properties =
        await ref.read(propertiesRepositoryProvider).list(orgId);
    if (!context.mounted) return;
    _goByPropertyCount(context, properties);
  } else if (scopedPropertyId != null) {
    final property =
        await ref.read(propertiesRepositoryProvider).getById(scopedPropertyId);
    if (!context.mounted) return;
    context.go('/property/$scopedPropertyId',
        extra: {'propertyName': property['name']});
  } else {
    context.go('/onboarding/welcome');
  }
}

/// Switch workspace role in-app (owner ↔ tenant) without the context picker.
Future<void> switchWorkspaceRole(
  BuildContext context,
  WidgetRef ref, {
  required bool toTenant,
}) async {
  final authRepo = ref.read(authRepositoryProvider);
  final contexts = await authRepo.listContexts();
  final match = contexts.where((c) {
    final role = c['role']?.toString();
    if (toTenant) return role == 'tenant';
    return role == 'owner' || role == 'admin' || role == 'manager';
  }).toList();

  if (match.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            toTenant
                ? 'No tenant workspace on this account.'
                : 'No owner workspace on this account.',
          ),
        ),
      );
    }
    return;
  }

  final chosen = _pickPrimaryContext(match);
  await authRepo.selectContext(chosen['type'], chosen['id']);
  if (context.mounted) await routeAfterContextSelection(context, ref, chosen);
}

/// Prefer owner/admin org workspaces over staff/tenant for frictionless entry.
Map<String, dynamic> _pickPrimaryContext(List<dynamic> contexts) {
  int score(Map<String, dynamic> c) {
    switch (c['role']?.toString()) {
      case 'owner':
        return 0;
      case 'admin':
        return 1;
      case 'manager':
        return 2;
      case 'staff':
        return 3;
      case 'tenant':
        return 4;
      default:
        return 5;
    }
  }

  final list = contexts
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList()
    ..sort((a, b) => score(a).compareTo(score(b)));
  return list.first;
}

/// Always land on the first property shell — never the property list gate.
void _goByPropertyCount(BuildContext context, List<dynamic> properties) {
  if (properties.isEmpty) {
    context.go('/onboarding/welcome');
    return;
  }
  final p = properties.first as Map;
  context.go(
    '/property/${p['id']}',
    extra: {'propertyName': p['name']},
  );
}
