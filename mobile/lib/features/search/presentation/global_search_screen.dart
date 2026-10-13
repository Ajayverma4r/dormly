// features/search/presentation/global_search_screen.dart
//
// Property-wide search: tenants, rooms/flats/spaces, invoices and complaints.
// Filters data the app already loads — no extra backend endpoint.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/theme_mode.dart';

import '../../billing/presentation/billing_invoice_helpers.dart'
    show invoiceCalendarDate, invoiceRemaining, isDraftInvoice, isOverdueInvoice;
import '../../billing/presentation/billing_providers.dart';
import '../../billing/presentation/invoice_detail_screen.dart';
import '../../billing/presentation/whatsapp_reminder.dart'
    show normalizeWhatsAppPhone, whatsAppGreen;
import '../../complaints/presentation/complaints_list_screen.dart'
    show complaintsProvider;
import '../../properties/domain/property_archetype.dart';
import '../../structure/presentation/property_shell_screen.dart'
    show propertyDetailProvider;
import '../../structure/presentation/rooms/room_list_filter.dart';
import '../../structure/presentation/rooms/rooms_tree_provider.dart';
import '../../tenancies/presentation/add_tenant_screen.dart'
    show openAddTenantFlow;
import '../../tenancies/presentation/node_detail_screen.dart';
import '../../tenancies/presentation/rental_space_detail_screen.dart';
import '../../tenancies/presentation/tenancy_providers.dart';
import '../../tenancies/presentation/tenant_profile_screen.dart';
import '../data/recent_searches.dart';
import '../domain/global_search.dart';

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

class GlobalSearchScreen extends ConsumerStatefulWidget {
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
  String _query = '';
  SearchQuickFilter? _filter;
  List<String> _recent = const [];

  @override
  void initState() {
    super.initState();
    RecentSearches.load(widget.propertyId).then((r) {
      if (mounted) setState(() => _recent = r);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setQuery(String q) {
    _controller.value = TextEditingValue(
      text: q,
      selection: TextSelection.collapsed(offset: q.length),
    );
    setState(() => _query = q);
  }

  Future<void> _remember() async {
    if (_query.trim().length < 2) return;
    final next = await RecentSearches.add(widget.propertyId, _query);
    if (mounted) setState(() => _recent = next);
  }

  Future<void> _clearRecent() async {
    await RecentSearches.clear(widget.propertyId);
    if (mounted) setState(() => _recent = const []);
  }

  bool get _isRental {
    final property =
        ref.read(propertyDetailProvider(widget.propertyId)).valueOrNull;
    return propertyArchetypeFromProperty(property) ==
        PropertyArchetype.individualLease;
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

  // ---- Navigation ----

  Future<void> _openTenant(Map<String, dynamic> t) async {
    final id = t['id']?.toString() ?? '';
    if (id.isEmpty) return;
    await _remember();
    if (!mounted) return;
    await Navigator.of(context).push(
      TenantProfileScreen.route(
        propertyId: widget.propertyId,
        tenancyId: id,
        initialTenancy: t,
      ),
    );
    ref.invalidate(propertyResidentsProvider(widget.propertyId));
  }

  Future<void> _openNode(String nodeId, String name, String levelName) async {
    if (nodeId.isEmpty) return;
    await _remember();
    if (!mounted) return;
    await Navigator.of(context).push(
      _isRental
          ? RentalSpaceDetailScreen.route(
              propertyId: widget.propertyId,
              nodeId: nodeId,
              canManage: widget.canManage,
            )
          : NodeDetailScreen.route(
              propertyId: widget.propertyId,
              nodeId: nodeId,
              nodeName: name,
              levelName: levelName,
            ),
    );
    ref.invalidate(roomsTreeProvider(widget.propertyId));
  }

  Future<void> _addTenant(SearchRoom room) async {
    await _remember();
    if (!mounted) return;
    await openAddTenantFlow(
      context: context,
      ref: ref,
      propertyId: widget.propertyId,
      nodeId: room.id,
    );
    ref.invalidate(roomsTreeProvider(widget.propertyId));
    ref.invalidate(propertyResidentsProvider(widget.propertyId));
  }

  Future<void> _openInvoice(Map<String, dynamic> inv) async {
    final id = inv['id']?.toString() ?? '';
    if (id.isEmpty) return;
    await _remember();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            InvoiceDetailScreen(propertyId: widget.propertyId, invoiceId: id),
      ),
    );
    ref.invalidate(invoicesProvider(widget.propertyId));
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
    final residentsAsync =
        ref.watch(propertyResidentsProvider(widget.propertyId));
    final treeAsync = ref.watch(roomsTreeProvider(widget.propertyId));
    final complaintsAsync = ref.watch(complaintsProvider(widget.propertyId));
    final invoicesAsync = widget.canManage
        ? ref.watch(invoicesProvider(widget.propertyId))
        : const AsyncValue<List<Map<String, dynamic>>>.data([]);

    final loading = residentsAsync.isLoading ||
        treeAsync.isLoading ||
        complaintsAsync.isLoading ||
        invoicesAsync.isLoading;

    final rooms = treeAsync.valueOrNull == null
        ? const <SearchRoom>[]
        : collectRoomListEntries(treeAsync.value!)
            .map((e) => SearchRoom(
                  id: e.room.id,
                  name: e.room.name,
                  blockName: e.blockName,
                  levelName: e.room.level.displayName,
                  occupied: e.isOccupied,
                  tenantName: e.room.tenantDisplayName,
                ))
            .toList();

    final results = runGlobalSearch(
      query: _query,
      filter: _filter,
      tenants: residentsAsync.valueOrNull ?? const [],
      rooms: rooms,
      invoices: invoicesAsync.valueOrNull ?? const [],
      complaints: complaintsAsync.valueOrNull ?? const [],
    );

    final idle = _query.trim().isEmpty && _filter == null;

    return Scaffold(
      backgroundColor: _C.bg,
      appBar: AppBar(
        backgroundColor: _C.bg,
        foregroundColor: _C.textPrimary,
        elevation: 0,
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          style: TextStyle(color: _C.textPrimary, fontSize: 16),
          cursorColor: _C.purple,
          decoration: InputDecoration(
            hintText: 'Search tenants, ${_roomsLabel.toLowerCase()}, invoices…',
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
                    icon: Icon(Icons.close,
                        color: _C.textSecondary, size: 20),
                    onPressed: () => _setQuery(''),
                  ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: (v) => setState(() => _query = v),
          onSubmitted: (_) => _remember(),
        ),
        actions: const [SizedBox(width: 12)],
        bottom: loading
            ? PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(
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
          _QuickFilterBar(
            selected: _filter,
            showBilling: widget.canManage,
            roomsLabel: _roomsLabel,
            onSelected: (f) => setState(() => _filter = f),
          ),
          Expanded(
            child: idle
                ? _RecentList(
                    recent: _recent,
                    onTap: _setQuery,
                    onClear: _clearRecent,
                  )
                : results.isEmpty
                    ? _NoResults(loading: loading, query: _query)
                    : _ResultsList(
                        results: results,
                        roomsLabel: _roomsLabel,
                        canManage: widget.canManage,
                        onTenant: _openTenant,
                        onCall: _call,
                        onWhatsApp: _whatsApp,
                        onRoom: (r) => _openNode(r.id, r.name, r.levelName),
                        onAddTenant: _addTenant,
                        onInvoice: _openInvoice,
                        onComplaint: (c) => _openNode(
                          c['node_id']?.toString() ?? '',
                          c['node_name']?.toString() ?? 'Room',
                          'Room',
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _QuickFilterBar extends StatelessWidget {
  final SearchQuickFilter? selected;
  final bool showBilling;
  final String roomsLabel;
  final ValueChanged<SearchQuickFilter?> onSelected;

  const _QuickFilterBar({
    required this.selected,
    required this.showBilling,
    required this.roomsLabel,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final filters = [
      if (showBilling) SearchQuickFilter.overdue,
      if (showBilling) SearchQuickFilter.drafts,
      SearchQuickFilter.vacant,
      SearchQuickFilter.checkedOut,
    ];
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final f = filters[i];
          final isOn = selected == f;
          final label = f == SearchQuickFilter.vacant
              ? 'Vacant ${roomsLabel.toLowerCase()}'
              : f.label;
          return ChoiceChip(
            label: Text(label),
            selected: isOn,
            showCheckmark: false,
            onSelected: (_) => onSelected(isOn ? null : f),
            labelStyle: TextStyle(
              color: isOn ? Colors.white : _C.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
            backgroundColor: _C.card,
            selectedColor: _C.purple,
            side: BorderSide(color: isOn ? _C.purple : _C.border),
            shape: const StadiumBorder(),
          );
        },
      ),
    );
  }
}

class _RecentList extends StatelessWidget {
  final List<String> recent;
  final ValueChanged<String> onTap;
  final VoidCallback onClear;

  const _RecentList({
    required this.recent,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    if (recent.isEmpty) {
      return Padding(
        padding: EdgeInsets.fromLTRB(24, 32, 24, 0),
        child: Text(
          'Search by name, phone, room or flat number, month ("Nov"), '
          'invoice status ("overdue", "draft") or complaint ticket.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _C.textSecondary, fontSize: 13, height: 1.5),
        ),
      );
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
            title: Text(q, style: TextStyle(color: _C.textPrimary)),
            trailing: Icon(Icons.north_west,
                color: _C.textSecondary, size: 18),
            onTap: () => onTap(q),
          ),
        ),
      ],
    );
  }
}

class _NoResults extends StatelessWidget {
  final bool loading;
  final String query;

  const _NoResults({required this.loading, required this.query});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 0),
      child: Text(
        loading
            ? 'Loading…'
            : query.trim().isEmpty
                ? 'Nothing matches this filter.'
                : 'No results for "${query.trim()}".',
        textAlign: TextAlign.center,
        style: TextStyle(color: _C.textSecondary, fontSize: 14),
      ),
    );
  }
}

class _ResultsList extends StatelessWidget {
  final GlobalSearchResults results;
  final String roomsLabel;
  final bool canManage;
  final ValueChanged<Map<String, dynamic>> onTenant;
  final ValueChanged<String?> onCall;
  final ValueChanged<String?> onWhatsApp;
  final ValueChanged<SearchRoom> onRoom;
  final ValueChanged<SearchRoom> onAddTenant;
  final ValueChanged<Map<String, dynamic>> onInvoice;
  final ValueChanged<Map<String, dynamic>> onComplaint;

  const _ResultsList({
    required this.results,
    required this.roomsLabel,
    required this.canManage,
    required this.onTenant,
    required this.onCall,
    required this.onWhatsApp,
    required this.onRoom,
    required this.onAddTenant,
    required this.onInvoice,
    required this.onComplaint,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        if (results.tenants.isNotEmpty) ...[
          _SectionTitle('Tenants', results.tenants.length),
          ...results.tenants.map((t) {
            final phone = t['phone']?.toString();
            final hasPhone = (phone ?? '').trim().isNotEmpty;
            final ended = t['status']?.toString() == 'ended';
            return _ResultTile(
              icon: Icons.person_outline,
              title: (t['full_name'] ?? t['user_name'] ?? 'Tenant').toString(),
              subtitle: [
                if ((t['node_name'] ?? '').toString().isNotEmpty)
                  t['node_name'].toString(),
                if ((t['floor_name'] ?? '').toString().isNotEmpty)
                  t['floor_name'].toString(),
                if (hasPhone) phone!,
                if (ended) 'Checked-out',
              ].join(' · '),
              onTap: () => onTenant(t),
              trailing: hasPhone
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Call',
                          icon: Icon(Icons.call_outlined,
                              color: _C.textSecondary, size: 20),
                          onPressed: () => onCall(phone),
                        ),
                        IconButton(
                          tooltip: 'WhatsApp',
                          icon: const Icon(Icons.chat,
                              color: whatsAppGreen, size: 20),
                          onPressed: () => onWhatsApp(phone),
                        ),
                      ],
                    )
                  : null,
            );
          }),
        ],
        if (results.rooms.isNotEmpty) ...[
          _SectionTitle(roomsLabel, results.rooms.length),
          ...results.rooms.map((r) {
            return _ResultTile(
              icon: Icons.meeting_room_outlined,
              title: r.name,
              subtitle: [
                if (r.blockName.isNotEmpty && r.blockName != r.name)
                  r.blockName,
                r.occupied
                    ? ((r.tenantName ?? '').isNotEmpty
                        ? r.tenantName!
                        : 'Occupied')
                    : 'Vacant',
              ].join(' · '),
              onTap: () => onRoom(r),
              trailing: !r.occupied && canManage
                  ? TextButton(
                      onPressed: () => onAddTenant(r),
                      style: TextButton.styleFrom(foregroundColor: _C.purple),
                      child: const Text('Add Tenant'),
                    )
                  : _Pill(
                      r.occupied ? 'Occupied' : 'Vacant',
                      r.occupied ? _C.green : _C.orange,
                    ),
            );
          }),
        ],
        if (results.invoices.isNotEmpty) ...[
          _SectionTitle('Invoices', results.invoices.length),
          ...results.invoices.map((i) {
            final draft = isDraftInvoice(i);
            final overdue = isOverdueInvoice(i);
            final balance = invoiceRemaining(i);
            final paid = !draft && balance <= 0.009;
            final (label, color) = draft
                ? ('Draft', _C.purple)
                : overdue
                    ? ('Overdue', _C.red)
                    : paid
                        ? ('Paid', _C.green)
                        : ('Due', _C.orange);
            return _ResultTile(
              icon: Icons.receipt_long_outlined,
              title: '${i['full_name'] ?? 'Tenant'} · ${_period(i)}',
              subtitle:
                  '${_currency.format(paid ? invoiceTotal(i) : balance)} · Due ${_date(i['due_date'])}',
              onTap: () => onInvoice(i),
              trailing: _Pill(label, color),
            );
          }),
        ],
        if (results.complaints.isNotEmpty) ...[
          _SectionTitle('Complaints', results.complaints.length),
          ...results.complaints.map((c) {
            final status =
                (c['status'] ?? 'open').toString().replaceAll('_', ' ');
            final open = !{'resolved', 'closed'}.contains(c['status']);
            return _ResultTile(
              icon: Icons.build_outlined,
              title: [
                if ((c['ticket_number'] ?? '').toString().isNotEmpty)
                  c['ticket_number'].toString(),
                (c['category'] ?? 'Complaint').toString(),
              ].join(' · '),
              subtitle: [
                (c['node_name'] ?? '').toString(),
                (c['description'] ?? '').toString(),
              ].where((s) => s.isNotEmpty).join(' · '),
              onTap: () => onComplaint(c),
              trailing: _Pill(
                status[0].toUpperCase() + status.substring(1),
                open ? _C.orange : _C.green,
              ),
            );
          }),
        ],
      ],
    );
  }

  static double invoiceTotal(Map<String, dynamic> i) =>
      double.tryParse(i['total_amount']?.toString() ?? '') ?? 0;

  static String _date(dynamic raw) {
    final d = invoiceCalendarDate(raw);
    return d == null ? '—' : DateFormat('d MMM').format(d);
  }

  static String _period(Map<String, dynamic> i) {
    final d = invoiceCalendarDate(i['period_start'] ?? i['due_date']);
    return d == null ? 'Invoice' : DateFormat('MMM yyyy').format(d);
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
                          maxLines: 1,
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
                if (trailing != null) trailing!,
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
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
