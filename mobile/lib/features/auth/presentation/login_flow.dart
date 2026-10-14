// features/auth/presentation/login_flow.dart
//
// Unauthenticated: Splash → Your Stay, Simplified → Login → OTP
// Signed in (fresh OTP or cold start), the server decides — see
// resolveLoginDestination:
//   tenant / staff / owner with properties → that workspace's dashboard
//   pending or ended tenancy only           → "stay not active" screen
//   owner with no property yet              → Welcome to Dormly (setup)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/storage/app_prefs.dart';
import '../../../core/storage/auth_storage.dart';
import '../data/auth_repository.dart';
import '../domain/user_profile.dart';
import '../domain/workspace_resolver.dart';
import '../../staff/data/staff_repository.dart';
import '../../properties/data/properties_repository.dart';

/// Signed-in routing for a fresh login and for a cold start. Workspaces and
/// tenancies always come from the server; a failure here surfaces to the
/// caller rather than falling back to owner setup.
Future<void> completeLogin(
  BuildContext context,
  WidgetRef ref, {
  UserProfile? otpProfile,
}) async {
  final authRepo = ref.read(authRepositoryProvider);
  final staffRepo = ref.read(staffRepositoryProvider);

  final invitations = await staffRepo.listMyInvitations();
  if (invitations.isNotEmpty) {
    debugPrint('[AUTH] routing decision: INVITATIONS');
    if (context.mounted) context.go('/invitations', extra: invitations);
    return;
  }

  final workspaces = await authRepo.listContexts();
  final me = await authRepo.fetchMe();
  if (me.id.isNotEmpty && await AuthStorage.userId() != me.id) {
    await AuthStorage.writeUserId(me.id);
  }
  final destination = resolveLoginDestination(
    workspaces: workspaces,
    tenancies: me.tenancies,
    fallbackPropertyCount: me.propertyCount,
    lastWorkspace: me.id.isEmpty ? null : await AppPrefs.lastWorkspace(me.id),
  );
  debugPrint('[AUTH] routing decision: ${destination.runtimeType}');
  if (context.mounted) await openLoginDestination(context, ref, destination, me);
}

Future<void> openLoginDestination(
  BuildContext context,
  WidgetRef ref,
  LoginDestination destination,
  UserProfile me,
) async {
  final authRepo = ref.read(authRepositoryProvider);
  switch (destination) {
    case OpenWorkspace(:final workspace):
      await authRepo.selectContext(workspace['type'], workspace['id']);
      if (context.mounted) {
        await routeAfterContextSelection(context, ref, workspace, otpProfile: me);
      }
    case OwnerSetup(:final workspace):
      if (workspace != null) {
        await authRepo.selectContext(workspace['type'], workspace['id']);
      } else {
        await authRepo.ensureOwnerWorkspace();
      }
      if (!context.mounted) return;
      if (!me.profileComplete) {
        context.go('/onboarding/profile');
      } else {
        await continueAfterProfileComplete(context, ref, otpProfile: me);
      }
    case TenancyUnavailable(:final status):
      if (context.mounted) context.go('/tenant/unavailable', extra: status);
  }
}

/// Cold start — refreshes the session, then routes from the server's current
/// workspaces exactly like a fresh login.
Future<void> restoreSession(BuildContext context, WidgetRef ref) async {
  final authRepo = ref.read(authRepositoryProvider);

  final ok = await authRepo.ensureValidSession();
  if (!ok) {
    await authRepo.logout();
    throw Exception('Session expired');
  }

  if (context.mounted) await completeLogin(context, ref);
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

Future<String?> _currentWorkspaceKey(AuthRepository authRepo) async {
  final type = await authRepo.getContextType();
  final id = await AuthStorage.contextId();
  return type == null || id == null ? null : '$type:$id';
}

/// Other workspaces the server currently lists for this user (not the open
/// one). Drives whether a "Switch Workspace" action is shown at all.
final otherWorkspacesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final authRepo = ref.watch(authRepositoryProvider);
  final workspaces = await authRepo.listContexts();
  return switchableWorkspaces(
    workspaces,
    currentKey: await _currentWorkspaceKey(authRepo),
  );
});

/// Switch to another server-listed workspace: re-fetches the list, opens the
/// only alternative directly or lets the user pick; the server validates the
/// selection and every later request.
Future<void> switchWorkspace(BuildContext context, WidgetRef ref) async {
  final authRepo = ref.read(authRepositoryProvider);
  final options = switchableWorkspaces(
    await authRepo.listContexts(),
    currentKey: await _currentWorkspaceKey(authRepo),
  );
  if (!context.mounted) return;

  if (options.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No other workspace on this account.')),
    );
    return;
  }
  if (options.length > 1) {
    context.push('/select-context', extra: options);
    return;
  }
  final chosen = options.single;
  await authRepo.selectContext(chosen['type'], chosen['id']);
  if (context.mounted) await routeAfterContextSelection(context, ref, chosen);
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
