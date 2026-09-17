// features/notifications/presentation/notifications_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../data/notifications_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../subscription/presentation/paywall_screen.dart';
import '../../tenancies/presentation/tenant_profile_screen.dart';
import 'notifications_providers.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<Map<String, dynamic>>? _items;
  Object? _error;
  bool _loading = true;
  bool _markingAll = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFresh());
  }

  Future<void> _loadFresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      ref.invalidate(notificationsProvider);
      final list = await ref.read(notificationsRepositoryProvider).list();
      await ref.read(unreadNotificationsCountProvider.notifier).refresh();
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.trim().startsWith('{')) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return const {};
  }

  String? _tenancyIdFrom(Map<String, dynamic> n) {
    final data = _asMap(n['data']);
    final fromData =
        data['tenancy_id']?.toString() ?? data['tenancyId']?.toString();
    if (fromData != null && fromData.isNotEmpty) return fromData;
    final type = (n['type'] ?? '').toString();
    if (type.startsWith('move_out_request:')) {
      final id = type.substring('move_out_request:'.length).trim();
      if (id.isNotEmpty) return id;
    }
    return n['tenancy_id']?.toString() ?? n['tenancyId']?.toString();
  }

  String? _propertyIdFrom(Map<String, dynamic> n) {
    final data = _asMap(n['data']);
    final fromData =
        data['property_id']?.toString() ?? data['propertyId']?.toString();
    if (fromData != null && fromData.isNotEmpty) return fromData;
    return n['property_id']?.toString() ?? n['propertyId']?.toString();
  }

  bool _isMoveOut(Map<String, dynamic> n) {
    final type = (n['type'] ?? '').toString();
    return type == 'move_out_request' ||
        type.startsWith('move_out_request:') ||
        type == 'move_out';
  }

  bool _isMoveOutApproved(Map<String, dynamic> n) {
    final type = (n['type'] ?? '').toString();
    return type == 'move_out_approved' || type == 'move_out_modified';
  }

  bool _isSubscription(Map<String, dynamic> n) {
    final type = (n['type'] ?? '').toString().toLowerCase();
    return type == 'subscription_ending_soon' ||
        type == 'subscription_expiry_warning' ||
        type == 'subscription' ||
        type.startsWith('subscription_');
  }

  bool _isRentReminder(Map<String, dynamic> n) {
    final type = (n['type'] ?? '').toString().toLowerCase();
    final title = (n['title'] ?? '').toString().toLowerCase();
    return type == 'rent_reminder' ||
        type == 'payment_reminder' ||
        title.contains('rent reminder');
  }

  /// True when this notification has a known deep-link target.
  bool _isRoutable(Map<String, dynamic> n) {
    if (_isMoveOut(n)) {
      return (_tenancyIdFrom(n)?.isNotEmpty ?? false) &&
          (_propertyIdFrom(n)?.isNotEmpty ?? false);
    }
    if (_isMoveOutApproved(n)) return true;
    if (_isSubscription(n)) return true;
    if (_isRentReminder(n)) return true;
    final data = _asMap(n['data']);
    final route = data['route']?.toString();
    return route != null && route.isNotEmpty;
  }

  IconData _iconFor(Map<String, dynamic> n) {
    if (_isMoveOutApproved(n)) return Icons.check_circle_rounded;
    if (_isMoveOut(n)) return Icons.logout_rounded;
    if (_isSubscription(n)) return Icons.workspace_premium_outlined;
    if (_isRentReminder(n)) return Icons.payments_outlined;
    return Icons.notifications_active_outlined;
  }

  Color _iconColorFor(Map<String, dynamic> n) {
    if (_isMoveOutApproved(n)) return const Color(0xFF10B981);
    if (_isRentReminder(n)) return const Color(0xFFD97706);
    return AppColors.blueprint;
  }

  Future<void> _routeNotification(
    BuildContext context,
    Map<String, dynamic> n,
  ) async {
    final type = (n['type'] ?? '').toString();
    final data = _asMap(n['data']);

    if (_isRentReminder(n) ||
        type == 'rent_reminder' ||
        data['route']?.toString().contains('payments') == true) {
      if (!context.mounted) return;
      // Land on My Home Rent & Payments (opens dues sheet).
      context.go('/tenant/dashboard?focus=payments');
      return;
    }

    if (_isMoveOutApproved(n)) {
      // Tenant confirmation — return to My Home.
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(n['body']?.toString() ?? 'Move-out notice confirmed.'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
      if (context.mounted) context.go('/tenant/dashboard');
      return;
    }

    if (_isMoveOut(n) || type == 'move_out_request') {
      final tenancyId = _tenancyIdFrom(n);
      final propertyId = _propertyIdFrom(n);
      if (tenancyId == null ||
          tenancyId.isEmpty ||
          propertyId == null ||
          propertyId.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not open tenant profile for this request.'),
            ),
          );
        }
        return;
      }
      if (!context.mounted) return;
      await Navigator.of(context).push(
        TenantProfileScreen.route(
          propertyId: propertyId,
          tenancyId: tenancyId,
        ),
      );
      return;
    }

    if (_isSubscription(n)) {
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const PaywallScreen(
            reason: 'Your subscription is ending soon. Renew to keep Premium.',
          ),
        ),
      );
      return;
    }

    // Generic payload route (e.g. data.route = '/subscription' or named path).
    final route = data['route']?.toString();
    if (route == null || route.isEmpty) return;

    if (!context.mounted) return;
    if (route == '/subscription' ||
        route == '/paywall' ||
        route == '/pricing') {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PaywallScreen()),
      );
      return;
    }
    if (route.contains('payments') ||
        route.contains('tenant/dashboard')) {
      context.go(route.startsWith('/') ? route : '/$route');
      return;
    }
    if (route == '/tenant-profile') {
      final tenancyId = _tenancyIdFrom(n);
      final propertyId = _propertyIdFrom(n);
      if (tenancyId != null &&
          tenancyId.isNotEmpty &&
          propertyId != null &&
          propertyId.isNotEmpty) {
        await Navigator.of(context).push(
          TenantProfileScreen.route(
            propertyId: propertyId,
            tenancyId: tenancyId,
          ),
        );
      }
      return;
    }

    // Fall through: try go_router-style named path via Navigator if registered.
    try {
      await Navigator.of(context).pushNamed(route);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No screen for route: $route')),
        );
      }
    }
  }

  Future<void> _onTap(BuildContext context, Map<String, dynamic> n) async {
    // Mark read immediately, then deep-link.
    await _markReadOptimistic(n);
    if (!context.mounted) return;
    await _routeNotification(context, n);
  }

  String? _formatTimestamp(dynamic raw) {
    if (raw == null) return null;
    final dt = DateTime.tryParse(raw.toString());
    if (dt == null) return null;
    return DateFormat('dd MMM yyyy · hh:mm a').format(dt.toLocal());
  }

  Future<void> _markReadOptimistic(Map<String, dynamic> n) async {
    final id = n['id']?.toString() ?? '';
    if (id.isEmpty) return;
    if (NotificationsRepository.isRead(n)) return;

    final nowIso = DateTime.now().toUtc().toIso8601String();
    setState(() {
      _items = [
        for (final item in _items ?? const <Map<String, dynamic>>[])
          if (item['id']?.toString() == id)
            {
              ...item,
              'read_at': nowIso,
              'is_read': true,
              'isRead': true,
            }
          else
            item,
      ];
    });
    ref.read(unreadNotificationsCountProvider.notifier).optimisticDecrement();

    try {
      await ref.read(notificationsRepositoryProvider).markRead(id);
    } catch (_) {
      // Keep optimistic state; next refresh will reconcile.
    }
  }

  Future<void> _markAllRead() async {
    if (_markingAll) return;
    final unread = (_items ?? const [])
        .where((n) => !NotificationsRepository.isRead(n))
        .toList();
    if (unread.isEmpty) return;

    setState(() {
      _markingAll = true;
      final nowIso = DateTime.now().toUtc().toIso8601String();
      _items = [
        for (final item in _items ?? const <Map<String, dynamic>>[])
          {
            ...item,
            'read_at': item['read_at'] ?? nowIso,
            'is_read': true,
            'isRead': true,
          },
      ];
    });
    ref.read(unreadNotificationsCountProvider.notifier).optimisticClear();

    try {
      await ref.read(notificationsRepositoryProvider).markAllRead();
    } catch (_) {}
    if (mounted) setState(() => _markingAll = false);
  }

  bool get _hasUnread =>
      (_items ?? const []).any((n) => !NotificationsRepository.isRead(n));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (_hasUnread)
            TextButton(
              onPressed: _markingAll ? null : _markAllRead,
              child: _markingAll
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Mark all as read'),
            ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadFresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Something went wrong: $_error'),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _loadFresh,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadFresh,
                  child: (_items == null || _items!.isEmpty)
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(24),
                          children: [
                            const SizedBox(height: 80),
                            const Icon(Icons.notifications_none,
                                size: 48, color: AppColors.slate),
                            const SizedBox(height: 12),
                            Text(
                              'No notifications yet',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyLarge,
                            ),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(20),
                          itemCount: _items!.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final n = _items![i];
                            final unread = !NotificationsRepository.isRead(n);
                            final routable = _isRoutable(n);
                            final ts = _formatTimestamp(
                                n['created_at'] ?? n['createdAt']);
                            final icon = _iconFor(n);

                            return Material(
                              color: unread
                                  ? AppColors.primarySoft.withValues(alpha: 0.35)
                                  : AppColors.surface,
                              borderRadius: BorderRadius.circular(14),
                              child: InkWell(
                                onTap: () => _onTap(context, n),
                                borderRadius: BorderRadius.circular(14),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          Icon(icon,
                                              color: _iconColorFor(n)),
                                          if (unread)
                                            Positioned(
                                              right: -2,
                                              top: -2,
                                              child: Container(
                                                width: 8,
                                                height: 8,
                                                decoration: const BoxDecoration(
                                                  color: AppColors.danger,
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              n['title']?.toString() ?? '',
                                              style: theme
                                                  .textTheme.titleMedium
                                                  ?.copyWith(
                                                fontWeight: unread
                                                    ? FontWeight.w800
                                                    : FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              n['body']?.toString() ?? '',
                                              style: theme
                                                  .textTheme.bodyMedium
                                                  ?.copyWith(
                                                color: AppColors.slate,
                                              ),
                                            ),
                                            if (ts != null) ...[
                                              const SizedBox(height: 6),
                                              Text(
                                                ts,
                                                style: theme
                                                    .textTheme.bodySmall
                                                    ?.copyWith(
                                                  color: AppColors.slate,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      if (routable)
                                        const Padding(
                                          padding:
                                              EdgeInsets.only(left: 4, top: 2),
                                          child: Icon(
                                            Icons.chevron_right_rounded,
                                            color: AppColors.slate,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}
