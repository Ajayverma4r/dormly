// features/staff_home/presentation/staff_tenants_screen.dart
//
// Limited resident list for staff: name, room/bed and status only. The
// server already strips phone, KYC, rent and dues from staff responses.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../properties/domain/property_archetype.dart';
import 'staff_ui.dart';

String staffTenantName(Map<String, dynamic> t) {
  for (final key in ['full_name', 'user_name', 'name']) {
    final v = t[key]?.toString().trim() ?? '';
    if (v.isNotEmpty) return v;
  }
  return 'Resident';
}

String staffTenantPlace(Map<String, dynamic> t) => [
      t['floor_name']?.toString().trim() ?? '',
      t['node_name']?.toString().trim() ?? '',
    ].where((s) => s.isNotEmpty).join(' · ');

bool _isCurrent(Map<String, dynamic> t) {
  final s = t['status']?.toString().toLowerCase() ?? '';
  return s == 'active' || s == 'pending';
}

class StaffTenantsScreen extends ConsumerStatefulWidget {
  final String propertyId;
  const StaffTenantsScreen({super.key, required this.propertyId});

  @override
  ConsumerState<StaffTenantsScreen> createState() => _StaffTenantsScreenState();
}

class _StaffTenantsScreenState extends ConsumerState<StaffTenantsScreen> {
  String _query = '';
  bool _currentOnly = true;

  Future<void> _refresh() async {
    await ref
        .refresh(staffTenanciesProvider(widget.propertyId).future)
        .then<void>((_) {}, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    final label = staffPropertyArchetype(ref, widget.propertyId)?.peopleLabel ??
        'Tenants';
    final async = ref.watch(staffTenanciesProvider(widget.propertyId));

    return Scaffold(
      backgroundColor: StaffColors.bg,
      appBar: StaffAppBar(title: label, subtitle: 'Limited view'),
      body: RefreshIndicator(
        color: StaffColors.brand,
        onRefresh: _refresh,
        child: async.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: StaffColors.brand)),
          error: (e, _) => StaffScrollableMessage(
            child: StaffErrorState(
              key: const Key('staff-tenants-error'),
              error: e,
              fallback: "Couldn't load residents. Please try again.",
              onRetry: () =>
                  ref.invalidate(staffTenanciesProvider(widget.propertyId)),
            ),
          ),
          data: (all) {
            if (all.isEmpty) {
              return const StaffScrollableMessage(
                child: StaffMessage(
                  key: Key('staff-tenants-empty'),
                  icon: Icons.groups_outlined,
                  title: 'No residents yet',
                  subtitle:
                      'Residents appear here once the owner or manager moves them in.',
                ),
              );
            }
            final q = _query.trim().toLowerCase();
            final visible = all.where((t) {
              if (_currentOnly && !_isCurrent(t)) return false;
              if (q.isEmpty) return true;
              return staffTenantName(t).toLowerCase().contains(q) ||
                  staffTenantPlace(t).toLowerCase().contains(q);
            }).toList()
              ..sort((a, b) => staffTenantName(a)
                  .toLowerCase()
                  .compareTo(staffTenantName(b).toLowerCase()));

            return ListView(
              key: const Key('staff-tenants-list'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                TextField(
                  key: const Key('staff-tenants-search'),
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Search by name or room',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: StaffColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: StaffColors.border),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (final current in [true, false]) ...[
                      ChoiceChip(
                        label: Text(current ? 'Current' : 'All'),
                        selected: _currentOnly == current,
                        onSelected: (_) =>
                            setState(() => _currentOnly = current),
                        selectedColor: StaffColors.brand,
                        backgroundColor: Colors.white,
                        showCheckmark: false,
                        side: BorderSide(
                          color: _currentOnly == current
                              ? StaffColors.brand
                              : StaffColors.border,
                        ),
                        labelStyle: TextStyle(
                          color: _currentOnly == current
                              ? Colors.white
                              : StaffColors.ink,
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                if (visible.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: StaffMessage(
                        icon: Icons.search_off_rounded,
                        title: 'No residents match'),
                  )
                else
                  Container(
                    decoration: staffCardDecoration(),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (var i = 0; i < visible.length; i++) ...[
                          if (i > 0)
                            const Divider(
                                height: 1,
                                color: StaffColors.border,
                                indent: 64),
                          _TenantRow(tenancy: visible[i]),
                        ],
                      ],
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

class _TenantRow extends StatelessWidget {
  final Map<String, dynamic> tenancy;
  const _TenantRow({required this.tenancy});

  @override
  Widget build(BuildContext context) {
    final name = staffTenantName(tenancy);
    final place = staffTenantPlace(tenancy);
    final status = tenancy['status']?.toString().toLowerCase() ?? '';
    final (label, fg, bg) = switch (status) {
      'active' => ('Active', StaffColors.success, StaffColors.successSoft),
      'pending' => ('Moving in', StaffColors.warning, StaffColors.warningSoft),
      'ended' => ('Moved out', StaffColors.muted, const Color(0xFFF1F5F9)),
      _ => (
          status.isEmpty
              ? 'Unknown'
              : status[0].toUpperCase() +
                  status.substring(1).replaceAll('_', ' '),
          StaffColors.muted,
          const Color(0xFFF1F5F9),
        ),
    };

    return Padding(
      key: Key('staff-tenant-${tenancy['id']}'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: StaffColors.brandSoft,
            child: Text(
              initialOf(name),
              style: const TextStyle(
                  color: StaffColors.brand, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: StaffColors.ink, fontWeight: FontWeight.w700),
                ),
                if (place.isNotEmpty)
                  Text(
                    place,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(color: StaffColors.muted, fontSize: 12),
                  ),
              ],
            ),
          ),
          StaffPill(label: label, fg: fg, bg: bg),
        ],
      ),
    );
  }
}
