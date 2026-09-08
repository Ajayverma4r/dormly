// features/tenancies/presentation/residents_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/tenancy_repository.dart';
import '../../../core/theme/app_theme.dart';
import 'add_tenant_screen.dart';
import 'node_detail_screen.dart';

enum _GuestStatusFilter { all, active, due, checkedOut }

const _pageSize = 10;
const _accent = AppColors.blueprint;

final propertyResidentsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>(
  (ref, propertyId) =>
      ref.watch(tenancyRepositoryProvider).listByProperty(propertyId),
);

class ResidentsListScreen extends ConsumerStatefulWidget {
  final String propertyId;
  final String label;

  const ResidentsListScreen({
    super.key,
    required this.propertyId,
    required this.label,
  });

  @override
  ConsumerState<ResidentsListScreen> createState() =>
      _ResidentsListScreenState();
}

class _ResidentsListScreenState extends ConsumerState<ResidentsListScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  _GuestStatusFilter _filter = _GuestStatusFilter.all;
  int _currentPage = 1;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String get _addButtonLabel {
    final label = widget.label;
    if (label.endsWith('s') && label.length > 1) {
      return 'Add ${label.substring(0, label.length - 1)}';
    }
    return 'Add $label';
  }

  Future<void> _openAddGuest() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddTenantScreen(propertyId: widget.propertyId),
      ),
    );
    ref.invalidate(propertyResidentsProvider(widget.propertyId));
  }

  Future<void> _openGuestDetail(Map<String, dynamic> r) async {
    final nodeId = (r['node_id'] ?? r['nodeId'])?.toString() ?? '';
    if (nodeId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This tenant is not linked to a unit. Re-assign them from Rooms.',
          ),
        ),
      );
      return;
    }
    final nodeName =
        (r['node_name'] ?? r['nodeName'])?.toString() ?? 'Unit';
    final levelName =
        (r['level_name'] ?? r['levelName'])?.toString() ?? 'Room';

    await Navigator.of(context).push(
      NodeDetailScreen.route(
        propertyId: widget.propertyId,
        nodeId: nodeId,
        nodeName: nodeName,
        levelName: levelName,
      ),
    );
    ref.invalidate(propertyResidentsProvider(widget.propertyId));
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

  List<Map<String, dynamic>> _applyFilters(
      List<Map<String, dynamic>> residents) {
    final q = _searchQuery.trim().toLowerCase();
    return residents.where((r) {
      switch (_filter) {
        case _GuestStatusFilter.active:
          if (!_isActive(r) || _hasDue(r)) return false;
        case _GuestStatusFilter.due:
          if (!_isActive(r) || !_hasDue(r)) return false;
        case _GuestStatusFilter.checkedOut:
          if (!_isCheckedOut(r)) return false;
        case _GuestStatusFilter.all:
          break;
      }
      if (q.isEmpty) return true;
      final name = (r['full_name'] ?? '').toString().toLowerCase();
      final room = (r['node_name'] ?? '').toString().toLowerCase();
      final phone = (r['phone'] ?? '').toString().toLowerCase();
      return name.contains(q) || room.contains(q) || phone.contains(q);
    }).toList();
  }

  void _setFilter(_GuestStatusFilter filter, int totalPages) {
    setState(() {
      _filter = filter;
      _currentPage = 1;
    });
  }

  void _setPage(int page, int totalPages) {
    setState(() => _currentPage = page.clamp(1, totalPages));
  }

  @override
  Widget build(BuildContext context) {
    final residentsAsync =
        ref.watch(propertyResidentsProvider(widget.propertyId));
    final baseUrl = ref.watch(tenancyRepositoryProvider).baseUrl;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: residentsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('Something went wrong: $err')),
          data: (residents) {
            final allCount = residents.length;
            final activeCount = residents
                .where((r) => _isActive(r) && !_hasDue(r))
                .length;
            final dueCount =
                residents.where((r) => _isActive(r) && _hasDue(r)).length;
            final checkedOutCount =
                residents.where((r) => _isCheckedOut(r)).length;

            final filtered = _applyFilters(residents);
            final totalPages =
                (filtered.length / _pageSize).ceil().clamp(1, 999999);
            final safePage = _currentPage.clamp(1, totalPages);
            if (safePage != _currentPage) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _currentPage = safePage);
              });
            }
            final start = (safePage - 1) * _pageSize;
            final end = (start + _pageSize).clamp(0, filtered.length);
            final pageItems = filtered.sublist(
              start,
              end,
            );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: _HeaderRow(
                    title: widget.label,
                    subtitle: '$allCount ${widget.label}',
                    addLabel: _addButtonLabel,
                    onAdd: _openAddGuest,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: _SearchFilterRow(
                    controller: _searchController,
                    onChanged: (v) => setState(() {
                      _searchQuery = v;
                      _currentPage = 1;
                    }),
                    onFilterTap: () {
                      showModalBottomSheet(
                        context: context,
                        builder: (ctx) => SafeArea(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(
                                title: const Text('Sort by name (A–Z)'),
                                onTap: () => Navigator.pop(ctx),
                              ),
                              ListTile(
                                title: const Text('Sort by room'),
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
                _StatusFilterPills(
                  allCount: allCount,
                  activeCount: activeCount,
                  dueCount: dueCount,
                  checkedOutCount: checkedOutCount,
                  selected: _filter,
                  onSelected: (f) => _setFilter(f, totalPages),
                ),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: _TableHeaderRow(),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? _EmptyState(label: widget.label, onAdd: _openAddGuest)
                      : ListView.separated(
                          padding: const EdgeInsets.only(top: 4),
                          itemCount: pageItems.length,
                          separatorBuilder: (_, __) => const Divider(
                            height: 1,
                            thickness: 1,
                            color: AppColors.hairline,
                            indent: 12,
                            endIndent: 12,
                          ),
                          itemBuilder: (context, i) {
                            final r = pageItems[i];
                            return _GuestListRow(
                              resident: r,
                              baseUrl: baseUrl,
                              onTap: () => _openGuestDetail(r),
                            );
                          },
                        ),
                ),
                if (filtered.isNotEmpty)
                  _PaginationFooter(
                    start: start + 1,
                    end: end,
                    total: filtered.length,
                    currentPage: safePage,
                    totalPages: totalPages,
                    onPageSelected: (p) => _setPage(p, totalPages),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final String addLabel;
  final VoidCallback onAdd;

  const _HeaderRow({
    required this.title,
    required this.subtitle,
    required this.addLabel,
    required this.onAdd,
  });

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
                title,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          onPressed: onAdd,
          style: ElevatedButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          icon: const Icon(Icons.add, size: 18),
          label: Text(
            addLabel,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

class _SearchFilterRow extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onFilterTap;

  const _SearchFilterRow({
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
            decoration: InputDecoration(
              hintText: 'Search by name, room, phone...',
              hintStyle: TextStyle(color: AppColors.slate.withValues(alpha: 0.8)),
              prefixIcon: const Icon(Icons.search, color: AppColors.slate, size: 20),
              filled: true,
              fillColor: AppColors.canvas,
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.hairline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _accent, width: 1.2),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Material(
          color: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: AppColors.hairline),
          ),
          child: InkWell(
            onTap: onFilterTap,
            borderRadius: BorderRadius.circular(10),
            child: const SizedBox(
              width: 48,
              height: 48,
              child: Icon(Icons.tune, color: AppColors.slate, size: 20),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusFilterPills extends StatelessWidget {
  final int allCount;
  final int activeCount;
  final int dueCount;
  final int checkedOutCount;
  final _GuestStatusFilter selected;
  final ValueChanged<_GuestStatusFilter> onSelected;

  const _StatusFilterPills({
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
          _FilterPill(
            label: 'All ($allCount)',
            selected: selected == _GuestStatusFilter.all,
            onTap: () => onSelected(_GuestStatusFilter.all),
          ),
          const SizedBox(width: 8),
          _FilterPill(
            label: 'Active ($activeCount)',
            dotColor: AppColors.positive,
            selected: selected == _GuestStatusFilter.active,
            onTap: () => onSelected(_GuestStatusFilter.active),
          ),
          const SizedBox(width: 8),
          _FilterPill(
            label: 'Due ($dueCount)',
            dotColor: AppColors.caution,
            selected: selected == _GuestStatusFilter.due,
            onTap: () => onSelected(_GuestStatusFilter.due),
          ),
          const SizedBox(width: 8),
          _FilterPill(
            label: 'Checked-out ($checkedOutCount)',
            dotColor: AppColors.slate,
            selected: selected == _GuestStatusFilter.checkedOut,
            onTap: () => onSelected(_GuestStatusFilter.checkedOut),
          ),
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final Color? dotColor;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.dotColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _accent : AppColors.surface,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? _accent : AppColors.hairline,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dotColor != null && !selected) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TableHeaderRow extends StatelessWidget {
  const _TableHeaderRow();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 12,
      color: AppColors.slate,
      fontWeight: FontWeight.w500,
    );
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text('Guest', style: style)),
          Expanded(flex: 2, child: Text('Room', style: style)),
          Expanded(flex: 3, child: Text('Floor', style: style)),
          Expanded(flex: 3, child: Text('Status', style: style)),
        ],
      ),
    );
  }
}

class _GuestListRow extends StatelessWidget {
  final Map<String, dynamic> resident;
  final String baseUrl;
  final VoidCallback onTap;

  const _GuestListRow({
    required this.resident,
    required this.baseUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = resident['full_name']?.toString() ?? '';
    final phone = _formatPhone(resident['phone']?.toString() ?? '');
    final room = resident['node_name']?.toString() ?? '—';
    final floor = _formatFloor(
      resident['floor_name'] ?? resident['floorName'],
    );
    final status = _resolveDisplayStatus(resident);
    final photoUrl = _photoUrl(resident, baseUrl);
    final initials = _initials(name);

    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.canvas,
                      backgroundImage:
                          photoUrl != null ? NetworkImage(photoUrl) : null,
                      child: photoUrl == null
                          ? Text(
                              initials,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _accent,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            phone,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Row(
                  children: [
                    const Icon(Icons.door_front_door_outlined,
                        size: 13, color: _accent),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(
                        room,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  floor,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 12,
                      ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: _StatusBadge(status: status),
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: AppColors.slate,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final _GuestDisplayStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    late Color bg;
    late Color fg;
    late String label;
    late Color dot;

    switch (status) {
      case _GuestDisplayStatus.active:
        bg = AppColors.positive.withValues(alpha: 0.12);
        fg = AppColors.positive;
        dot = AppColors.positive;
        label = 'Active';
      case _GuestDisplayStatus.due:
        bg = AppColors.caution.withValues(alpha: 0.12);
        fg = AppColors.caution;
        dot = AppColors.caution;
        label = 'Due';
      case _GuestDisplayStatus.checkedOut:
        bg = AppColors.slate.withValues(alpha: 0.12);
        fg = AppColors.slate;
        dot = AppColors.slate;
        label = 'Out';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _GuestDisplayStatus { active, due, checkedOut }

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

String? _photoUrl(Map<String, dynamic> r, String baseUrl) {
  final raw = r['profile_photo_url'] ?? r['profilePhotoUrl'];
  if (raw == null || raw.toString().trim().isEmpty) return null;
  final s = raw.toString();
  if (s.startsWith('http')) return s;
  return '$baseUrl$s';
}

String _initials(String name) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    return parts.first.substring(0, 1).toUpperCase();
  }
  return '${parts.first[0]}${parts[1][0]}'.toUpperCase();
}

String _formatPhone(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 10) return '+91 $digits';
  if (digits.length == 12 && digits.startsWith('91')) {
    return '+${digits.substring(0, 2)} ${digits.substring(2)}';
  }
  return raw.isEmpty ? '—' : raw;
}

String _formatFloor(dynamic raw) {
  if (raw == null || raw.toString().trim().isEmpty) return '—';
  final name = raw.toString().trim();
  if (name.toLowerCase().contains('floor')) return name;
  return '$name Floor';
}

class _PaginationFooter extends StatelessWidget {
  final int start;
  final int end;
  final int total;
  final int currentPage;
  final int totalPages;
  final ValueChanged<int> onPageSelected;

  const _PaginationFooter({
    required this.start,
    required this.end,
    required this.total,
    required this.currentPage,
    required this.totalPages,
    required this.onPageSelected,
  });

  @override
  Widget build(BuildContext context) {
    final pages = _visiblePages(currentPage, totalPages);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.hairline)),
        color: AppColors.surface,
      ),
      child: Row(
        children: [
          Text(
            'Showing $start–$end of $total',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12),
          ),
          const Spacer(),
          _PageButton(
            icon: Icons.chevron_left,
            enabled: currentPage > 1,
            onTap: () => onPageSelected(currentPage - 1),
          ),
          ...pages.map(
            (p) => Padding(
              padding: const EdgeInsets.only(left: 6),
              child: _PageButton(
                label: '$p',
                selected: p == currentPage,
                onTap: () => onPageSelected(p),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: _PageButton(
              icon: Icons.chevron_right,
              enabled: currentPage < totalPages,
              onTap: () => onPageSelected(currentPage + 1),
            ),
          ),
        ],
      ),
    );
  }

  List<int> _visiblePages(int current, int total) {
    if (total <= 3) {
      return List.generate(total, (i) => i + 1);
    }
    if (current <= 2) return [1, 2, 3];
    if (current >= total - 1) return [total - 2, total - 1, total];
    return [current - 1, current, current + 1];
  }
}

class _PageButton extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _PageButton({
    this.label,
    this.icon,
    this.selected = false,
    this.enabled = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(
          color: selected ? _accent : AppColors.hairline,
        ),
      ),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 32,
          height: 32,
          child: Center(
            child: icon != null
                ? Icon(
                    icon,
                    size: 18,
                    color: enabled ? AppColors.slate : AppColors.hairline,
                  )
                : Text(
                    label ?? '',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected ? _accent : AppColors.ink,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String label;
  final VoidCallback onAdd;

  const _EmptyState({required this.label, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.people_outline, size: 48, color: AppColors.slate),
            const SizedBox(height: 12),
            Text(
              'No $label found',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Try adjusting your search or filters.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onAdd, child: Text('Add $label')),
          ],
        ),
      ),
    );
  }
}
