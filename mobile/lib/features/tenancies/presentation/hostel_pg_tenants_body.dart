// features/tenancies/presentation/hostel_pg_tenants_body.dart
// Screen 2 — Hostel / PG Tenants list (dark). Rental / apartment keep residents_list_screen.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/theme_mode.dart';

import '../domain/tenant_filters.dart';

/// Palette aligned with Hostel/PG dashboard (Screen 1).
class _H {
  static Color get bg =>
      themed(const Color(0xFF0D1623), const Color(0xFFF6F7FB));
  static Color get card =>
      themed(const Color(0xFF151F30), const Color(0xFFFFFFFF));
  static Color get cardElevated =>
      themed(const Color(0xFF1A2438), const Color(0xFFFFFFFF));
  static Color get field =>
      themed(const Color(0xFF121C2C), const Color(0xFFF3F4F6));
  static Color get textPrimary =>
      themed(const Color(0xFFFFFFFF), const Color(0xFF111827));
  static Color get textSecondary =>
      themed(const Color(0xFF94A3B8), const Color(0xFF6B7280));
  static Color get purple =>
      themed(const Color(0xFF8B5CF6), const Color(0xFF7C3AED));
  static Color get purpleBright =>
      themed(const Color(0xFF7C3AED), const Color(0xFF7C3AED));
  static Color get green =>
      themed(const Color(0xFF22C55E), const Color(0xFF16A34A));
  static Color get greenBg =>
      themed(const Color(0xFF1A3A2A), const Color(0xFFDCFCE7));
  static Color get orange =>
      themed(const Color(0xFFF2835F), const Color(0xFFEA580C));
  static Color get orangeBg =>
      themed(const Color(0xFF3E2A22), const Color(0xFFFFEDD5));
  static Color get red =>
      themed(const Color(0xFFF87171), const Color(0xFFDC2626));
  static Color get redBg =>
      themed(const Color(0xFF3A1F28), const Color(0xFFFEE2E2));
  static Color get slate =>
      themed(const Color(0xFF64748B), const Color(0xFF64748B));
  static Color get slateBg =>
      themed(const Color(0xFF1E293B), const Color(0xFFF1F5F9));
}

class HostelPgTenantsBody extends StatefulWidget {
  final List<Map<String, dynamic>> residents;
  final Future<void> Function() onAdd;
  final Future<void> Function(Map<String, dynamic> resident) onOpen;

  const HostelPgTenantsBody({
    super.key,
    required this.residents,
    required this.onAdd,
    required this.onOpen,
  });

  @override
  State<HostelPgTenantsBody> createState() => _HostelPgTenantsBodyState();
}

class _HostelPgTenantsBodyState extends State<HostelPgTenantsBody> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  HostelGuestFilter _filter = HostelGuestFilter.active;
  TenantPaymentFilter _payment = TenantPaymentFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final residents = widget.residents;
    final active = residents.where(isActiveTenancy).toList();
    final allCount = residents.length;
    final activeCount = active.length;
    final checkedOutCount = residents.where(isCheckedOutTenancy).length;
    final payCounts = <TenantPaymentStatus, int>{
      for (final s in TenantPaymentStatus.values) s: 0,
    };
    for (final r in active) {
      final s = tenantPaymentStatus(r);
      payCounts[s] = payCounts[s]! + 1;
    }
    final filtered = residents
        .where((r) => matchesTenantFilters(
              r,
              stay: _filter,
              payment: _payment,
              query: _searchQuery,
            ))
        .toList();

    return ColoredBox(
      color: _H.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: _Header(
              count: allCount,
              onAdd: widget.onAdd,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: _SearchRow(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              onFilterTap: () {
                showModalBottomSheet(
                  context: context,
                  backgroundColor: _H.card,
                  shape: const RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  builder: (ctx) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          title: Text(
                            'Sort by name (A–Z)',
                            style: TextStyle(color: _H.textPrimary),
                          ),
                          onTap: () => Navigator.pop(ctx),
                        ),
                        ListTile(
                          title: Text(
                            'Sort by room',
                            style: TextStyle(color: _H.textPrimary),
                          ),
                          onTap: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          _FilterChips(
            allCount: allCount,
            activeCount: activeCount,
            checkedOutCount: checkedOutCount,
            selected: _filter,
            onSelected: (f) => setState(() {
              _filter = f;
              if (f != HostelGuestFilter.active) {
                _payment = TenantPaymentFilter.all;
              }
            }),
          ),
          if (_filter == HostelGuestFilter.active) ...[
            const SizedBox(height: 8),
            _PaymentChips(
              allCount: activeCount,
              paidCount: payCounts[TenantPaymentStatus.paid]!,
              dueCount: payCounts[TenantPaymentStatus.due]!,
              overdueCount: payCounts[TenantPaymentStatus.overdue]!,
              selected: _payment,
              onSelected: (p) => setState(() => _payment = p),
            ),
          ],
          const SizedBox(height: 10),
          Expanded(
            child: filtered.isEmpty
                ? _EmptyState(onAdd: widget.onAdd)
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final r = filtered[i];
                      return _TenantCard(
                        resident: r,
                        onTap: () => widget.onOpen(r),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final int count;
  final VoidCallback onAdd;

  const _Header({required this.count, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tenants',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: _H.textPrimary,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$count Tenants',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _H.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Material(
          color: _H.purpleBright,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onAdd,
            borderRadius: BorderRadius.circular(12),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 18, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    'Add Tenant',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchRow extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onFilterTap;

  const _SearchRow({
    required this.controller,
    required this.onChanged,
    required this.onFilterTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            style: TextStyle(color: _H.textPrimary, fontSize: 14),
            cursorColor: _H.purple,
            decoration: InputDecoration(
              hintText: 'Search by name, room, phone...',
              hintStyle: TextStyle(
                color: _H.textSecondary.withValues(alpha: 0.85),
                fontSize: 13,
              ),
              prefixIcon: Icon(
                Icons.search,
                color: _H.textSecondary,
                size: 20,
              ),
              filled: true,
              fillColor: _H.field,
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: _H.purple, width: 1.2),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Material(
          color: _H.field,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onFilterTap,
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 48,
              height: 48,
              child: Icon(Icons.tune_rounded, color: _H.textSecondary, size: 20),
            ),
          ),
        ),
      ],
    );
  }
}

class _PaymentChips extends StatelessWidget {
  final int allCount;
  final int paidCount;
  final int dueCount;
  final int overdueCount;
  final TenantPaymentFilter selected;
  final ValueChanged<TenantPaymentFilter> onSelected;

  const _PaymentChips({
    required this.allCount,
    required this.paidCount,
    required this.dueCount,
    required this.overdueCount,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      (TenantPaymentFilter.all, 'All payments ($allCount)'),
      (TenantPaymentFilter.paid, 'Paid ($paidCount)'),
      (TenantPaymentFilter.due, 'Due ($dueCount)'),
      (TenantPaymentFilter.overdue, 'Overdue ($overdueCount)'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _Chip(
              label: items[i].$2,
              selected: selected == items[i].$1,
              compact: true,
              onTap: () => onSelected(items[i].$1),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  final int allCount;
  final int activeCount;
  final int checkedOutCount;
  final HostelGuestFilter selected;
  final ValueChanged<HostelGuestFilter> onSelected;

  const _FilterChips({
    required this.allCount,
    required this.activeCount,
    required this.checkedOutCount,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _Chip(
            label: 'All ($allCount)',
            selected: selected == HostelGuestFilter.all,
            onTap: () => onSelected(HostelGuestFilter.all),
          ),
          const SizedBox(width: 8),
          _Chip(
            label: 'Active ($activeCount)',
            selected: selected == HostelGuestFilter.active,
            onTap: () => onSelected(HostelGuestFilter.active),
          ),
          const SizedBox(width: 8),
          _Chip(
            label: 'Checked-out ($checkedOutCount)',
            selected: selected == HostelGuestFilter.checkedOut,
            onTap: () => onSelected(HostelGuestFilter.checkedOut),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _H.purple : _H.card,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? _H.purple : themed(const Color(0xFF243044), const Color(0xFFE5E7EB)),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 14,
            vertical: compact ? 6 : 8,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: compact ? 12 : 13,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : _H.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _TenantCard extends StatelessWidget {
  final Map<String, dynamic> resident;
  final VoidCallback onTap;

  const _TenantCard({required this.resident, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = resident['full_name']?.toString() ?? '';
    final phone = _formatPhone(resident['phone']?.toString() ?? '');
    final location = _roomLine(resident);
    final status = _resolvePill(resident);
    final initial = _firstInitial(name);

    return Material(
      color: _H.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF3B82F6), themed(const Color(0xFF8B5CF6), const Color(0xFF7C3AED))],
                  ),
                ),
                child: Text(
                  initial,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? '—' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _H.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: _H.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      phone,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: _H.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusPill(status: status),
              PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_vert,
                  color: _H.textSecondary,
                  size: 20,
                ),
                color: _H.cardElevated,
                onSelected: (v) {
                  if (v == 'view') onTap();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'view',
                    child: Text(
                      'View profile',
                      style: TextStyle(color: _H.textPrimary),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _PillKind { paid, due, overdue, draft, notBilled, checkedOut, other }

class _StatusPill extends StatelessWidget {
  final _PillKind status;

  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    late Color bg;
    late Color fg;
    late String label;

    switch (status) {
      case _PillKind.paid:
        bg = _H.greenBg;
        fg = _H.green;
        label = 'Paid';
      case _PillKind.due:
        bg = _H.orangeBg;
        fg = _H.orange;
        label = 'Due';
      case _PillKind.overdue:
        bg = _H.redBg;
        fg = _H.red;
        label = 'Overdue';
      case _PillKind.draft:
        bg = _H.slateBg;
        fg = _H.slate;
        label = 'Draft';
      case _PillKind.notBilled:
        bg = _H.slateBg;
        fg = _H.slate;
        label = 'Not billed';
      case _PillKind.checkedOut:
        bg = _H.slateBg;
        fg = _H.slate;
        label = 'Out';
      case _PillKind.other:
        bg = _H.slateBg;
        fg = _H.slate;
        label = 'Pending';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.people_outline,
              size: 48,
              color: _H.textSecondary.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 12),
            Text(
              'No tenants found',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _H.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try adjusting your search or filters.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _H.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: onAdd,
              style: TextButton.styleFrom(
                foregroundColor: _H.purple,
              ),
              child: const Text('+ Add Tenant'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Checked-out tenants always show Out, whatever they still owe.
/// Active tenants show their payment status.
_PillKind _resolvePill(Map<String, dynamic> r) {
  if (isCheckedOutTenancy(r)) return _PillKind.checkedOut;
  if (!isActiveTenancy(r)) return _PillKind.other;
  switch (tenantPaymentStatus(r)) {
    case TenantPaymentStatus.paid:
      return _PillKind.paid;
    case TenantPaymentStatus.due:
      return _PillKind.due;
    case TenantPaymentStatus.overdue:
      return _PillKind.overdue;
    case TenantPaymentStatus.draft:
      return _PillKind.draft;
    case TenantPaymentStatus.notBilled:
      return _PillKind.notBilled;
  }
}

String _firstInitial(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '?';
  return trimmed[0].toUpperCase();
}

String _formatPhone(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 10) {
    return '+91 ${digits.substring(0, 5)} ${digits.substring(5)}';
  }
  if (digits.length == 12 && digits.startsWith('91')) {
    final local = digits.substring(2);
    return '+91 ${local.substring(0, 5)} ${local.substring(5)}';
  }
  return raw.isEmpty ? '—' : raw;
}

String _roomLine(Map<String, dynamic> r) {
  final room = (r['node_name'] ?? r['nodeName'])?.toString().trim() ?? '';
  final floor = (r['floor_name'] ?? r['floorName'])?.toString().trim() ?? '';
  final level = (r['level_name'] ?? r['levelName'])?.toString().trim() ?? '';

  final roomPart = room.isEmpty
      ? '—'
      : (room.toLowerCase().contains('room') ? room : 'Room $room');

  if (r['status']?.toString() == 'ended') {
    final leftRaw = r['move_out_at'] ?? r['moveOutAt'] ?? r['updated_at'];
    final left = _formatShortDate(leftRaw);
    if (left != null) return 'Stayed in $roomPart • Left $left';
    return 'Stayed in $roomPart';
  }

  String block = floor;
  if (block.isEmpty && level.isNotEmpty) block = level;
  if (block.isEmpty) return roomPart;
  final blockLabel =
      block.toLowerCase().contains('block') || block.toLowerCase().contains('floor')
          ? block
          : block;
  return '$roomPart - $blockLabel';
}

String? _formatShortDate(dynamic raw) {
  if (raw == null || raw.toString().trim().isEmpty) return null;
  final parsed = DateTime.tryParse(raw.toString());
  if (parsed == null) return null;
  return DateFormat('d MMM yyyy').format(parsed.toLocal());
}
