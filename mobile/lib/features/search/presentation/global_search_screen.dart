// features/search/presentation/global_search_screen.dart
//
// Global search for every workspace role, backed by GET /v1/search. The
// server scopes results to the signed-in workspace (organization, assigned
// property or own tenancy) and to what the role may see.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/theme_mode.dart';

import '../../billing/presentation/whatsapp_reminder.dart'
    show normalizeWhatsAppPhone, whatsAppGreen;
import '../../properties/domain/property_archetype.dart';
import '../../structure/presentation/dynamic_dashboard/dynamic_dashboard_screen.dart'
    show contextRoleProvider;
import '../../structure/presentation/property_shell_screen.dart'
    show propertyDetailProvider;
import '../../tenancies/presentation/add_tenant_screen.dart'
    show openAddTenantFlow;
import '../data/global_search_repository.dart';
import '../data/recent_searches.dart';
import '../domain/global_search.dart';
import 'search_navigation.dart';

class _C {
  static Color get bg =>
      themed(const Color(0xFF0D1623), const Color(0xFFF6F7FB));
  static Color get card =>
      themed(const Color(0xFF151F30), const Color(0xFFFFFFFF));
  static Color get field =>
      themed(const Color(0xFF1A2438), const Color(0xFFF3F4F6));
  static Color get border =>
      themed(const Color(0xFF243044), const Color(0xFFE5E7EB));
  static Color get textPrimary =>
      themed(Colors.white, const Color(0xFF111827));
  static Color get textSecondary =>
      themed(const Color(0xFF94A3B8), const Color(0xFF6B7280));
  static Color get purple =>
      themed(const Color(0xFF8B5CF6), const Color(0xFF7C3AED));
  static Color get green =>
      themed(const Color(0xFF22C55E), const Color(0xFF16A34A));
  static Color get red =>
      themed(const Color(0xFFF87171), const Color(0xFFDC2626));
  static Color get orange =>
      themed(const Color(0xFFF2835F), const Color(0xFFEA580C));
}

final _currency =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

const searchDebounce = Duration(milliseconds: 300);

Future<void> openGlobalSearch(
  BuildContext context, {
  required String propertyId,
  required bool canManage,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => GlobalSearchScreen(
        propertyId: propertyId,
        canManage: canManage,
      ),
    ),
  );
}

/// User-facing text for a failed search. Server messages for 400/403/429/503
/// are written for users; anything else gets a fixed message.
String searchErrorMessage(Object error) {
  if (error is DioException) {
    final status = error.response?.statusCode;
    final data = error.response?.data;
    final serverMessage =
        data is Map && data['error'] is String ? data['error'] as String : null;
    if (status == 401) {
      return 'Your session has expired. Please sign in again.';
    }
    if (status == 403) {
      return serverMessage ?? 'You do not have access to search this.';
    }
    if (status == 429) {
      return serverMessage ??
          'Too many searches. Please wait a moment and try again.';
    }
    if ((status == 400 || status == 503) && serverMessage != null) {
      return serverMessage;
    }
    if (error.response == null) {
      return 'Could not reach Dormly. Check your connection and try again.';
    }
  }
  return 'Search failed. Please try again.';
}

enum _Phase { idle, loading, results, error }

class GlobalSearchScreen extends ConsumerStatefulWidget {
  /// Property the search was opened from (owner/admin results still span
  /// the whole organization). Also keys the recent-searches list.
  final String propertyId;

  /// Owner / admin / manager — billing data and add-tenant actions.
  final bool canManage;

  const GlobalSearchScreen({
    super.key,
    required this.propertyId,
    required this.canManage,
  });

  @override
  ConsumerState<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends ConsumerState<GlobalSearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  CancelToken? _inFlight;
  int _seq = 0;

  String _query = '';
  SearchQuickFilter? _filter;
  SearchCategory? _category;
  List<String> _recent = const [];

  _Phase _phase = _Phase.idle;
  List<SearchHit> _hits = const [];
  Object? _error;

  String get _recentKey => widget.propertyId;

  @override
  void initState() {
    super.initState();
    RecentSearches.load(_recentKey).then((r) {
      if (mounted) setState(() => _recent = r);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _inFlight?.cancel();
    _controller.dispose();
    super.dispose();
  }

  bool get _canSearch =>
      _filter != null || _query.trim().length >= minSearchQueryLength;

  /// Drops in-flight work and every result, e.g. after a workspace change.
  void _reset({bool clearInput = false}) {
    _debounce?.cancel();
    _inFlight?.cancel();
    _seq++;
    setState(() {
      if (clearInput) {
        _controller.clear();
        _query = '';
        _filter = null;
        _category = null;
      }
      _phase = _Phase.idle;
      _hits = const [];
      _error = null;
    });
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    _debounce?.cancel();
    if (!_canSearch) {
      _reset();
      return;
    }
    _debounce = Timer(searchDebounce, _run);
  }

  void _setQuery(String q) {
    _controller.value = TextEditingValue(
      text: q,
      selection: TextSelection.collapsed(offset: q.length),
    );
    _onQueryChanged(q);
  }

  void _searchNow() {
    _debounce?.cancel();
    if (_canSearch) {
      _run();
    } else {
      _reset();
    }
  }

  Future<void> _run() async {
    _inFlight?.cancel();
    final token = CancelToken();
    _inFlight = token;
    final seq = ++_seq;
    setState(() {
      _phase = _Phase.loading;
      _error = null;
    });
    try {
      final response = await ref.read(globalSearchRepositoryProvider).search(
            query: _query,
            category: _filter == null ? _category : null,
            filter: _filter,
            cancelToken: token,
          );
      if (!mounted || seq != _seq) return;
      setState(() {
        _hits = response.results;
        _phase = _Phase.results;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      if (e is DioException && e.type == DioExceptionType.cancel) return;
      setState(() {
        _error = e;
        _hits = const [];
        _phase = _Phase.error;
      });
    }
  }

  Future<void> _remember() async {
    if (_query.trim().length < minSearchQueryLength) return;
    final next = await RecentSearches.add(_recentKey, _query);
    if (mounted) setState(() => _recent = next);
  }

  Future<void> _clearRecent() async {
    await RecentSearches.clear(_recentKey);
    if (mounted) setState(() => _recent = const []);
  }

  String get _roomsLabel {
    final property =
        ref.watch(propertyDetailProvider(widget.propertyId)).valueOrNull;
    return switch (propertyArchetypeFromProperty(property)) {
      PropertyArchetype.sharedLiving => 'Rooms',
      PropertyArchetype.gatedCommunity => 'Flats',
      PropertyArchetype.individualLease => 'Spaces',
    };
  }

  // ---- Actions ----

  Future<void> _open(SearchHit hit, String? role) async {
    final destination = searchDestinationFor(hit, role);
    if (destination == null) return;
    await _remember();
    if (!mounted) return;
    await ref.read(searchResultOpenerProvider)(
      context,
      ref,
      destination,
      canManage: widget.canManage,
    );
    if (mounted && _canSearch) _run();
  }

  Future<void> _addTenant(SearchHit hit) async {
    await _remember();
    if (!mounted) return;
    await openAddTenantFlow(
      context: context,
      ref: ref,
      propertyId: hit.propertyId,
      nodeId: hit.nodeId ?? hit.id,
    );
    if (mounted && _canSearch) _run();
  }

  Future<void> _launch(Uri uri, String failure) async {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure)));
    }
  }

  void _call(String? phone) {
    final digits = (phone ?? '').replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.isEmpty) return;
    _launch(Uri.parse('tel:$digits'), 'Could not start a call.');
  }

  void _whatsApp(String? phone) {
    final normalized = normalizeWhatsAppPhone(phone);
    if (normalized == null) return;
    _launch(Uri.parse('https://wa.me/$normalized'), 'Could not open WhatsApp.');
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<String?>>(contextRoleProvider, (prev, next) {
      final before = prev?.valueOrNull;
      if (before != null && next.hasValue && next.valueOrNull != before) {
        _reset(clearInput: true);
      }
    });
    final roleAsync = ref.watch(contextRoleProvider);
    final role = roleAsync.valueOrNull;
    final tenant = isTenantRole(role);
    final roomsLabel = isTeamRole(role) ? _roomsLabel : 'Rooms';
    final categories = searchCategoriesForRole(role);
    final filters = searchFiltersForRole(role);
    final showProperty = role == 'owner' || role == 'admin';

    final Widget body;
    if (roleAsync.isLoading && role == null) {
      body = const SizedBox.shrink();
    } else if (role == null || categories.isEmpty) {
      body = const _Message(
        key: Key('search-unavailable'),
        text: 'Search is not available for this workspace.',
      );
    } else if (!_canSearch) {
      body = _query.trim().isNotEmpty
          ? const _Message(
              key: Key('search-min-length'),
              text: 'Type at least $minSearchQueryLength characters to search.',
            )
          : _RecentList(
              recent: _recent,
              help: searchHelpText(role),
              onTap: _setQuery,
              onClear: _clearRecent,
            );
    } else {
      body = switch (_phase) {
        _Phase.error => _ErrorState(
            message: searchErrorMessage(_error ?? 'error'),
            onRetry: _searchNow,
          ),
        _Phase.loading when _hits.isEmpty => const _Message(
            key: Key('search-loading'),
            text: 'Searching…',
          ),
        _ when _phase != _Phase.idle && _hits.isEmpty => _NoResults(
            query: _query,
            help: searchHelpText(role),
          ),
        _Phase.idle => const SizedBox.shrink(),
        _ => _ResultsList(
            groups: groupSearchHits(_hits, categories),
            tenant: tenant,
            roomsLabel: roomsLabel,
            showProperty: showProperty,
            canManage: widget.canManage && canSeeBilling(role),
            onOpen: (hit) => _open(hit, role),
            onCall: _call,
            onWhatsApp: _whatsApp,
            onAddTenant: _addTenant,
          ),
      };
    }

    return Scaffold(
      backgroundColor: _C.bg,
      appBar: AppBar(
        backgroundColor: _C.bg,
        foregroundColor: _C.textPrimary,
        elevation: 0,
        titleSpacing: 0,
        title: TextField(
          key: const Key('global-search-field'),
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          style: TextStyle(color: _C.textPrimary, fontSize: 16),
          cursorColor: _C.purple,
          decoration: InputDecoration(
            hintText: searchHint(role: role, roomsLabel: roomsLabel),
            hintStyle: TextStyle(color: _C.textSecondary, fontSize: 15),
            filled: true,
            fillColor: _C.field,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            prefixIcon:
                Icon(Icons.search, color: _C.textSecondary, size: 20),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    key: const Key('global-search-clear'),
                    tooltip: 'Clear',
                    icon: Icon(Icons.close,
                        color: _C.textSecondary, size: 20),
                    onPressed: () => _setQuery(''),
                  ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: _onQueryChanged,
          onSubmitted: (_) {
            _remember();
            _searchNow();
          },
        ),
        actions: const [SizedBox(width: 12)],
        bottom: _phase == _Phase.loading
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(
                  key: const Key('search-progress'),
                  minHeight: 2,
                  color: _C.purple,
                  backgroundColor: Colors.transparent,
                ),
              )
            : null,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (categories.length > 1)
            _ChipBar(
              chips: [
                _ChipData(
                  key: 'all',
                  label: 'All',
                  selected: _category == null && _filter == null,
                  onTap: () {
                    setState(() {
                      _category = null;
                      _filter = null;
                    });
                    _searchNow();
                  },
                ),
                for (final c in categories)
                  _ChipData(
                    key: c.wire,
                    label: searchCategoryLabel(c,
                        tenant: tenant, roomsLabel: roomsLabel),
                    selected: _category == c && _filter == null,
                    onTap: () {
                      setState(() {
                        _category = _category == c ? null : c;
                        _filter = null;
                      });
                      _searchNow();
                    },
                  ),
              ],
            ),
          if (filters.isNotEmpty)
            _ChipBar(
              chips: [
                for (final f in filters)
                  _ChipData(
                    key: f.wire,
                    label: f == SearchQuickFilter.vacant
                        ? 'Vacant ${roomsLabel.toLowerCase()}'
                        : f.label,
                    selected: _filter == f,
                    onTap: () {
                      setState(() {
                        _filter = _filter == f ? null : f;
                        _category = null;
                      });
                      _searchNow();
                    },
                  ),
              ],
            ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _ChipData {
  final String key;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ChipData({
    required this.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });
}

class _ChipBar extends StatelessWidget {
  final List<_ChipData> chips;

  const _ChipBar({required this.chips});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final chip = chips[i];
          return ChoiceChip(
            key: Key('search-chip-${chip.key}'),
            label: Text(chip.label),
            selected: chip.selected,
            showCheckmark: false,
            onSelected: (_) => chip.onTap(),
            labelStyle: TextStyle(
              color: chip.selected ? Colors.white : _C.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
            backgroundColor: _C.card,
            selectedColor: _C.purple,
            side: BorderSide(color: chip.selected ? _C.purple : _C.border),
            shape: const StadiumBorder(),
          );
        },
      ),
    );
  }
}

class _RecentList extends StatelessWidget {
  final List<String> recent;
  final String help;
  final ValueChanged<String> onTap;
  final VoidCallback onClear;

  const _RecentList({
    required this.recent,
    required this.help,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    if (recent.isEmpty) {
      return _Message(key: const Key('search-help'), text: help);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Recent searches',
                style: TextStyle(
                  color: _C.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(
              onPressed: onClear,
              style: TextButton.styleFrom(foregroundColor: _C.purple),
              child: const Text('Clear'),
            ),
          ],
        ),
        ...recent.map(
          (q) => ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.history, color: _C.textSecondary),
            title: Text(q,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _C.textPrimary)),
            trailing: Icon(Icons.north_west,
                color: _C.textSecondary, size: 18),
            onTap: () => onTap(q),
          ),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  final String text;

  const _Message({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: _C.textSecondary, fontSize: 13, height: 1.5),
        ),
      ],
    );
  }
}

class _NoResults extends StatelessWidget {
  final String query;
  final String help;

  const _NoResults({required this.query, required this.help});

  @override
  Widget build(BuildContext context) {
    final q = query.trim();
    return ListView(
      key: const Key('search-empty'),
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
      children: [
        Text(
          q.isEmpty ? 'Nothing matches this filter.' : 'No results for "$q".',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: _C.textPrimary, fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          help,
          textAlign: TextAlign.center,
          style: TextStyle(color: _C.textSecondary, fontSize: 13, height: 1.5),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('search-error'),
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
      children: [
        Icon(Icons.error_outline, color: _C.red, size: 32),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: _C.textPrimary, fontSize: 14, height: 1.4),
        ),
        const SizedBox(height: 16),
        Center(
          child: OutlinedButton.icon(
            key: const Key('search-retry'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _C.purple,
              side: BorderSide(color: _C.purple),
            ),
          ),
        ),
      ],
    );
  }
}

IconData _iconFor(SearchCategory c) => switch (c) {
      SearchCategory.properties => Icons.apartment_outlined,
      SearchCategory.rooms => Icons.meeting_room_outlined,
      SearchCategory.tenants => Icons.person_outline,
      SearchCategory.team => Icons.badge_outlined,
      SearchCategory.complaints => Icons.build_outlined,
      SearchCategory.gatePasses => Icons.qr_code_2_outlined,
      SearchCategory.invoices => Icons.receipt_long_outlined,
      SearchCategory.payments => Icons.payments_outlined,
      SearchCategory.meterReadings => Icons.speed_outlined,
      SearchCategory.messMenu => Icons.restaurant_menu_outlined,
    };

String _statusLabel(SearchHit hit) {
  final raw = hit.status ?? '';
  if (raw.isEmpty) return '';
  if (hit.category == SearchCategory.tenants && raw == 'ended') {
    return 'Checked-out';
  }
  if (hit.category == SearchCategory.invoices && raw == 'pending') return 'Due';
  final text = raw.replaceAll('_', ' ');
  return text[0].toUpperCase() + text.substring(1);
}

Color _statusColor(String status) => switch (status) {
      'overdue' || 'denied' => _C.red,
      'draft' => _C.purple,
      'paid' || 'approved' || 'resolved' || 'closed' || 'active' ||
      'occupied' =>
        _C.green,
      'ended' || 'expired' => _C.textSecondary,
      _ => _C.orange,
    };

String? _shortDate(String? raw) {
  if (raw == null) return null;
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return null;
  final local = raw.length <= 10 ? parsed : parsed.toLocal();
  return DateFormat('d MMM yyyy').format(local);
}

class _ResultsList extends StatelessWidget {
  final List<(SearchCategory, List<SearchHit>)> groups;
  final bool tenant;
  final String roomsLabel;
  final bool showProperty;
  final bool canManage;
  final ValueChanged<SearchHit> onOpen;
  final ValueChanged<String?> onCall;
  final ValueChanged<String?> onWhatsApp;
  final ValueChanged<SearchHit> onAddTenant;

  const _ResultsList({
    required this.groups,
    required this.tenant,
    required this.roomsLabel,
    required this.showProperty,
    required this.canManage,
    required this.onOpen,
    required this.onCall,
    required this.onWhatsApp,
    required this.onAddTenant,
  });

  String _details(SearchHit hit) {
    final money = hit.amount == null ? null : _currency.format(hit.amount);
    final when = _shortDate(hit.date);
    final dated = switch (hit.category) {
      SearchCategory.invoices when when != null => 'Due $when',
      SearchCategory.payments when when != null => 'Paid $when',
      _ => when,
    };
    return [
      if (showProperty && hit.category != SearchCategory.properties)
        hit.propertyName,
      hit.subtitle,
      money,
      if (hit.category != SearchCategory.tenants) dated,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
  }

  Widget? _trailing(SearchHit hit) {
    final phone = hit.phone;
    if (hit.category == SearchCategory.tenants &&
        phone != null &&
        phone.isNotEmpty) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Call',
            icon: Icon(Icons.call_outlined, color: _C.textSecondary, size: 20),
            onPressed: () => onCall(phone),
          ),
          IconButton(
            tooltip: 'WhatsApp',
            icon: const Icon(Icons.chat, color: whatsAppGreen, size: 20),
            onPressed: () => onWhatsApp(phone),
          ),
        ],
      );
    }
    if (hit.category == SearchCategory.rooms &&
        hit.status == 'vacant' &&
        canManage) {
      return TextButton(
        key: Key('search-add-tenant-${hit.id}'),
        onPressed: () => onAddTenant(hit),
        style: TextButton.styleFrom(foregroundColor: _C.purple),
        child: const Text('Add Tenant'),
      );
    }
    final label = _statusLabel(hit);
    return label.isEmpty ? null : _Pill(label, _statusColor(hit.status ?? ''));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('search-results'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        for (final (category, hits) in groups) ...[
          _SectionTitle(
            searchCategoryLabel(category,
                tenant: tenant, roomsLabel: roomsLabel),
            hits.length,
          ),
          for (final hit in hits)
            _ResultTile(
              key: Key('search-hit-${hit.category.wire}-${hit.id}'),
              icon: _iconFor(category),
              title: hit.title.isEmpty ? 'Untitled' : hit.title,
              subtitle: _details(hit),
              onTap: () => onOpen(hit),
              trailing: _trailing(hit),
            ),
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final int count;

  const _SectionTitle(this.title, this.count);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(
        '$title ($count)',
        style: TextStyle(
          color: _C.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  const _ResultTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: _C.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            child: Row(
              children: [
                Icon(icon, color: _C.purple, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _C.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _C.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: trailing!,
                  ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;

  const _Pill(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
