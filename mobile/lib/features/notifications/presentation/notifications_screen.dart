// features/notifications/presentation/notifications_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../data/notifications_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../tenancies/presentation/tenant_profile_screen.dart';

final notificationsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final items = await ref.watch(notificationsRepositoryProvider).list();
  // ignore: avoid_print
  print('>>> FETCHED NOTIFICATIONS COUNT: ${items.length} <<<');
  // ignore: avoid_print
  print(
    '>>> NOTIFICATION TYPES: ${items.map((e) => e['type']).join(' | ')} <<<',
  );
  return items;
});

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

  @override
  void initState() {
    super.initState();
    // Force a fresh network fetch immediately — do not rely on cached provider.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadFresh();
    });
  }

  Future<void> _loadFresh() async {
    // ignore: avoid_print
    print('>>> NOTIFICATIONS SCREEN FORCE FETCH <<<');
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      ref.invalidate(notificationsProvider);
      final list = await ref.read(notificationsRepositoryProvider).list();
      // ignore: avoid_print
      print('>>> FETCHED NOTIFICATIONS COUNT: ${list.length} <<<');
      for (final n in list) {
        // ignore: avoid_print
        print('>>> NOTIF: type=${n['type']} title=${n['title']} <<<');
      }
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e, st) {
      // ignore: avoid_print
      print('>>> NOTIFICATIONS FETCH ERROR: $e\n$st <<<');
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

  String? _formatTimestamp(dynamic raw) {
    if (raw == null) return null;
    final dt = DateTime.tryParse(raw.toString());
    if (dt == null) return null;
    return DateFormat('dd MMM yyyy · hh:mm a').format(dt.toLocal());
  }

  Future<void> _onTap(BuildContext context, Map<String, dynamic> n) async {
    if (!_isMoveOut(n)) return;
    final tenancyId = _tenancyIdFrom(n);
    final propertyId = _propertyIdFrom(n);
    // ignore: avoid_print
    print(
      '>>> MOVE-OUT NOTIF TAP <<< tenancyId=$tenancyId propertyId=$propertyId',
    );
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

    await Navigator.of(context).push(
      TenantProfileScreen.route(
        propertyId: propertyId,
        tenancyId: tenancyId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
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
                            final tappable = _isMoveOut(n) &&
                                (_tenancyIdFrom(n)?.isNotEmpty ?? false) &&
                                (_propertyIdFrom(n)?.isNotEmpty ?? false);
                            final ts = _formatTimestamp(
                                n['created_at'] ?? n['createdAt']);
                            final icon = _isMoveOut(n)
                                ? Icons.logout_rounded
                                : Icons.notifications_active_outlined;

                            return Material(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(14),
                              child: InkWell(
                                onTap:
                                    tappable ? () => _onTap(context, n) : null,
                                borderRadius: BorderRadius.circular(14),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(icon, color: AppColors.blueprint),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              n['title']?.toString() ?? '',
                                              style:
                                                  theme.textTheme.titleMedium,
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
                                      if (tappable)
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
