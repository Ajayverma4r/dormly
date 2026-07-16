// features/auth/presentation/login_flow.dart
//
// Shared post-login routing logic. Order matters: pending invitations are
// checked BEFORE contexts, so a newly-invited manager/staff sees the
// accept/decline prompt even if they already have another context
// (e.g. they're also a tenant elsewhere).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/auth_repository.dart';
import '../../staff/data/staff_repository.dart';
import '../../properties/data/properties_repository.dart';

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

  if (contexts.length == 1) {
    final chosen = contexts.first;
    await authRepo.selectContext(chosen['type'], chosen['id']);
    if (context.mounted) await routeAfterContextSelection(context, ref, chosen);
  } else {
    if (context.mounted) context.go('/select-context', extra: contexts);
  }
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
  final orgId = await authRepo.getOrganizationId();
  final scopedPropertyId = await authRepo.getScopedPropertyId();

  if (!context.mounted) return;

  if (orgId != null) {
    final properties = await ref.read(propertiesRepositoryProvider).list(orgId);
    if (!context.mounted) return;
    if (properties.isEmpty) {
      context.go('/onboarding/welcome');
    } else {
      context.go('/home');
    }
  } else if (scopedPropertyId != null) {
    // Manager/Staff — go straight to their one assigned property's dashboard.
    final property = await ref.read(propertiesRepositoryProvider).getById(scopedPropertyId);
    if (!context.mounted) return;
    context.go('/dashboard/$scopedPropertyId', extra: {'propertyName': property['name']});
  } else {
    context.go('/onboarding/welcome');
  }
}