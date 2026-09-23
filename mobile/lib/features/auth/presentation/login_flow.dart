// features/auth/presentation/login_flow.dart
//
// Unauthenticated: Splash → Your Stay, Simplified → Login → OTP
// Post-OTP (server is source of truth):
//   propertyCount > 0  → Dashboard / property picker
//   propertyCount == 0 → Welcome to Dormly (property creation)
// Authenticated cold start: Splash → restoreSession → Dashboard

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/auth_repository.dart';
import '../domain/user_profile.dart';
import '../../staff/data/staff_repository.dart';
import '../../properties/data/properties_repository.dart';

/// Fresh login after OTP — always resolves context from the server.
Future<void> completeLogin(
  BuildContext context,
  WidgetRef ref, {
  UserProfile? otpProfile,
}) async {
  final authRepo = ref.read(authRepositoryProvider);
  final staffRepo = ref.read(staffRepositoryProvider);

  debugPrint('[AUTH] OTP successful');
  debugPrint(
    '[AUTH] otp profile: propertyCount=${otpProfile?.propertyCount} '
    'orgId=${otpProfile?.organizationId} '
    'profileComplete=${otpProfile?.profileComplete}',
  );

  final invitations = await staffRepo.listMyInvitations();
  if (invitations.isNotEmpty) {
    debugPrint('[AUTH] routing decision: INVITATIONS');
    if (context.mounted) context.go('/invitations', extra: invitations);
    return;
  }

  List<Map<String, dynamic>>? contexts;
  try {
    contexts = await authRepo.listContexts();
    debugPrint('[AUTH] listContexts count=${contexts.length}');
  } catch (e) {
    debugPrint('[AUTH] listContexts failed: $e');
    try {
      await authRepo.ensureOwnerWorkspace();
    } catch (ensureErr) {
      debugPrint('[AUTH] ensureOwnerWorkspace failed: $ensureErr');
    }
    if (context.mounted) {
      await routeAuthenticatedUser(context, ref, otpProfile: otpProfile);
    }
    return;
  }

  if (contexts.isEmpty) {
    debugPrint('[AUTH] contexts empty — ensuring owner workspace');
    if (context.mounted) {
      try {
        await authRepo.ensureOwnerWorkspace();
      } catch (e) {
        debugPrint('[AUTH] ensureOwnerWorkspace failed: $e');
      }
      try {
        final me = otpProfile ?? await authRepo.fetchMe();
        if (!me.profileComplete) {
          debugPrint('[AUTH] destination: /onboarding/profile');
          if (context.mounted) context.go('/onboarding/profile');
          return;
        }
      } catch (_) {}
      if (context.mounted) {
        await continueAfterProfileComplete(context, ref, otpProfile: otpProfile);
      }
    }
    return;
  }

  final chosen = _pickPrimaryContext(contexts);
  debugPrint(
    '[AUTH] selected context type=${chosen['type']} '
    'id=${chosen['id']} role=${chosen['role']}',
  );
  await authRepo.selectContext(chosen['type'], chosen['id']);
  if (context.mounted) {
    await routeAfterContextSelection(
      context,
      ref,
      chosen,
      otpProfile: otpProfile,
    );
  }
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
  WidgetRef ref, {
  UserProfile? otpProfile,
}) async {
  final authRepo = ref.read(authRepositoryProvider);
  final role = await authRepo.getContextRole();

  if (role == 'tenant') {
    debugPrint('[AUTH] destination: /tenant/dashboard');
    if (context.mounted) context.go('/tenant/dashboard');
    return;
  }

  if (role == 'owner' || role == 'admin') {
    try {
      final me = otpProfile ?? await authRepo.fetchMe();
      if (!me.profileComplete) {
        debugPrint('[AUTH] destination: /onboarding/profile');
        if (context.mounted) context.go('/onboarding/profile');
        return;
      }
    } catch (_) {}
  }

  if (context.mounted) {
    await continueAfterProfileComplete(context, ref, otpProfile: otpProfile);
  }
}

/// Route by server property list after auth context is ready.
Future<void> continueAfterProfileComplete(
  BuildContext context,
  WidgetRef ref, {
  UserProfile? otpProfile,
}) async {
  final authRepo = ref.read(authRepositoryProvider);
  final propsRepo = ref.read(propertiesRepositoryProvider);
  final orgId = await authRepo.getOrganizationId();
  final scopedPropertyId = await authRepo.getScopedPropertyId();
  if (!context.mounted) return;

  debugPrint(
    '[AUTH] continueAfterProfileComplete orgId=$orgId '
    'scopedPropertyId=$scopedPropertyId',
  );

  // 1) Prefer organization property list (JWT + optional orgId).
  if (orgId != null) {
    try {
      var properties = await propsRepo.list(orgId);
      debugPrint('[AUTH] properties count (org list): ${properties.length}');

      // If list is empty but server profile says properties exist, retry via JWT.
      if (properties.isEmpty) {
        final me = otpProfile ?? await authRepo.fetchMe();
        debugPrint('[AUTH] me.propertyCount=${me.propertyCount}');
        if (me.propertyCount > 0) {
          properties = await propsRepo.list();
          debugPrint(
            '[AUTH] properties count (JWT retry): ${properties.length}',
          );
          if (properties.isEmpty) {
            // Server says properties exist — never send to Welcome.
            debugPrint(
              '[AUTH] routing decision: EXISTING USER '
              '(propertyCount>0, list empty) → /home',
            );
            if (context.mounted) context.go('/home');
            return;
          }
        }
      }

      if (!context.mounted) return;
      _routeByPropertyList(context, properties);
      return;
    } catch (e) {
      debugPrint('[AUTH] list properties failed: $e');
      // Fall through — try scoped / me.propertyCount before Welcome.
      try {
        final me = otpProfile ?? await authRepo.fetchMe();
        if (me.propertyCount > 0) {
          debugPrint(
            '[AUTH] routing decision: EXISTING USER '
            '(list failed, propertyCount>0) → /home',
          );
          if (context.mounted) context.go('/home');
          return;
        }
      } catch (_) {}
    }
  }

  // 2) Staff/manager scoped property.
  if (scopedPropertyId != null) {
    try {
      final property = await propsRepo.getById(scopedPropertyId);
      debugPrint(
        '[AUTH] routing decision: EXISTING USER (scoped) '
        '→ /property/$scopedPropertyId',
      );
      if (!context.mounted) return;
      context.go(
        '/property/$scopedPropertyId',
        extra: {'propertyName': property['name']},
      );
      return;
    } catch (e) {
      debugPrint('[AUTH] getById scoped property failed: $e');
    }
  }

  // 3) Final server check before Welcome.
  try {
    final me = otpProfile ?? await authRepo.fetchMe();
    debugPrint('[AUTH] final me.propertyCount=${me.propertyCount}');
    if (me.propertyCount > 0) {
      debugPrint(
        '[AUTH] routing decision: EXISTING USER '
        '(final propertyCount>0) → /home',
      );
      if (context.mounted) context.go('/home');
      return;
    }
  } catch (_) {}

  debugPrint('[AUTH] routing decision: NEW USER → /onboarding/welcome');
  if (context.mounted) context.go('/onboarding/welcome');
}

Future<void> routeAfterContextSelection(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> selectedContext, {
  UserProfile? otpProfile,
}) async {
  final role = selectedContext['role'];

  if (role == 'tenant') {
    if (context.mounted) context.go('/tenant/dashboard');
    return;
  }

  final authRepo = ref.read(authRepositoryProvider);

  if (role == 'owner' || role == 'admin') {
    try {
      final me = otpProfile ?? await authRepo.fetchMe();
      if (!me.profileComplete) {
        if (context.mounted) context.go('/onboarding/profile');
        return;
      }
    } catch (_) {}
  }

  if (context.mounted) {
    await continueAfterProfileComplete(context, ref, otpProfile: otpProfile);
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

void _routeByPropertyList(BuildContext context, List<dynamic> properties) {
  if (properties.isEmpty) {
    debugPrint('[AUTH] routing decision: NEW USER → /onboarding/welcome');
    context.go('/onboarding/welcome');
    return;
  }
  // Always open a property dashboard. Multi-property switching is done
  // in-app (All Properties / property switcher) — never the list gate.
  final p = properties.first as Map;
  debugPrint(
    '[AUTH] routing decision: EXISTING USER → /property/${p['id']} '
    '(${properties.length} properties)',
  );
  context.go(
    '/property/${p['id']}',
    extra: {'propertyName': p['name']},
  );
}

/// Public alias used by WelcomeScreen redirects.
void goByPropertyCount(BuildContext context, List<dynamic> properties) {
  _routeByPropertyList(context, properties);
}
