// features/structure/presentation/rental_spaces_tab_screen.dart
//
// Rental House Spaces tab — dark Screen 4 style (Spaces labels + create-space flow).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../tenancies/domain/assignable_unit.dart';
import '../../tenancies/presentation/assignable_units_provider.dart';
import '../../tenancies/presentation/create_space_screen.dart';
import '../../tenancies/presentation/rental_space_detail_screen.dart';

class _H {
  static const bg = Color(0xFF0D1623);
  static const card = Color(0xFF151F30);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF94A3B8);
  static const purple = Color(0xFF8B5CF6);
  static const purpleBright = Color(0xFF7C3AED);
  static const green = Color(0xFF22C55E);
  static const greenBg = Color(0xFF14352A);
  static const orange = Color(0xFFF2835F);
  static const orangeBg = Color(0xFF3E2A22);
  static const border = Color(0xFF243044);
  static const iconWell = Color(0xFF1E2A40);
}

enum _SpaceFilter { all, occupied, vacant }

class RentalSpacesTabScreen extends ConsumerStatefulWidget {
  final String propertyId;
  final bool canManage;

  const RentalSpacesTabScreen({
    super.key,
    required this.propertyId,
    required this.canManage,
  });

  @override
  ConsumerState<RentalSpacesTabScreen> createState() =>
      _RentalSpacesTabScreenState();
}

class _RentalSpacesTabScreenState extends ConsumerState<RentalSpacesTabScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  _SpaceFilter _filter = _SpaceFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(assignableUnitsProvider(widget.propertyId));
    await ref.read(assignableUnitsProvider(widget.propertyId).future);
  }

  Future<void> _openAddSpace() async {
    if (!widget.canManage) return;
    final result = await openCreateSpaceScreen(
      context: context,
      propertyId: widget.propertyId,
    );
    if (!mounted) return;
    await _refresh();
    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('“${result.name}” added')),
      );
    }
  }

  Future<void> _openSpace(AssignableUnit space) async {
    await Navigator.of(context).push(
      RentalSpaceDetailScreen.route(
        propertyId: widget.propertyId,
        nodeId: space.nodeId,
        canManage: widget.canManage,
      ),
    );
    if (!mounted) return;
    await _refresh();
  }

  List<AssignableUnit> _apply(
    List<AssignableUnit> all,
  ) {
    final q = _query.trim().toLowerCase();
    return all.where((u) {
      switch (_filter) {
        case _SpaceFilter.all:
          break;
        case _SpaceFilter.occupied:
          if (!u.occupied) return false;
        case _SpaceFilter.vacant:
          if (u.occupied) return false;
      }
      if (q.isEmpty) return true;
      return u.pathLabel.toLowerCase().contains(q) ||
          u.nodeName.toLowerCase().contains(q) ||
          (u.tenantName?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final spacesAsync = ref.watch(assignableUnitsProvider(widget.propertyId));
    final currency = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    );

    return Scaffold(
      backgroundColor: _H.bg,
      body: SafeArea(
        child: spacesAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: _H.purple),
          ),
          error: (e, _) => Center(
            child: Text(
              'Could not load spaces: $e',
              style: const TextStyle(color: _H.textSecondary),
            ),
          ),
          data: (all) {
            final occupiedCount = all.where((s) => s.occupied).length;
            final vacantCount = all.length - occupiedCount;
            final spaces = _apply(all);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Spaces',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: _H.textPrimary,
                                height: 1.1,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${all.length} Spaces',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: _H.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (widget.canManage)
                        Material(
                          color: _H.purpleBright,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            onTap: _openAddSpace,
                            borderRadius: BorderRadius.circular(12),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 11,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.add, size: 18, color: Colors.white),
                                  SizedBox(width: 4),
                                  Text(
                                    'Add Space',
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
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _query = v),
                    style: const TextStyle(color: _H.textPrimary, fontSize: 14),
                    cursorColor: _H.purple,
                    decoration: InputDecoration(
                      hintText: 'Search spaces...',
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
                      fillColor: const Color(0xFF121C2C),
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
                        borderSide:
                            const BorderSide(color: _H.purple, width: 1.2),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      _Chip(
                        label: 'All (${all.length})',
                        selected: _filter == _SpaceFilter.all,
                        onTap: () =>
                            setState(() => _filter = _SpaceFilter.all),
                      ),
                      const SizedBox(width: 8),
                      _Chip(
                        label: 'Occupied ($occupiedCount)',
                        selected: _filter == _SpaceFilter.occupied,
                        onTap: () =>
                            setState(() => _filter = _SpaceFilter.occupied),
                      ),
                      const SizedBox(width: 8),
                      _Chip(
                        label: 'Vacant ($vacantCount)',
                        selected: _filter == _SpaceFilter.vacant,
                        onTap: () =>
                            setState(() => _filter = _SpaceFilter.vacant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: RefreshIndicator(
                    color: _H.purple,
                    backgroundColor: _H.card,
                    onRefresh: _refresh,
                    child: all.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height: 280,
                                child: _EmptyState(
                                  canManage: widget.canManage,
                                  onAdd: _openAddSpace,
                                ),
                              ),
                            ],
                          )
                        : spaces.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: const [
                                  SizedBox(
                                    height: 220,
                                    child: Center(
                                      child: Text(
                                        'No spaces match this filter.',
                                        style:
                                            TextStyle(color: _H.textSecondary),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding:
                                    const EdgeInsets.fromLTRB(16, 4, 16, 24),
                                itemCount: spaces.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (context, i) {
                                  final space = spaces[i];
                                  return _SpaceCard(
                                    space: space,
                                    rentLabel: space.monthlyRent != null
                                        ? '${currency.format(space.monthlyRent)} / month'
                                        : 'Rent not set',
                                    onTap: () => _openSpace(space),
                                  );
                                },
                              ),
                  ),
                ),
              ],
            );
          },
        ),
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
        side: BorderSide(color: selected ? _H.purple : _H.border),
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

class _SpaceCard extends StatelessWidget {
  final AssignableUnit space;
  final String rentLabel;
  final VoidCallback onTap;

  const _SpaceCard({
    required this.space,
    required this.rentLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final occupied = space.occupied;
    final statusBg = occupied ? _H.orangeBg : _H.greenBg;
    final statusFg = occupied ? _H.orange : _H.green;
    final statusLabel = occupied ? 'Occupied' : 'Vacant';

    return Material(
      color: _H.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _H.iconWell,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.home_work_outlined,
                  color: occupied ? _H.purple : _H.green,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      space.pathLabel,
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
                      rentLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: _H.textSecondary,
                      ),
                    ),
                    if (occupied &&
                        space.tenantName != null &&
                        space.tenantName!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        space.tenantName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: _H.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: statusFg,
                  ),
                ),
              ),
              const Icon(Icons.more_vert, color: _H.textSecondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool canManage;
  final VoidCallback onAdd;

  const _EmptyState({required this.canManage, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.home_work_outlined,
              size: 48,
              color: _H.textSecondary.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 12),
            const Text(
              'No spaces yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _H.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add your first rental space to get started.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _H.textSecondary, fontSize: 13),
            ),
            if (canManage) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: onAdd,
                style: TextButton.styleFrom(foregroundColor: _H.purple),
                child: const Text('+ Add Space'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
