// features/tenancies/presentation/hostel_pg_tenants_body.dart
// Screen 2 — Hostel / PG Tenants list (dark). Rental / apartment keep residents_list_screen.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Palette aligned with Hostel/PG dashboard (Screen 1).
class _H {
  static const bg = Color(0xFF0D1623);
  static const card = Color(0xFF151F30);
  static const cardElevated = Color(0xFF1A2438);
  static const field = Color(0xFF121C2C);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF94A3B8);
  static const purple = Color(0xFF8B5CF6);
  static const purpleBright = Color(0xFF7C3AED);
  static const green = Color(0xFF22C55E);
  static const greenBg = Color(0xFF1A3A2A);
  static const orange = Color(0xFFF2835F);
  static const orangeBg = Color(0xFF3E2A22);
  static const slate = Color(0xFF64748B);
  static const slateBg = Color(0xFF1E293B);
}

enum HostelGuestFilter { all, active, due, checkedOut }

enum _GuestDisplayStatus { active, due, checkedOut }

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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _hasDue(Map<String, dynamic> r) {
    final raw = r['has_due'] ?? r['hasDue'];
    if (raw is bool) return raw;
    return raw?.toString().toLowerCase() == 'true';
  }

  bool _isActive(Map<String, dynamic> r) =>
      r['status']?.toString() == 'active';

  bool _isCheckedOut(Map<String, dynamic> r) =>
      r['status']?.toString() == 'ended';

  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> list) {
    final q = _searchQuery.trim().toLowerCase();
    return list.where((r) {
      switch (_filter) {
        case HostelGuestFilter.active:
          if (!_isActive(r) || _hasDue(r)) return false;
        case HostelGuestFilter.due:
          if (!_isActive(r) || !_hasDue(r)) return false;
        case HostelGuestFilter.checkedOut:
          if (!_isCheckedOut(r)) return false;
        case HostelGuestFilter.all:
          break;
      }
      if (q.isEmpty) return true;
      final name = (r['full_name'] ?? '').toString().toLowerCase();
      final room = (r['node_name'] ?? '').toString().toLowerCase();
      final floor = (r['floor_name'] ?? r['floorName'] ?? '').toString().toLowerCase();
      final phone = (r['phone'] ?? '').toString().toLowerCase();
      return name.contains(q) ||
          room.contains(q) ||
          floor.contains(q) ||
          phone.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final residents = widget.residents;
    final allCount = residents.length;
    final activeCount =
        residents.where((r) => _isActive(r) && !_hasDue(r)).length;
    final dueCount =
        residents.where((r) => _isActive(r) && _hasDue(r)).length;
    final checkedOutCount = residents.where(_isCheckedOut).length;
    final filtered = _applyFilters(residents);

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
                          title: const Text(
                            'Sort by name (A–Z)',
                            style: TextStyle(color: _H.textPrimary),
                          ),
                          onTap: () => Navigator.pop(ctx),
                        ),
                        ListTile(
                          title: const Text(
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
            dueCount: dueCount,
            checkedOutCount: checkedOutCount,
            selected: _filter,
            onSelected: (f) => setState(() => _filter = f),
          ),
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
              const Text(
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
                style: const TextStyle(
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
            style: const TextStyle(color: _H.textPrimary, fontSize: 14),
            cursorColor: _H.purple,
            decoration: InputDecoration(
              hintText: 'Search by name, room, phone...',
              hintStyle: TextStyle(
                color: _H.textSecondary.withValues(alpha: 0.85),
                fontSize: 13,
              ),
              prefixIcon: const Icon(
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
                borderSide: const BorderSide(color: _H.purple, width: 1.2),
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
            child: const SizedBox(
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

class _FilterChips extends StatelessWidget {
  final int allCount;
  final int activeCount;
  final int dueCount;
  final int checkedOutCount;
  final HostelGuestFilter selected;
  final ValueChanged<HostelGuestFilter> onSelected;

  const _FilterChips({
    required this.allCount,
    required this.activeCount,
    required this.dueCount,
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
            label: 'Due ($dueCount)',
            selected: selected == HostelGuestFilter.due,
            onTap: () => onSelected(HostelGuestFilter.due),
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

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _H.purple : _H.card,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? _H.purple : const Color(0xFF243044),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
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
    final status = _resolveDisplayStatus(resident);
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
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
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
                      style: const TextStyle(
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
                      style: const TextStyle(
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
                      style: const TextStyle(
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
                icon: const Icon(
                  Icons.more_vert,
                  color: _H.textSecondary,
                  size: 20,
                ),
                color: _H.cardElevated,
                onSelected: (v) {
                  if (v == 'view') onTap();
                },
                itemBuilder: (_) => const [
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

class _StatusPill extends StatelessWidget {
  final _GuestDisplayStatus status;

  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    late Color bg;
    late Color fg;
    late String label;

    switch (status) {
      case _GuestDisplayStatus.active:
        bg = _H.greenBg;
        fg = _H.green;
        label = 'Active';
      case _GuestDisplayStatus.due:
        bg = _H.orangeBg;
        fg = _H.orange;
        label = 'Due';
      case _GuestDisplayStatus.checkedOut:
        bg = _H.slateBg;
        fg = _H.slate;
        label = 'Out';
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
            const Text(
              'No tenants found',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _H.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
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

_GuestDisplayStatus _resolveDisplayStatus(Map<String, dynamic> r) {
  if (r['status']?.toString() == 'ended') {
    return _GuestDisplayStatus.checkedOut;
  }
  final hasDue = r['has_due'] == true ||
      r['hasDue'] == true ||
      r['has_due']?.toString() == 'true';
  if (hasDue) return _GuestDisplayStatus.due;
  return _GuestDisplayStatus.active;
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
