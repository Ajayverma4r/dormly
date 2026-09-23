// features/tenancies/presentation/rental_space_detail_screen.dart
//
// Rental House space profile — product UI, not the generic hierarchy node screen.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../billing/data/billing_repository.dart';
import '../../structure/data/structure_repository.dart';
import '../../structure/domain/hierarchy_level.dart';
import '../../structure/presentation/dynamic_dashboard/dynamic_dashboard_screen.dart'
    show hierarchyLevelsProvider;
import '../data/tenancy_repository.dart';
import '../domain/assignable_unit.dart';
import 'add_tenant_screen.dart';
import 'assignable_units_provider.dart';
import 'tenant_profile_screen.dart';

final _currency =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _dayFmt = DateFormat('dd MMM');

class _SpaceDetailData {
  final AssignableUnit space;
  final String? spaceTypeLabel;
  final String? floorLabel;
  final Map<String, dynamic>? activeTenancy;
  final DateTime? nextRentDue;

  const _SpaceDetailData({
    required this.space,
    this.spaceTypeLabel,
    this.floorLabel,
    this.activeTenancy,
    this.nextRentDue,
  });
}

final rentalSpaceDetailProvider = FutureProvider.autoDispose
    .family<_SpaceDetailData, (String propertyId, String nodeId)>(
  (ref, args) async {
    final propertyId = args.$1;
    final nodeId = args.$2;
    final units = await ref.watch(assignableUnitsProvider(propertyId).future);
    final space = units.where((u) => u.nodeId == nodeId).firstOrNull;
    if (space == null) {
      throw Exception('Space not found.');
    }

    final structureRepo = ref.watch(structureRepositoryProvider);
    final tenancyRepo = ref.watch(tenancyRepositoryProvider);
    final levels = await ref.watch(hierarchyLevelsProvider(propertyId).future);

    final tenancies = await tenancyRepo.listByNode(propertyId, nodeId);
    Map<String, dynamic>? active;
    for (final t in tenancies) {
      if (t['status']?.toString() == 'active') {
        active = t;
        break;
      }
    }

    String? spaceTypeLabel;
    String? floorLabel;
    double? rent = space.monthlyRent;
    double? deposit = space.securityDeposit;

    // Enrich from raw node + parent floor name.
    final unitLevel = _pickUnitLevel(levels);
    if (unitLevel != null) {
      final node = await _findNodeDeep(
        structureRepo,
        propertyId,
        unitLevel,
        levels,
        nodeId,
      );
      if (node != null) {
        final type = (node['spaceType'] ??
                node['space_type'] ??
                (node['metadata'] is Map
                    ? node['metadata']['space_type']
                    : null))
            ?.toString();
        spaceTypeLabel = _labelForSpaceType(type);
        rent ??= _readAmount(node, const ['monthlyRent', 'monthly_rent']);
        deposit ??=
            _readAmount(node, const ['securityDeposit', 'security_deposit']);

        final parentId =
            (node['parentNodeId'] ?? node['parent_node_id'])?.toString();
        if (parentId != null && parentId.isNotEmpty) {
          final parent = await _findNodeDeep(
            structureRepo,
            propertyId,
            unitLevel,
            levels,
            parentId,
          );
          if (parent != null) {
            final parentType = (parent['spaceType'] ??
                    parent['space_type'] ??
                    (parent['metadata'] is Map
                        ? parent['metadata']['space_type']
                        : null))
                ?.toString();
            if (parentType == 'floor' ||
                RegExp(r'floor|ground|roof', caseSensitive: false)
                    .hasMatch(parent['name']?.toString() ?? '')) {
              floorLabel = parent['name']?.toString();
            }
          }
        }
      }
    }

    DateTime? nextDue;
    if (active != null) {
      final tenancyId = active['id']?.toString();
      if (tenancyId != null) {
        final invoices =
            await ref.watch(billingRepositoryProvider).listInvoices(propertyId);
        DateTime? earliest;
        for (final inv in invoices) {
          final tid =
              (inv['tenancy_id'] ?? inv['tenancyId'])?.toString() ?? '';
          if (tid != tenancyId) continue;
          final status = (inv['status'] ?? '').toString().toLowerCase();
          if (status == 'paid' || status == 'cancelled' || status == 'void') {
            continue;
          }
          final raw = (inv['due_date'] ?? inv['dueDate'])?.toString();
          if (raw == null || raw.isEmpty) continue;
          final d = DateTime.tryParse(raw);
          if (d == null) continue;
          if (earliest == null || d.isBefore(earliest)) earliest = d;
        }
        nextDue = earliest;
      }
    }

    final enriched = AssignableUnit(
      nodeId: space.nodeId,
      nodeName: space.nodeName,
      levelName: space.levelName,
      pathLabel: space.pathLabel,
      occupied: active != null,
      monthlyRent: rent ?? space.monthlyRent,
      securityDeposit: deposit ?? space.securityDeposit,
      tenantName: active != null
          ? (active['full_name'] ?? active['fullName'])?.toString()
          : space.tenantName,
    );

    return _SpaceDetailData(
      space: enriched,
      spaceTypeLabel: spaceTypeLabel,
      floorLabel: floorLabel,
      activeTenancy: active,
      nextRentDue: nextDue,
    );
  },
);

HierarchyLevel? _pickUnitLevel(List<HierarchyLevel> levels) {
  final enabled = levels.where((l) => l.isEnabled).toList()
    ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
  for (final key in const ['unit', 'room', 'flat']) {
    final hit = enabled.where((l) => l.internalKey == key).firstOrNull;
    if (hit != null) return hit;
  }
  return enabled.where((l) => l.supportsOccupancy).firstOrNull ??
      enabled.lastOrNull;
}

Future<Map<String, dynamic>?> _findNodeDeep(
  StructureRepository repo,
  String propertyId,
  HierarchyLevel unitLevel,
  List<HierarchyLevel> levels,
  String nodeId,
) async {
  Future<Map<String, dynamic>?> search(
    String? parentId,
  ) async {
    final nodes = await repo.listNodes(
      propertyId,
      unitLevel.id,
      parentNodeId: parentId,
    );
    for (final n in nodes) {
      if (n['id']?.toString() == nodeId) return n;
    }
    for (final n in nodes) {
      final id = n['id']?.toString();
      if (id == null) continue;
      final found = await search(id);
      if (found != null) return found;
    }
    return null;
  }

  // Roots under property shell + null parent.
  final propertyLevel =
      levels.where((l) => l.isEnabled && l.internalKey == 'property').firstOrNull;
  if (propertyLevel != null) {
    final roots = await repo.listNodes(
      propertyId,
      propertyLevel.id,
      parentNodeId: null,
    );
    for (final root in roots) {
      final rootId = root['id']?.toString();
      if (rootId == null) continue;
      final found = await search(rootId);
      if (found != null) return found;
    }
  }
  return search(null);
}

double? _readAmount(Map<String, dynamic> node, List<String> keys) {
  for (final key in keys) {
    final v = node[key];
    if (v is num) return v.toDouble();
    if (v is String) {
      final n = double.tryParse(v);
      if (n != null) return n;
    }
  }
  final meta = node['metadata'];
  if (meta is Map) {
    for (final key in keys) {
      final v = meta[key];
      if (v is num) return v.toDouble();
      if (v is String) {
        final n = double.tryParse(v);
        if (n != null) return n;
      }
    }
  }
  return null;
}

String _labelForSpaceType(String? type) {
  switch (type) {
    case 'entire_property':
      return 'Entire Property';
    case 'floor':
      return 'Full Floor';
    case 'portion':
      return 'Floor / Portion';
    case 'room':
      return 'Room';
    case 'shop':
      return 'Commercial Space';
    default:
      return 'Rental Space';
  }
}

class RentalSpaceDetailScreen extends ConsumerWidget {
  final String propertyId;
  final String nodeId;
  final bool canManage;

  const RentalSpaceDetailScreen({
    super.key,
    required this.propertyId,
    required this.nodeId,
    this.canManage = true,
  });

  static Route<void> route({
    required String propertyId,
    required String nodeId,
    bool canManage = true,
  }) {
    return MaterialPageRoute(
      settings: const RouteSettings(name: 'rental-space-detail'),
      builder: (_) => RentalSpaceDetailScreen(
        propertyId: propertyId,
        nodeId: nodeId,
        canManage: canManage,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(rentalSpaceDetailProvider((propertyId, nodeId)));

    return async.when(
      loading: () => Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: AppBar(title: const Text('Space')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: AppBar(title: const Text('Space')),
        body: Center(child: Text('$e')),
      ),
      data: (data) => _SpaceDetailBody(
        propertyId: propertyId,
        canManage: canManage,
        data: data,
      ),
    );
  }
}

class _SpaceDetailBody extends ConsumerWidget {
  final String propertyId;
  final bool canManage;
  final _SpaceDetailData data;

  const _SpaceDetailBody({
    required this.propertyId,
    required this.canManage,
    required this.data,
  });

  Future<void> _addTenant(BuildContext context, WidgetRef ref) async {
    await openAddTenantFlow(
      context: context,
      ref: ref,
      propertyId: propertyId,
      nodeId: data.space.nodeId,
    );
    ref.invalidate(rentalSpaceDetailProvider((propertyId, data.space.nodeId)));
    ref.invalidate(assignableUnitsProvider(propertyId));
  }

  Future<void> _viewTenant(BuildContext context) async {
    final t = data.activeTenancy;
    final id = t?['id']?.toString();
    if (id == null) return;
    await Navigator.of(context).push(
      TenantProfileScreen.route(
        propertyId: propertyId,
        tenancyId: id,
        initialTenancy: t,
      ),
    );
  }

  Future<void> _editSpace(BuildContext context, WidgetRef ref) async {
    final nameCtrl = TextEditingController(text: data.space.nodeName);
    final rentCtrl = TextEditingController(
      text: data.space.monthlyRent != null
          ? _formatAmount(data.space.monthlyRent!)
          : '',
    );
    final depositCtrl = TextEditingController(
      text: data.space.securityDeposit != null
          ? _formatAmount(data.space.securityDeposit!)
          : '',
    );

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Edit Space',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Space name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: rentCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Monthly rent',
                  prefixText: '₹ ',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: depositCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Security deposit',
                  prefixText: '₹ ',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Save changes'),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (saved != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    try {
      await ref.read(structureRepositoryProvider).updateNode(
            propertyId,
            data.space.nodeId,
            name: name,
            monthlyRent: double.tryParse(rentCtrl.text.trim()),
            securityDeposit: double.tryParse(depositCtrl.text.trim()),
          );
      ref.invalidate(
        rentalSpaceDetailProvider((propertyId, data.space.nodeId)),
      );
      ref.invalidate(assignableUnitsProvider(propertyId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Space updated')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update: $e')),
        );
      }
    }
  }

  Future<void> _deleteSpace(BuildContext context, WidgetRef ref) async {
    if (data.space.occupied) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Remove or reassign the tenant before deleting.'),
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete space?'),
        content: Text(
          '“${data.space.nodeName}” will be permanently removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref
          .read(structureRepositoryProvider)
          .deleteNode(propertyId, data.space.nodeId);
      ref.invalidate(assignableUnitsProvider(propertyId));
      if (context.mounted) Navigator.of(context).pop();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final space = data.space;
    final occupied = space.occupied;
    final statusColor =
        occupied ? const Color(0xFFB45309) : const Color(0xFF1F9D55);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(space.nodeName),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  space.nodeName,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 10),
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
                    const SizedBox(width: 8),
                    Text(
                      occupied ? 'Occupied' : 'Vacant',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
                if (space.monthlyRent != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    '${_currency.format(space.monthlyRent)} / month',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ],
                if (space.securityDeposit != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Security deposit ${_currency.format(space.securityDeposit)}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.slate,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Tenant',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 10),
                if (!occupied) ...[
                  const Text(
                    'No tenant assigned',
                    style: TextStyle(color: AppColors.slate),
                  ),
                  if (canManage) ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: () => _addTenant(context, ref),
                        icon: const Icon(Icons.person_add_alt_1),
                        label: const Text(
                          '+ Add Tenant',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ] else ...[
                  Text(
                    space.tenantName ?? 'Tenant',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (space.monthlyRent != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${_currency.format(space.monthlyRent)} / month',
                      style: const TextStyle(color: AppColors.slate),
                    ),
                  ],
                  if (data.nextRentDue != null) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Next Rent Due',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.slate,
                      ),
                    ),
                    Text(
                      _dayFmt.format(data.nextRentDue!),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  OutlinedButton(
                    onPressed: () => _viewTenant(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'View Tenant',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Space Details',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                _kv('Type', data.spaceTypeLabel ?? 'Rental Space'),
                if (data.floorLabel != null) ...[
                  const SizedBox(height: 8),
                  _kv('Floor', data.floorLabel!),
                ],
              ],
            ),
          ),
          if (canManage) ...[
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: () => _editSpace(context, ref),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Edit Space',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => _deleteSpace(context, ref),
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              child: const Text('Delete Space'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
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
      child: child,
    );
  }

  Widget _kv(String k, String v) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            k,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.slate,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            v,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
        ),
      ],
    );
  }
}

String _formatAmount(double value) {
  if (value == value.roundToDouble()) return value.round().toString();
  return value.toString();
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}

extension _LastOrNull<E> on List<E> {
  E? get lastOrNull => isEmpty ? null : last;
}
