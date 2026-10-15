// features/staff_home/presentation/staff_ui.dart
//
// Shared look, providers and messages for the staff app (light lavender
// canvas, white cards, Dormly purple accent).

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../gate_passes/data/gate_passes_repository.dart';
import '../../properties/domain/property_archetype.dart';
import '../../structure/presentation/property_shell_screen.dart'
    show propertyDetailProvider;
import '../../tenancies/data/tenancy_repository.dart';
import '../../tenant_portal/data/tenant_portal_repository.dart';

class StaffColors {
  static const brand = AppColors.primary;
  static const brandSoft = AppColors.primarySoft;
  static const bg = Color(0xFFF7F5FF);
  static const card = Colors.white;
  static const border = Color(0xFFECE8F7);
  static const ink = AppColors.ink;
  static const muted = AppColors.slate;
  static const success = Color(0xFF16A34A);
  static const successSoft = Color(0xFFDCFCE7);
  static const warning = Color(0xFFD97706);
  static const warningSoft = Color(0xFFFEF3C7);
  static const danger = Color(0xFFDC2626);
  static const dangerSoft = Color(0xFFFEE2E2);
}

final staffGatePassesProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, propertyId) =>
      ref.watch(gatePassesRepositoryProvider).listForProperty(propertyId),
);

final staffMeterReadingsProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, propertyId) => ref
      .watch(tenantPortalRepositoryProvider)
      .listMeterReadingsForProperty(propertyId),
);

/// The server strips phone, KYC, rent and dues from staff responses.
final staffTenanciesProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, propertyId) =>
      ref.watch(tenancyRepositoryProvider).listByProperty(propertyId),
);

/// Archetype of the property, or null until it has loaded.
PropertyArchetype? staffPropertyArchetype(WidgetRef ref, String propertyId) {
  final property = ref.watch(propertyDetailProvider(propertyId)).valueOrNull;
  return property == null ? null : propertyArchetypeFromProperty(property);
}

/// User-facing text for a failed request; never raw server or Dio details.
String staffErrorMessage(Object error,
    {String fallback = 'Something went wrong. Please try again.'}) {
  if (error is DioException) {
    final status = error.response?.statusCode;
    if (status == 401) return 'Your session has expired. Please sign in again.';
    if (status == 403) return "Your staff role doesn't include this action.";
    if (status == 404) {
      return 'This item could not be found. Pull down to refresh.';
    }
    if (status == null) {
      return 'Could not reach the server. Check your connection and try again.';
    }
  }
  return fallback;
}

String staffGreeting([DateTime? now]) {
  final h = (now ?? DateTime.now()).hour;
  if (h < 12) return 'Good Morning';
  if (h < 17) return 'Good Afternoon';
  return 'Good Evening';
}

String initialOf(String? name) {
  final n = name?.trim() ?? '';
  return n.isEmpty ? '?' : n[0].toUpperCase();
}

BoxDecoration staffCardDecoration({double radius = 16}) => BoxDecoration(
      color: StaffColors.card,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: StaffColors.border),
      boxShadow: const [
        BoxShadow(
            color: Color(0x0A4C1D95), blurRadius: 12, offset: Offset(0, 4)),
      ],
    );

class StaffAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final bool showBack;

  const StaffAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    this.showBack = true,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: StaffColors.bg,
      foregroundColor: StaffColors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      automaticallyImplyLeading: showBack,
      title: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: StaffColors.ink,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (subtitle != null && subtitle!.isNotEmpty)
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: StaffColors.muted, fontSize: 12),
            ),
        ],
      ),
      actions: actions,
    );
  }
}

class StaffMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const StaffMessage({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: StaffColors.brandSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 30, color: StaffColors.brand),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: StaffColors.ink,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: StaffColors.muted, fontSize: 13, height: 1.4),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class StaffErrorState extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  final String fallback;

  const StaffErrorState({
    super.key,
    required this.error,
    required this.onRetry,
    this.fallback = "Couldn't load this right now. Please try again.",
  });

  @override
  Widget build(BuildContext context) {
    return StaffMessage(
      icon: Icons.cloud_off_rounded,
      title: staffErrorMessage(error, fallback: fallback),
      action: FilledButton(
        onPressed: onRetry,
        style: FilledButton.styleFrom(backgroundColor: StaffColors.brand),
        child: const Text('Retry'),
      ),
    );
  }
}

/// Scrollable wrapper so empty and error states still support pull-to-refresh.
class StaffScrollableMessage extends StatelessWidget {
  final Widget child;
  const StaffScrollableMessage({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [const SizedBox(height: 80), child],
    );
  }
}

class StaffPill extends StatelessWidget {
  final String label;
  final Color fg;
  final Color bg;
  final IconData? icon;

  const StaffPill({
    super.key,
    required this.label,
    required this.fg,
    required this.bg,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: fg, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class StaffSectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const StaffSectionHeader(
      {super.key, required this.title, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: StaffColors.ink,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: StaffColors.brand,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(actionLabel!,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
      ],
    );
  }
}
