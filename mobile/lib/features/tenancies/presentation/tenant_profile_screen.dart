// features/tenancies/presentation/tenant_profile_screen.dart
//
// Tenant Details — card + tab layout matching the product mock:
// Overview / Personal / KYC / Payments / Complaints.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../billing/data/billing_repository.dart';
import '../../billing/presentation/tenant_ledger_sheet.dart';
import '../../billing/presentation/whatsapp_reminder.dart';
import '../../complaints/data/complaints_repository.dart';
import '../../complaints/presentation/complaints_list_screen.dart';
import '../../properties/domain/property_archetype.dart';
import '../../structure/presentation/property_shell_screen.dart'
    show propertyDetailProvider;
import '../data/tenancy_repository.dart';
import 'add_tenant_screen.dart';
import 'checkout_settlement_sheet.dart';
import 'tenancy_providers.dart';
import 'tenant_profile_section.dart'
    show
        KycEditSheet,
        PersonalInfoEditSheet,
        TenantProfilePhotoViewerScreen,
        tenancyDocumentsProvider,
        tenantField;

final _currency =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _dateFmt = DateFormat('d MMM yyyy');

final tenancyProfileProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, (String propertyId, String tenancyId)>(
  (ref, args) async {
    return ref.watch(tenancyRepositoryProvider).getById(args.$1, args.$2);
  },
);

typedef TenancyLedgerTotals = ({
  double billed,
  double paid,
  double outstanding,
  DateTime? nextDue,
});

final tenancyLedgerSummaryProvider = FutureProvider.autoDispose
    .family<TenancyLedgerTotals, (String, String)>(
  (ref, args) async {
    final invoices =
        await ref.watch(billingRepositoryProvider).listInvoices(args.$1);
    var billed = 0.0;
    var paid = 0.0;
    DateTime? nextDue;
    for (final inv in invoices) {
      final tid = (inv['tenancy_id'] ?? inv['tenancyId'])?.toString() ?? '';
      if (tid != args.$2) continue;
      final total = double.tryParse(
            inv['total_amount']?.toString() ??
                inv['totalAmount']?.toString() ??
                '',
          ) ??
          0;
      final paidAmt = double.tryParse(
            inv['paid_amount']?.toString() ??
                inv['paidAmount']?.toString() ??
                '',
          ) ??
          0;
      billed += total;
      paid += paidAmt;
      final dueLeft = total - paidAmt;
      if (dueLeft <= 0.009) continue;
      final dueRaw = inv['due_date'] ??
          inv['dueDate'] ??
          inv['period_end'] ??
          inv['periodEnd'];
      final due = DateTime.tryParse(dueRaw?.toString() ?? '');
      if (due == null) continue;
      if (nextDue == null || due.isBefore(nextDue)) nextDue = due;
    }
    return (
      billed: billed,
      paid: paid,
      outstanding: (billed - paid).clamp(0.0, 1e12).toDouble(),
      nextDue: nextDue,
    );
  },
);

final tenantNodeComplaintsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, (String propertyId, String nodeId)>(
  (ref, args) async {
    if (args.$2.isEmpty) return const [];
    final all =
        await ref.watch(complaintsRepositoryProvider).listForProperty(args.$1);
    return all
        .where((c) {
          final nid = (c['node_id'] ?? c['nodeId'])?.toString() ?? '';
          return nid == args.$2;
        })
        .toList(growable: false);
  },
);

enum _TenantTab { overview, personal, kyc, payments, complaints }

class TenantProfileScreen extends ConsumerStatefulWidget {
  final String propertyId;
  final String tenancyId;
  final Map<String, dynamic>? initialTenancy;

  /// When true, opens the dues / ledger sheet once profile data is ready.
  final bool openDuesSheet;

  const TenantProfileScreen({
    super.key,
    required this.propertyId,
    required this.tenancyId,
    this.initialTenancy,
    this.openDuesSheet = false,
  });

  static Route<void> route({
    required String propertyId,
    required String tenancyId,
    Map<String, dynamic>? initialTenancy,
    bool openDuesSheet = false,
  }) {
    return MaterialPageRoute(
      settings: const RouteSettings(name: 'tenant-profile'),
      builder: (_) => TenantProfileScreen(
        propertyId: propertyId,
        tenancyId: tenancyId,
        initialTenancy: initialTenancy,
        openDuesSheet: openDuesSheet,
      ),
    );
  }

  @override
  ConsumerState<TenantProfileScreen> createState() =>
      _TenantProfileScreenState();
}

class _TenantProfileScreenState extends ConsumerState<TenantProfileScreen> {
  bool _duesSheetOpened = false;

  void _maybeOpenDues(Map<String, dynamic> tenancy) {
    if (!widget.openDuesSheet || _duesSheetOpened) return;
    _duesSheetOpened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _ProfileBody.openLedgerStatic(
        context: context,
        ref: ref,
        propertyId: widget.propertyId,
        tenancy: tenancy,
        onRefresh: _refresh,
      );
    });
  }

  Future<void> _openSettlement(Map<String, dynamic> tenancy) async {
    final done = await showCheckoutSettlementSheet(
      context: context,
      ref: ref,
      propertyId: widget.propertyId,
      tenancy: tenancy,
      isEmergencyExit: _ProfileBody.isEmergencyRequest(tenancy),
    );
    if (done) await _refresh();
  }

  List<Widget>? _appBarActions(Map<String, dynamic> tenancy) {
    final ended = tenancy['status']?.toString() == 'ended';
    if (ended) return null;
    return [
      PopupMenuButton<String>(
        tooltip: 'More',
        onSelected: (value) {
          if (value == 'checkout') _openSettlement(tenancy);
        },
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: 'checkout',
            child: Text('Initiate Move-Out / Settlement'),
          ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(
      tenancyProfileProvider((widget.propertyId, widget.tenancyId)),
    );

    return async.when(
      loading: () {
        if (widget.initialTenancy != null) {
          _maybeOpenDues(widget.initialTenancy!);
        }
        final t = widget.initialTenancy;
        return Scaffold(
          backgroundColor: AppColors.canvas,
          appBar: AppBar(
            title: const Text('Tenant Details'),
            backgroundColor: AppColors.surface,
            actions: t != null ? _appBarActions(t) : null,
          ),
          body: t != null
              ? _ProfileBody(
                  propertyId: widget.propertyId,
                  tenancy: t,
                  onRefresh: _refresh,
                  onCheckout: () => _openSettlement(t),
                )
              : const Center(child: CircularProgressIndicator()),
        );
      },
      error: (e, _) {
        if (widget.initialTenancy != null) {
          _maybeOpenDues(widget.initialTenancy!);
        }
        final t = widget.initialTenancy;
        return Scaffold(
          backgroundColor: AppColors.canvas,
          appBar: AppBar(
            title: const Text('Tenant Details'),
            backgroundColor: AppColors.surface,
            actions: t != null ? _appBarActions(t) : null,
          ),
          body: t != null
              ? _ProfileBody(
                  propertyId: widget.propertyId,
                  tenancy: t,
                  onRefresh: _refresh,
                  onCheckout: () => _openSettlement(t),
                )
              : Center(child: Text('Could not load profile: $e')),
        );
      },
      data: (tenancy) {
        _maybeOpenDues(tenancy);
        return Scaffold(
          backgroundColor: AppColors.canvas,
          appBar: AppBar(
            title: const Text('Tenant Details'),
            backgroundColor: AppColors.surface,
            actions: _appBarActions(tenancy),
          ),
          body: _ProfileBody(
            propertyId: widget.propertyId,
            tenancy: tenancy,
            onRefresh: _refresh,
            onCheckout: () => _openSettlement(tenancy),
          ),
        );
      },
    );
  }

  Future<void> _refresh() async {
    ref.invalidate(
      tenancyProfileProvider((widget.propertyId, widget.tenancyId)),
    );
    ref.invalidate(
      tenancyLedgerSummaryProvider((widget.propertyId, widget.tenancyId)),
    );
    ref.invalidate(
      tenancyDocumentsProvider((widget.propertyId, widget.tenancyId)),
    );
    ref.invalidate(propertyResidentsProvider(widget.propertyId));
    final tenancy = ref
            .read(
              tenancyProfileProvider((widget.propertyId, widget.tenancyId)),
            )
            .asData
            ?.value ??
        widget.initialTenancy;
    final nodeId =
        (tenancy?['node_id'] ?? tenancy?['nodeId'])?.toString() ?? '';
    if (nodeId.isNotEmpty) {
      ref.invalidate(
        tenantNodeComplaintsProvider((widget.propertyId, nodeId)),
      );
    }
  }
}

class _ProfileBody extends ConsumerStatefulWidget {
  final String propertyId;
  final Map<String, dynamic> tenancy;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onCheckout;

  const _ProfileBody({
    required this.propertyId,
    required this.tenancy,
    required this.onRefresh,
    required this.onCheckout,
  });

  static bool isEmergencyRequest(Map<String, dynamic> t) {
    return t['move_out_is_emergency'] == true ||
        t['move_out_is_emergency']?.toString() == 'true';
  }

  static bool _hasMoveOutRequest(Map<String, dynamic> t) {
    final status = t['move_out_request_status']?.toString();
    if (status != null && status.isNotEmpty && status != 'rejected') {
      return true;
    }
    final notice = t['notice_given_at'] ?? t['noticeGivenAt'];
    return notice != null && notice.toString().trim().isNotEmpty;
  }

  static Future<void> openLedgerStatic({
    required BuildContext context,
    required WidgetRef ref,
    required String propertyId,
    required Map<String, dynamic> tenancy,
    required Future<void> Function() onRefresh,
  }) async {
    final tenancyId = tenancy['id']?.toString() ?? '';
    if (tenancyId.isEmpty) return;
    final property =
        ref.read(propertyDetailProvider(propertyId)).asData?.value;
    final isRentalHouse = property != null &&
        propertyArchetypeFromProperty(property) ==
            PropertyArchetype.individualLease;
    final spaceFallback = isRentalHouse ? 'Space' : 'Room';
    List<Map<String, dynamic>> invoices = const [];
    try {
      invoices =
          await ref.read(billingRepositoryProvider).listInvoices(propertyId);
    } catch (_) {}
    if (!context.mounted) return;
    await showTenantLedgerSheet(
      context: context,
      ref: ref,
      propertyId: propertyId,
      tenancyId: tenancyId,
      tenantName: tenancy['full_name']?.toString() ?? 'Tenant',
      roomLabel: (tenancy['node_name'] ?? tenancy['nodeName'])?.toString() ??
          spaceFallback,
      phone: tenancy['phone']?.toString(),
      allInvoices: invoices,
    );
    await onRefresh();
  }

  @override
  ConsumerState<_ProfileBody> createState() => _ProfileBodyState();
}

class _ProfileBodyState extends ConsumerState<_ProfileBody> {
  _TenantTab _tab = _TenantTab.overview;

  String get _propertyId => widget.propertyId;
  Map<String, dynamic> get tenancy => widget.tenancy;
  String get _tenancyId => tenancy['id']?.toString() ?? '';
  String get _nodeId =>
      (tenancy['node_id'] ?? tenancy['nodeId'])?.toString() ?? '';
  bool get _isEnded => tenancy['status']?.toString() == 'ended';

  Future<void> _openLedger() => _ProfileBody.openLedgerStatic(
        context: context,
        ref: ref,
        propertyId: _propertyId,
        tenancy: tenancy,
        onRefresh: widget.onRefresh,
      );

  Future<void> _openPersonalEdit() async {
    if (_nodeId.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => PersonalInfoEditSheet(
        propertyId: _propertyId,
        nodeId: _nodeId,
        tenancyId: _tenancyId,
        tenant: tenancy,
      ),
    );
    await widget.onRefresh();
  }

  Future<void> _openKycEdit() async {
    if (_nodeId.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => KycEditSheet(
        propertyId: _propertyId,
        nodeId: _nodeId,
        tenancyId: _tenancyId,
        tenant: tenancy,
      ),
    );
    await widget.onRefresh();
  }

  Future<void> _openStayEdit() async {
    final rentCtrl = TextEditingController(
      text: _amountText(tenancy['monthly_rent'] ?? tenancy['monthlyRent']),
    );
    final depositCtrl = TextEditingController(
      text: _amountText(
        tenancy['security_deposit'] ?? tenancy['securityDeposit'],
      ),
    );
    DateTime? moveIn = DateTime.tryParse(
      (tenancy['move_in_at'] ?? tenancy['moveInAt'])?.toString() ?? '',
    )?.toLocal();

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Edit stay details',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: rentCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Rent amount / month',
                      prefixText: '₹ ',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: depositCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Security deposit',
                      prefixText: '₹ ',
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Move-in date'),
                    subtitle: Text(
                      moveIn == null ? 'Not set' : _dateFmt.format(moveIn!),
                    ),
                    trailing: const Icon(Icons.calendar_today_outlined),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: moveIn ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) setSheet(() => moveIn = picked);
                    },
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Save'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (saved != true) return;
    try {
      await ref.read(tenancyRepositoryProvider).update(
            _propertyId,
            _tenancyId,
            nodeId: _nodeId.isEmpty ? null : _nodeId,
            monthlyRent: double.tryParse(rentCtrl.text.trim()),
            securityDeposit: double.tryParse(depositCtrl.text.trim()),
            moveInAt: moveIn?.toIso8601String(),
          );
      await widget.onRefresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Stay details updated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  Future<void> _raiseComplaint() async {
    if (_nodeId.isEmpty) return;
    final categoryCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Raise New Complaint'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: categoryCtrl,
              decoration: const InputDecoration(labelText: 'Category'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(labelText: 'Description'),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final category = categoryCtrl.text.trim();
    final description = descCtrl.text.trim();
    if (category.isEmpty || description.isEmpty) return;
    try {
      await ref.read(complaintsRepositoryProvider).createForProperty(
            _propertyId,
            nodeId: _nodeId,
            category: category,
            description: description,
          );
      ref.invalidate(tenantNodeComplaintsProvider((_propertyId, _nodeId)));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Complaint submitted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  Future<void> _confirmRemove() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Tenant'),
        content: const Text(
          'This starts check-out and final settlement for this tenant. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (go == true) await widget.onCheckout();
  }

  Future<void> _reAdmit() async {
    await openAddTenantFlow(
      context: context,
      ref: ref,
      propertyId: _propertyId,
      prefill: TenantPrefill.fromTenancy(tenancy),
    );
    await widget.onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    final baseUrl = ref.watch(tenancyRepositoryProvider).baseUrl;
    final totalsAsync =
        ref.watch(tenancyLedgerSummaryProvider((_propertyId, _tenancyId)));
    final docsAsync =
        ref.watch(tenancyDocumentsProvider((_propertyId, _tenancyId)));
    final complaintsAsync =
        ref.watch(tenantNodeComplaintsProvider((_propertyId, _nodeId)));
    final property =
        ref.watch(propertyDetailProvider(_propertyId)).asData?.value;
    final isRentalHouse = property != null &&
        propertyArchetypeFromProperty(property) ==
            PropertyArchetype.individualLease;

    final name = tenancy['full_name']?.toString() ?? '—';
    final phone = tenancy['phone']?.toString() ?? '—';
    final email = tenantField(tenancy, ['email']);
    final space =
        (tenancy['node_name'] ?? tenancy['nodeName'])?.toString() ?? '—';
    final moveInRaw = tenancy['move_in_at'] ?? tenancy['moveInAt'];
    final moveOutRaw = tenancy['move_out_at'] ?? tenancy['moveOutAt'];
    final moveInDt = DateTime.tryParse(moveInRaw?.toString() ?? '')?.toLocal();
    final moveOutDt =
        DateTime.tryParse(moveOutRaw?.toString() ?? '')?.toLocal();
    final moveIn = moveInDt == null ? null : _dateFmt.format(moveInDt);
    final moveOut = moveOutDt == null ? null : _dateFmt.format(moveOutDt);
    final rent = _amount(tenancy['monthly_rent'] ?? tenancy['monthlyRent']);
    final deposit =
        _amount(tenancy['security_deposit'] ?? tenancy['securityDeposit']);
    final photoUrl = _photoUrl(tenancy, baseUrl);
    final hasMoveOut = _ProfileBody._hasMoveOutRequest(tenancy);
    final spaceLabel = isRentalHouse ? 'Space' : 'Room';

    final outstandingPreview = totalsAsync.asData?.value.outstanding;
    final showDue = !_isEnded &&
        (outstandingPreview != null
            ? outstandingPreview > 0.009
            : _flagDue(tenancy));

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _ProfileHeader(
            name: name,
            phone: phone,
            email: email,
            photoUrl: photoUrl,
            isEnded: _isEnded,
            showDue: showDue,
            subtitle: '$spaceLabel $space · Since ${moveIn ?? '—'}',
            propertyId: _propertyId,
            nodeId: _nodeId,
            tenancyId: _tenancyId,
            baseUrl: baseUrl,
            onPhotoChanged: widget.onRefresh,
          ),
          const SizedBox(height: 14),
          _TabChips(
            selected: _tab,
            onSelected: (t) => setState(() => _tab = t),
          ),
          if (!_isEnded && hasMoveOut && _tab == _TenantTab.overview) ...[
            const SizedBox(height: 14),
            _MoveOutRequestCard(
              tenancy: tenancy,
              propertyId: _propertyId,
              onRefresh: widget.onRefresh,
            ),
          ],
          const SizedBox(height: 14),
          if (_tab == _TenantTab.overview || _tab == _TenantTab.payments) ...[
            if (_tab == _TenantTab.overview) ...[
              _StayDetailsCard(
                isRentalHouse: isRentalHouse,
                space: space,
                moveIn: moveIn,
                moveOut: moveOut,
                isEnded: _isEnded,
                duration: _stayDuration(moveInDt, moveOutDt),
                rent: rent,
                deposit: deposit,
                onEdit: _isEnded ? null : _openStayEdit,
              ),
              const SizedBox(height: 12),
            ],
            _RentPaymentsCard(
              totalsAsync: totalsAsync,
              deposit: deposit,
              phone: phone,
              name: name,
              isEnded: _isEnded,
              onViewHistory: _openLedger,
              onRecordPayment: _openLedger,
            ),
            if (_tab == _TenantTab.overview) const SizedBox(height: 12),
          ],
          if (_tab == _TenantTab.overview || _tab == _TenantTab.kyc) ...[
            _KycStatusCard(
              tenancy: tenancy,
              docsAsync: docsAsync,
              onUpload: _isEnded || _nodeId.isEmpty ? null : _openKycEdit,
            ),
            if (_tab == _TenantTab.overview) const SizedBox(height: 12),
          ],
          if (_tab == _TenantTab.overview || _tab == _TenantTab.personal) ...[
            _PersonalInfoCard(
              tenancy: tenancy,
              onEdit: _isEnded || _nodeId.isEmpty ? null : _openPersonalEdit,
            ),
            if (_tab == _TenantTab.overview) const SizedBox(height: 12),
          ],
          if (_tab == _TenantTab.overview || _tab == _TenantTab.complaints) ...[
            _ComplaintsCard(
              complaintsAsync: complaintsAsync,
              onViewAll: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ComplaintsListScreen(propertyId: _propertyId),
                  ),
                );
              },
              onRaise: _isEnded || _nodeId.isEmpty ? null : _raiseComplaint,
              onRetry: () => ref.invalidate(
                tenantNodeComplaintsProvider((_propertyId, _nodeId)),
              ),
            ),
          ],
          const SizedBox(height: 20),
          if (!_isEnded)
            SizedBox(
              height: 50,
              child: OutlinedButton.icon(
                onPressed: _confirmRemove,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  backgroundColor: AppColors.danger.withValues(alpha: 0.06),
                  side: BorderSide(
                    color: AppColors.danger.withValues(alpha: 0.25),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.delete_outline),
                label: const Text(
                  'Remove Tenant',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            )
          else
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: _reAdmit,
                icon: Icon(
                  isRentalHouse
                      ? Icons.home_work_outlined
                      : Icons.meeting_room_outlined,
                ),
                label: Text(
                  isRentalHouse
                      ? 'Re-Admit / Assign New Space'
                      : 'Re-Admit / Assign New Room',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static bool _flagDue(Map<String, dynamic> t) {
    final raw = t['has_due'] ?? t['hasDue'];
    if (raw is bool) return raw;
    return raw?.toString().toLowerCase() == 'true';
  }

  static double _amount(dynamic raw) =>
      double.tryParse(raw?.toString() ?? '') ?? 0;

  static String _amountText(dynamic raw) {
    final v = _amount(raw);
    if (v == 0 && (raw == null || raw.toString().trim().isEmpty)) return '';
    return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
  }

  static String? _photoUrl(Map<String, dynamic> r, String baseUrl) {
    final raw = r['profile_photo_url'] ?? r['profilePhotoUrl'];
    if (raw == null || raw.toString().trim().isEmpty) return null;
    final s = raw.toString();
    if (s.startsWith('http')) return s;
    return '$baseUrl$s';
  }

  static String _stayDuration(DateTime? moveIn, DateTime? moveOut) {
    if (moveIn == null) return '—';
    final end = moveOut ?? DateTime.now();
    var months =
        (end.year - moveIn.year) * 12 + end.month - moveIn.month;
    var days = end.day - moveIn.day;
    if (days < 0) {
      months -= 1;
      final prev = DateTime(end.year, end.month, 0);
      days += prev.day;
    }
    if (months < 0) return '—';
    if (months == 0) return '$days day${days == 1 ? '' : 's'}';
    return '$months month${months == 1 ? '' : 's'} $days day${days == 1 ? '' : 's'}';
  }
}

// ─── Header ───────────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  final String name;
  final String phone;
  final String? email;
  final String? photoUrl;
  final bool isEnded;
  final bool showDue;
  final String subtitle;
  final String propertyId;
  final String nodeId;
  final String tenancyId;
  final String baseUrl;
  final Future<void> Function() onPhotoChanged;

  const _ProfileHeader({
    required this.name,
    required this.phone,
    required this.email,
    required this.photoUrl,
    required this.isEnded,
    required this.showDue,
    required this.subtitle,
    required this.propertyId,
    required this.nodeId,
    required this.tenancyId,
    required this.baseUrl,
    required this.onPhotoChanged,
  });

  Future<void> _launch(Uri uri) async {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openPhoto(BuildContext context) async {
    if (nodeId.isEmpty || tenancyId.isEmpty) return;
    final initials = name.isNotEmpty ? name[0].toUpperCase() : '?';
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => TenantProfilePhotoViewerScreen(
          propertyId: propertyId,
          nodeId: nodeId,
          tenancyId: tenancyId,
          baseUrl: baseUrl,
          tenantName: name,
          initials: initials,
          photoUrl: photoUrl,
        ),
      ),
    );
    await onPhotoChanged();
  }

  @override
  Widget build(BuildContext context) {
    final statusLabel = isEnded ? 'Checked Out' : (showDue ? 'Due' : 'Current');
    final statusColor = isEnded
        ? AppColors.slate
        : (showDue ? AppColors.caution : AppColors.positive);
    final canEditPhoto = nodeId.isNotEmpty && tenancyId.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: canEditPhoto ? () => _openPhoto(context) : null,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: AppColors.primarySoft,
                  backgroundImage:
                      photoUrl != null ? NetworkImage(photoUrl!) : null,
                  child: photoUrl == null
                      ? Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primaryDark,
                          ),
                        )
                      : null,
                ),
                if (canEditPhoto)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        size: 13,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(phone, style: const TextStyle(color: AppColors.slate)),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: AppColors.slate),
                ),
              ],
            ),
          ),
          Column(
            children: [
              _QuickAction(
                icon: Icons.phone_outlined,
                onTap: phone == '—'
                    ? null
                    : () => _launch(Uri(scheme: 'tel', path: phone)),
              ),
              const SizedBox(height: 8),
              _QuickAction(
                icon: Icons.chat_bubble_outline,
                onTap: phone == '—'
                    ? null
                    : () => _launch(Uri(scheme: 'sms', path: phone)),
              ),
              const SizedBox(height: 8),
              _QuickAction(
                icon: Icons.email_outlined,
                onTap: email == null || email!.isEmpty
                    ? null
                    : () => _launch(Uri(scheme: 'mailto', path: email)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _QuickAction({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primarySoft,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(
            icon,
            size: 18,
            color: onTap == null
                ? AppColors.slate.withValues(alpha: 0.4)
                : AppColors.primary,
          ),
        ),
      ),
    );
  }
}

// ─── Tabs ─────────────────────────────────────────────────────────────────

class _TabChips extends StatelessWidget {
  final _TenantTab selected;
  final ValueChanged<_TenantTab> onSelected;

  const _TabChips({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    const tabs = [
      (_TenantTab.overview, 'Overview'),
      (_TenantTab.personal, 'Personal'),
      (_TenantTab.kyc, 'KYC'),
      (_TenantTab.payments, 'Payments'),
      (_TenantTab.complaints, 'Complaints'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (tab, label) in tabs) ...[
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(label),
                selected: selected == tab,
                onSelected: (_) => onSelected(tab),
                selectedColor: AppColors.primary,
                labelStyle: TextStyle(
                  color: selected == tab ? Colors.white : AppColors.ink,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                backgroundColor: AppColors.surface,
                side: BorderSide(
                  color: selected == tab
                      ? AppColors.primary
                      : AppColors.hairline,
                ),
                showCheckmark: false,
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Cards ────────────────────────────────────────────────────────────────

BoxDecoration get _cardDecoration => BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.hairline),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    );

class _CardShell extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing;
  final Widget child;

  const _CardShell({
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

Widget _kv(String label, String value, {Color? valueColor, Widget? valueWidget}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: const TextStyle(color: AppColors.slate, fontSize: 13),
          ),
        ),
        Expanded(
          flex: 3,
          child: valueWidget ??
              Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: valueColor ?? AppColors.ink,
                ),
              ),
        ),
      ],
    ),
  );
}

class _StayDetailsCard extends StatelessWidget {
  final bool isRentalHouse;
  final String space;
  final String? moveIn;
  final String? moveOut;
  final bool isEnded;
  final String duration;
  final double rent;
  final double deposit;
  final VoidCallback? onEdit;

  const _StayDetailsCard({
    required this.isRentalHouse,
    required this.space,
    required this.moveIn,
    required this.moveOut,
    required this.isEnded,
    required this.duration,
    required this.rent,
    required this.deposit,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      icon: Icons.home_work_outlined,
      title: 'Stay Details',
      trailing: onEdit == null
          ? null
          : TextButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Edit'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
      child: Column(
        children: [
          _kv(isRentalHouse ? 'Space' : 'Room / unit', space),
          _kv('Move-in date', moveIn ?? '—'),
          _kv(
            'Move-out date',
            isEnded ? (moveOut ?? '—') : '— (still residing)',
          ),
          _kv('Stay duration', duration),
          _kv(
            'Rent amount',
            rent > 0 ? '${_currency.format(rent)} / month' : '—',
          ),
          _kv(
            'Security deposit',
            deposit > 0 ? _currency.format(deposit) : '—',
          ),
          _kv(
            'Status',
            '',
            valueWidget: Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: (isEnded ? AppColors.slate : AppColors.positive)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isEnded ? 'Checked Out' : 'Current',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isEnded ? AppColors.slate : AppColors.positive,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RentPaymentsCard extends StatelessWidget {
  final AsyncValue<TenancyLedgerTotals> totalsAsync;
  final double deposit;
  final String phone;
  final String name;
  final bool isEnded;
  final VoidCallback onViewHistory;
  final VoidCallback onRecordPayment;

  const _RentPaymentsCard({
    required this.totalsAsync,
    required this.deposit,
    required this.phone,
    required this.name,
    required this.isEnded,
    required this.onViewHistory,
    required this.onRecordPayment,
  });

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      icon: Icons.account_balance_wallet_outlined,
      title: 'Rent & Payments',
      trailing: TextButton(
        onPressed: onViewHistory,
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: const Text(
          'View history',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),
      child: totalsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Text('Could not load totals: $e'),
        data: (t) {
          final outstanding = t.outstanding;
          return Column(
            children: [
              _kv('Total rent billed', _currency.format(t.billed)),
              _kv('Total rent paid', _currency.format(t.paid)),
              _kv(
                'Outstanding dues',
                _currency.format(outstanding),
                valueColor: outstanding > 0 ? AppColors.caution : null,
              ),
              _kv(
                'Security deposit',
                deposit > 0 ? _currency.format(deposit) : '—',
              ),
              _kv(
                'Next due date',
                t.nextDue == null ? '—' : _dateFmt.format(t.nextDue!),
              ),
              if (!isEnded) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 46,
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: onRecordPayment,
                    icon: const Icon(
                      Icons.account_balance_wallet_outlined,
                      size: 18,
                    ),
                    label: const Text(
                      'Record Payment',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 46,
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: outstanding <= 0.009
                        ? null
                        : () => sendWhatsAppReminder(
                              context,
                              phone: phone,
                              name: name,
                              amount: outstanding,
                            ),
                    icon: const Icon(Icons.send_outlined, size: 18),
                    label: const Text(
                      'Send Reminder',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _KycStatusCard extends StatelessWidget {
  final Map<String, dynamic> tenancy;
  final AsyncValue<List<Map<String, dynamic>>> docsAsync;
  final VoidCallback? onUpload;

  const _KycStatusCard({
    required this.tenancy,
    required this.docsAsync,
    required this.onUpload,
  });

  bool _hasType(List<Map<String, dynamic>> docs, Set<String> types) {
    for (final d in docs) {
      final t =
          (d['doc_type'] ?? d['docType'])?.toString().toLowerCase() ?? '';
      if (types.contains(t)) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final kyc = (tenancy['kyc_status'] ?? tenancy['kycStatus'])
            ?.toString()
            .toLowerCase() ??
        'pending';
    final pending = kyc != 'verified' && kyc != 'approved';
    final hasPhotoField =
        (tenancy['profile_photo_url'] ?? tenancy['profilePhotoUrl'])
                ?.toString()
                .trim()
                .isNotEmpty ==
            true;
    final hasAadhaarNum =
        (tenancy['aadhaar_number'] ?? tenancy['aadhaarNumber'])
                ?.toString()
                .trim()
                .isNotEmpty ==
            true;

    return _CardShell(
      icon: Icons.verified_user_outlined,
      title: 'KYC Status',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: (pending ? AppColors.caution : AppColors.positive)
              .withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          pending ? 'Pending' : 'Verified',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: pending ? AppColors.caution : AppColors.positive,
          ),
        ),
      ),
      child: docsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (_, __) => const Text('Could not load documents.'),
        data: (docs) {
          final idOk = hasAadhaarNum ||
              _hasType(docs, {'aadhaar', 'pan', 'id', 'other'});
          final addressOk = _hasType(docs, {'address_proof', 'address'});
          final photoOk = hasPhotoField || _hasType(docs, {'photo'});
          return Column(
            children: [
              _DocStatusRow(
                label: 'Aadhaar / PAN Card',
                uploaded: idOk,
              ),
              _DocStatusRow(
                label: 'Address Proof',
                uploaded: addressOk,
                cautionIfMissing: true,
              ),
              _DocStatusRow(
                label: 'Photo',
                uploaded: photoOk,
              ),
              if (onUpload != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 46,
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onUpload,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.upload_outlined, size: 18),
                    label: const Text(
                      'Upload Documents',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _DocStatusRow extends StatelessWidget {
  final String label;
  final bool uploaded;
  final bool cautionIfMissing;

  const _DocStatusRow({
    required this.label,
    required this.uploaded,
    this.cautionIfMissing = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = uploaded
        ? AppColors.positive
        : (cautionIfMissing ? AppColors.caution : AppColors.danger);
    final text = uploaded ? 'Uploaded' : 'Not uploaded';
    final icon = uploaded ? Icons.check_circle : Icons.error_outline;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: AppColors.slate),
            ),
          ),
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonalInfoCard extends StatelessWidget {
  final Map<String, dynamic> tenancy;
  final VoidCallback? onEdit;

  const _PersonalInfoCard({
    required this.tenancy,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final name = tenancy['full_name']?.toString() ?? '—';
    final phone = tenancy['phone']?.toString() ?? '—';
    final email = tenantField(tenancy, ['email']) ?? '—';
    final address = tenantField(tenancy, ['address']) ?? '—';
    final ecName = tenantField(tenancy, [
      'emergency_contact_name',
      'emergencyContactName',
    ]);
    final ecPhone = tenantField(tenancy, [
      'emergency_contact_phone',
      'emergencyContactPhone',
    ]);
    final emergency = [
      if (ecName != null) ecName,
      if (ecPhone != null) ecPhone,
    ].join(' · ');

    return _CardShell(
      icon: Icons.person_outline,
      title: 'Personal Information',
      trailing: onEdit == null
          ? null
          : IconButton(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 18),
              color: AppColors.primary,
              visualDensity: VisualDensity.compact,
            ),
      child: Column(
        children: [
          _kv('Full name', name),
          _kv('Phone number', phone),
          _kv('Email', email),
          _kv('Date of birth', '—'),
          _kv('Gender', '—'),
          _kv(
            'Emergency contact',
            emergency.isEmpty ? '—' : emergency,
          ),
          _kv('Address', address),
        ],
      ),
    );
  }
}

class _ComplaintsCard extends StatelessWidget {
  final AsyncValue<List<Map<String, dynamic>>> complaintsAsync;
  final VoidCallback onViewAll;
  final VoidCallback? onRaise;
  final VoidCallback onRetry;

  const _ComplaintsCard({
    required this.complaintsAsync,
    required this.onViewAll,
    required this.onRaise,
    required this.onRetry,
  });

  String _status(Map<String, dynamic> c) =>
      (c['status']?.toString() ?? 'open').toLowerCase();

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      icon: Icons.build_outlined,
      title: 'Complaints',
      trailing: TextButton(
        onPressed: onViewAll,
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: const Text(
          'View all',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),
      child: complaintsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (_, __) => Column(
          children: [
            const Text('Could not load complaints'),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
        data: (list) {
          final open = list.where((c) {
            final s = _status(c);
            return s == 'open' || s == 'pending';
          }).length;
          final progress = list.where((c) {
            final s = _status(c);
            return s == 'in_progress' || s == 'assigned';
          }).length;
          final resolved = list.where((c) {
            final s = _status(c);
            return s == 'resolved' || s == 'closed';
          }).length;

          return Column(
            children: [
              _kv('Total complaints', '${list.length}'),
              _kv('Open', '$open', valueColor: AppColors.danger),
              _kv(
                'In progress',
                '$progress',
                valueColor: const Color(0xFF2563EB),
              ),
              _kv('Resolved', '$resolved', valueColor: AppColors.positive),
              if (onRaise != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 46,
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onRaise,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primarySoft,
                      foregroundColor: AppColors.primaryDark,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text(
                      'Raise New Complaint',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

// ─── Move-out (existing flow) ─────────────────────────────────────────────

class _MoveOutRequestCard extends ConsumerWidget {
  final Map<String, dynamic> tenancy;
  final String propertyId;
  final Future<void> Function() onRefresh;

  const _MoveOutRequestCard({
    required this.tenancy,
    required this.propertyId,
    required this.onRefresh,
  });

  String get _tenancyId => tenancy['id']?.toString() ?? '';

  bool get _isEmergency =>
      tenancy['move_out_is_emergency'] == true ||
      tenancy['move_out_is_emergency']?.toString() == 'true';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestedAt = tenancy['notice_given_at'] ?? tenancy['noticeGivenAt'];
    final proposed =
        tenancy['planned_move_out_at'] ?? tenancy['plannedMoveOutAt'];
    final status =
        tenancy['move_out_request_status']?.toString() ?? 'pending';
    final reqLabel = requestedAt == null
        ? '—'
        : DateFormat('d MMM yyyy, h:mm a')
            .format(DateTime.parse(requestedAt.toString()).toLocal());
    final propLabel = proposed == null
        ? '—'
        : DateFormat('d MMM yyyy')
            .format(DateTime.parse(proposed.toString()).toLocal());

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _isEmergency
            ? AppColors.caution.withValues(alpha: 0.1)
            : AppColors.primarySoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _isEmergency ? AppColors.caution : AppColors.hairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Move-Out Request',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
              if (_isEmergency)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Emergency Exit Requested',
                    style: TextStyle(
                      color: AppColors.danger,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Move-Out Request: $propLabel',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          Text(
            'Logged on: $reqLabel',
            style: const TextStyle(fontSize: 12, color: AppColors.slate),
          ),
          const SizedBox(height: 8),
          _MoveOutStatusPill(status: status),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (status == 'pending')
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.positive,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => _review(context, ref, 'approve'),
                  child: const Text('Approve Notice Date'),
                )
              else if (status == 'approved' ||
                  status == 'modified_by_mutual_agreement')
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF10B981).withValues(alpha: 0.45),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle,
                          color: Color(0xFF10B981), size: 18),
                      SizedBox(width: 6),
                      Text(
                        'Notice Approved',
                        style: TextStyle(
                          color: Color(0xFF10B981),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              if (status != 'rejected')
                OutlinedButton(
                  onPressed: () => _modifyDate(context, ref),
                  child: const Text('Modify Exit Date'),
                ),
              if (_isEmergency)
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.caution,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    final done = await showCheckoutSettlementSheet(
                      context: context,
                      ref: ref,
                      propertyId: propertyId,
                      tenancy: tenancy,
                      isEmergencyExit: true,
                    );
                    if (done) await onRefresh();
                  },
                  child: const Text('Proceed to Emergency Settlement'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _review(
    BuildContext context,
    WidgetRef ref,
    String action, {
    String? proposedExitDate,
  }) async {
    try {
      await ref.read(tenancyRepositoryProvider).reviewMoveOutRequest(
            propertyId,
            _tenancyId,
            action: action,
            proposedExitDate: proposedExitDate,
          );
      await onRefresh();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Move-out request ${action}d.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _modifyDate(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: today,
      lastDate: today.add(const Duration(days: 180)),
      helpText: 'Modify exit date (mutual agreement)',
    );
    if (picked == null) return;
    if (!context.mounted) return;
    await _review(
      context,
      ref,
      'modify',
      proposedExitDate: picked.toIso8601String(),
    );
  }
}

class _MoveOutStatusPill extends StatelessWidget {
  final String status;
  const _MoveOutStatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final normalized = status.toLowerCase();
    final isApproved = normalized == 'approved' ||
        normalized == 'modified_by_mutual_agreement';
    final label = status.replaceAll('_', ' ');

    if (isApproved) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF10B981).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFF10B981).withValues(alpha: 0.35),
          ),
        ),
        child: Text(
          'Status: $label',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: Color(0xFF10B981),
          ),
        ),
      );
    }

    if (normalized == 'rejected') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          'Status: $label',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.danger,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.caution.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'Status: $label',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFFB45309),
        ),
      ),
    );
  }
}
