// features/auth/domain/workspace_resolver.dart
//
// Where a signed-in user lands, decided only from the server's workspace list
// (/auth/contexts) and the user's tenancy summary (/auth/me).
//
// An owner workspace with no properties is not proof of ownership: older
// logins gave every user, tenants included, an empty owner workspace. So a
// tenant or staff workspace wins over an empty owner one, and a user whose
// only tenancy is pending or ended is told so instead of being sent to
// property setup. Locally remembered choices only pick among workspaces the
// server lists; the server rechecks every selected workspace on each request.

import 'user_profile.dart';

sealed class LoginDestination {
  const LoginDestination();
}

/// Select this server-listed workspace and open its dashboard.
class OpenWorkspace extends LoginDestination {
  final Map<String, dynamic> workspace;
  const OpenWorkspace(this.workspace);
}

/// Owner with no property yet. [workspace] is their existing empty owner
/// workspace, or null when one must be created first.
class OwnerSetup extends LoginDestination {
  final Map<String, dynamic>? workspace;
  const OwnerSetup(this.workspace);
}

/// The user's only tenancies are pending or ended: no dashboard access.
class TenancyUnavailable extends LoginDestination {
  final String status;
  const TenancyUnavailable(this.status);
}

String workspaceKey(Map<String, dynamic> workspace) =>
    '${workspace['type']}:${workspace['id']}';

bool isOwnerRole(Object? role) => role == 'owner' || role == 'admin';

int _rank(Object? role) {
  switch (role) {
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

/// Properties in an owner/admin workspace. Servers that predate per-workspace
/// counts fall back to [fallback] (`/auth/me` propertyCount).
int workspacePropertyCount(Map<String, dynamic> workspace, {int? fallback}) =>
    (workspace['propertyCount'] as num?)?.toInt() ?? fallback ?? 0;

List<Map<String, dynamic>> _known(List<Map<String, dynamic>> workspaces) =>
    workspaces.where((w) => _rank(w['role']) < 5 && w['id'] != null).toList()
      ..sort((a, b) => _rank(a['role']).compareTo(_rank(b['role'])));

/// A workspace that opens a dashboard: any listed manager/staff/tenant
/// workspace, or an owner/admin one that has properties. Empty owner
/// workspaces (including legacy auto-created ones) only lead to setup.
bool isUsableWorkspace(Map<String, dynamic> workspace, {int? fallbackPropertyCount}) {
  if (_rank(workspace['role']) >= 5 || workspace['id'] == null) return false;
  if (!isOwnerRole(workspace['role'])) return true;
  return workspacePropertyCount(workspace, fallback: fallbackPropertyCount) > 0;
}

/// Server-listed workspaces the user can switch to from [currentKey].
List<Map<String, dynamic>> switchableWorkspaces(
  List<Map<String, dynamic>> workspaces, {
  String? currentKey,
}) =>
    _known(workspaces)
        .where((w) => isUsableWorkspace(w) && workspaceKey(w) != currentKey)
        .toList();

LoginDestination resolveLoginDestination({
  required List<Map<String, dynamic>> workspaces,
  required TenancySummary tenancies,
  int? fallbackPropertyCount,
  String? lastWorkspace,
}) {
  final known = _known(workspaces);
  final usable = known
      .where((w) => isUsableWorkspace(w, fallbackPropertyCount: fallbackPropertyCount))
      .toList();

  // The remembered workspace is only a preference among usable ones.
  if (lastWorkspace != null) {
    for (final w in usable) {
      if (workspaceKey(w) == lastWorkspace) return OpenWorkspace(w);
    }
  }

  if (usable.isNotEmpty) return OpenWorkspace(usable.first);

  if (tenancies.pending > 0) return const TenancyUnavailable('pending');
  if (tenancies.ended > 0) return const TenancyUnavailable('ended');

  final owners = known.where((w) => isOwnerRole(w['role']));
  return OwnerSetup(owners.isEmpty ? null : owners.first);
}
