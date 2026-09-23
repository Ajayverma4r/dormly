// features/structure/presentation/rental_spaces_tab_screen.dart
//
// Rental House (individualLease) Spaces tab — flat list of rentable spaces.
// Does NOT use the hostel Rooms tree or Add Room bottom sheet.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../tenancies/domain/assignable_unit.dart';
import '../../tenancies/presentation/assignable_units_provider.dart';
import '../../tenancies/presentation/create_space_screen.dart';
import '../../tenancies/presentation/rental_space_detail_screen.dart';

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
  bool _showSearch = false;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openAddSpace() async {
    if (!widget.canManage) return;
    final result = await openCreateSpaceScreen(
      context: context,
      propertyId: widget.propertyId,
    );
    if (!mounted) return;
    ref.invalidate(assignableUnitsProvider(widget.propertyId));
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
    ref.invalidate(assignableUnitsProvider(widget.propertyId));
  }

  List<AssignableUnit> _filtered(List<AssignableUnit> all) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all
        .where((u) =>
            u.pathLabel.toLowerCase().contains(q) ||
            u.nodeName.toLowerCase().contains(q) ||
            (u.tenantName?.toLowerCase().contains(q) ?? false))
        .toList();
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
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('Spaces'),
        actions: [
          IconButton(
            tooltip: 'Search',
            onPressed: () => setState(() {
              _showSearch = !_showSearch;
              if (!_showSearch) {
                _searchController.clear();
                _query = '';
              }
            }),
            icon: Icon(_showSearch ? Icons.search_off : Icons.search),
          ),
          if (widget.canManage)
            IconButton(
              tooltip: 'Add Space',
              onPressed: _openAddSpace,
              icon: const Icon(Icons.add),
            ),
        ],
      ),
      floatingActionButton: widget.canManage
          ? FloatingActionButton.extended(
              onPressed: _openAddSpace,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Add Space'),
            )
          : null,
      body: spacesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load spaces: $e')),
        data: (all) {
          final spaces = _filtered(all);
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(assignableUnitsProvider(widget.propertyId));
              await ref.read(
                assignableUnitsProvider(widget.propertyId).future,
              );
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: Text(
                      'Manage the spaces you rent out',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                ),
                if (_showSearch)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        onChanged: (v) => setState(() => _query = v),
                        decoration: InputDecoration(
                          hintText: 'Search spaces',
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: AppColors.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: AppColors.hairline),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (all.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(
                      canManage: widget.canManage,
                      onAdd: _openAddSpace,
                    ),
                  )
                else if (spaces.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        'No spaces match your search.',
                        style: TextStyle(color: AppColors.slate),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      4,
                      20,
                      widget.canManage ? 100 : 24,
                    ),
                    sliver: SliverList.separated(
                      itemCount: spaces.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
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
              ],
            ),
          );
        },
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.home_work_outlined,
              size: 36,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'No spaces added yet',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Add your first rental space to get started.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: AppColors.slate,
            ),
          ),
          if (canManage) ...[
            const SizedBox(height: 24),
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: onAdd,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.add),
                label: const Text(
                  '+ Add Rental Space',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ],
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
    final statusColor =
        occupied ? const Color(0xFFB45309) : const Color(0xFF1F9D55);
    final statusText = occupied
        ? (space.tenantName != null && space.tenantName!.isNotEmpty
            ? 'Occupied · ${space.tenantName}'
            : 'Occupied')
        : 'Vacant';

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.hairline),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.home_work_outlined,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      space.pathLabel,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      rentLabel,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.slate,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.slate),
            ],
          ),
        ),
      ),
    );
  }
}
