// features/tenancies/presentation/tenant_profile_screen.dart
//
// Guest/tenant profile opened from the Guests list. Works for both active
// and checked-out tenancies (historical stay, ledger, KYC, settlement).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../billing/data/billing_repository.dart';
import '../../billing/presentation/tenant_ledger_sheet.dart';
import '../data/tenancy_repository.dart';
import 'add_tenant_screen.dart';
import 'checkout_settlement_sheet.dart';
import 'tenancy_providers.dart';
import 'tenant_profile_section.dart' show tenancyDocumentsProvider;

final _currency =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _dateFmt = DateFormat('d MMM yyyy');

final tenancyProfileProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, (String propertyId, String tenancyId)>(
  (ref, args) async {
    return ref.watch(tenancyRepositoryProvider).getById(args.$1, args.$2);
  },
);

final tenancyLedgerTotalsProvider = FutureProvider.autoDispose
    .family<({double billed, double paid, double outstanding}), (String, String)>(
  (ref, args) async {
    final invoices =
        await ref.watch(billingRepositoryProvider).listInvoices(args.$1);
    var billed = 0.0;
    var paid = 0.0;
    for (final inv in invoices) {
      final tid = (inv['tenancy_id'] ?? inv['tenancyId'])?.toString() ?? '';
      if (tid != args.$2) continue;
      billed += double.tryParse(
            inv['total_amount']?.toString() ??
                inv['totalAmount']?.toString() ??
                '',
          ) ??
          0;
      paid += double.tryParse(
            inv['paid_amount']?.toString() ??
                inv['paidAmount']?.toString() ??
                '',
          ) ??
          0;
    }
    return (
      billed: billed,
      paid: paid,
      outstanding: (billed - paid).clamp(0.0, 1e12).toDouble(),
    );
  },
);

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
        return Scaffold(
          appBar: AppBar(title: const Text('Guest profile')),
          body: widget.initialTenancy != null
              ? _ProfileBody(
                  propertyId: widget.propertyId,
                  tenancy: widget.initialTenancy!,
                  onRefresh: _refresh,
                )
              : const Center(child: CircularProgressIndicator()),
        );
      },
      error: (e, _) {
        if (widget.initialTenancy != null) {
          _maybeOpenDues(widget.initialTenancy!);
        }
        return Scaffold(
          appBar: AppBar(title: const Text('Guest profile')),
          body: widget.initialTenancy != null
              ? _ProfileBody(
                  propertyId: widget.propertyId,
                  tenancy: widget.initialTenancy!,
                  onRefresh: _refresh,
                )
              : Center(child: Text('Could not load profile: $e')),
        );
      },
      data: (tenancy) {
        _maybeOpenDues(tenancy);
        return Scaffold(
          backgroundColor: AppColors.canvas,
          appBar: AppBar(
            title: Text(tenancy['full_name']?.toString() ?? 'Guest profile'),
            backgroundColor: AppColors.surface,
          ),
          body: _ProfileBody(
            propertyId: widget.propertyId,
            tenancy: tenancy,
            onRefresh: _refresh,
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
      tenancyLedgerTotalsProvider((widget.propertyId, widget.tenancyId)),
    );
    ref.invalidate(
      tenancyDocumentsProvider((widget.propertyId, widget.tenancyId)),
    );
    ref.invalidate(propertyResidentsProvider(widget.propertyId));
  }
}

class _ProfileBody extends ConsumerWidget {
  final String propertyId;
  final Map<String, dynamic> tenancy;
  final Future<void> Function() onRefresh;

  const _ProfileBody({
    required this.propertyId,
    required this.tenancy,
    required this.onRefresh,
  });

  String get _tenancyId => tenancy['id']?.toString() ?? '';
  bool get _isEnded => tenancy['status']?.toString() == 'ended';
  bool get _hasDue {
    final raw = tenancy['has_due'] ?? tenancy['hasDue'];
    if (raw is bool) return raw;
    return raw?.toString().toLowerCase() == 'true';
  }

  String get _statusLabel {
    if (_isEnded) return 'Checked Out';
    if (_hasDue) return 'Due';
    return 'Active';
  }

  Color get _statusColor {
    if (_isEnded) return AppColors.slate;
    if (_hasDue) return AppColors.caution;
    return AppColors.positive;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baseUrl = ref.watch(tenancyRepositoryProvider).baseUrl;
    final totalsAsync = ref.watch(
      tenancyLedgerTotalsProvider((propertyId, _tenancyId)),
    );
    final docsAsync =
        ref.watch(tenancyDocumentsProvider((propertyId, _tenancyId)));

    final name = tenancy['full_name']?.toString() ?? '—';
    final phone = tenancy['phone']?.toString() ?? '—';
    final emergency = _emergencyContact(tenancy);
    final room =
        (tenancy['node_name'] ?? tenancy['nodeName'])?.toString() ?? '—';
    final moveIn = _fmtDate(tenancy['move_in_at'] ?? tenancy['moveInAt']);
    final moveOut = _fmtDate(tenancy['move_out_at'] ?? tenancy['moveOutAt']);
    final deposit = _amount(
      tenancy['security_deposit'] ?? tenancy['securityDeposit'],
    );
    final photoUrl = _photoUrl(tenancy, baseUrl);

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _HeaderCard(
            name: name,
            phone: phone,
            emergency: emergency,
            statusLabel: _statusLabel,
            statusColor: _statusColor,
            photoUrl: photoUrl,
          ),
          if (!_isEnded && _hasMoveOutRequest(tenancy)) ...[
            const SizedBox(height: 12),
            _MoveOutRequestCard(
              tenancy: tenancy,
              propertyId: propertyId,
              onRefresh: onRefresh,
            ),
          ],
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Stay details',
            child: Column(
              children: [
                _kv('Room', room),
                _kv('Move-in', moveIn ?? '—'),
                if (_isEnded) _kv('Move-out', moveOut ?? '—'),
                if (!_isEnded) _kv('Move-out', '— (still residing)'),
                if (_hasMoveOutRequest(tenancy)) ...[
                  _kv(
                    'Request submitted',
                    _fmtDateTime(
                          tenancy['notice_given_at'] ??
                              tenancy['noticeGivenAt'],
                        ) ??
                        '—',
                  ),
                  _kv(
                    'Proposed exit',
                    _fmtDate(
                          tenancy['planned_move_out_at'] ??
                              tenancy['plannedMoveOutAt'],
                        ) ??
                        '—',
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Financial ledger',
            trailing: TextButton(
              onPressed: () => _openLedger(context, ref),
              child: const Text('View ledger'),
            ),
            child: totalsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text('Could not load totals: $e'),
              data: (t) {
                final outstanding = t.outstanding;
                final refundEstimate = deposit - outstanding;
                return Column(
                  children: [
                    _kv('Total rent billed', _currency.format(t.billed)),
                    _kv('Total rent paid', _currency.format(t.paid)),
                    _kv(
                      'Outstanding dues',
                      _currency.format(outstanding),
                      valueColor: outstanding > 0 ? AppColors.caution : null,
                    ),
                    const Divider(height: 20),
                    _kv('Security deposit', _currency.format(deposit)),
                    _kv(
                      'Est. refund (deposit − dues)',
                      _currency.format(refundEstimate),
                      valueColor: refundEstimate >= 0
                          ? AppColors.positive
                          : AppColors.danger,
                    ),
                    if (_isEnded)
                      _kv(
                        'Refund status',
                        refundEstimate >= 0
                            ? 'Settled (see notes / NOC)'
                            : 'Settled (tenant owed)',
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: const Text(
                            'Refund status',
                            style: TextStyle(
                              color: AppColors.slate,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: const Text(
                            'Pending — initiate final settlement to checkout',
                            style: TextStyle(fontSize: 12),
                          ),
                          trailing: const Icon(
                            Icons.chevron_right,
                            color: AppColors.blueprint,
                          ),
                          onTap: () async {
                            final done = await showCheckoutSettlementSheet(
                              context: context,
                              ref: ref,
                              propertyId: propertyId,
                              tenancy: tenancy,
                              isEmergencyExit: _isEmergencyRequest(tenancy),
                            );
                            if (done) await onRefresh();
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'KYC documents',
            child: docsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => const Text('No documents available.'),
              data: (docs) {
                final agreement = tenancy['agreement_pdf_url'] ??
                    tenancy['agreementPdfUrl'];
                final idType =
                    (tenancy['id_type'] ?? tenancy['idType'])?.toString();
                final aadhaar =
                    (tenancy['aadhaar_number'] ?? tenancy['aadhaarNumber'])
                        ?.toString();
                final kyc = (tenancy['kyc_status'] ?? tenancy['kycStatus'])
                        ?.toString() ??
                    'pending';

                if (docs.isEmpty &&
                    (agreement == null || agreement.toString().isEmpty) &&
                    (aadhaar == null || aadhaar.isEmpty)) {
                  return const Text(
                    'No KYC documents uploaded yet.',
                    style: TextStyle(color: AppColors.slate),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _kv('KYC status', kyc),
                    if (idType != null && idType.isNotEmpty)
                      _kv('ID type', idType),
                    if (aadhaar != null && aadhaar.isNotEmpty)
                      _kv('Aadhaar', _maskAadhaar(aadhaar)),
                    ...docs.map((d) {
                      final type =
                          (d['doc_type'] ?? d['docType'])?.toString() ??
                              'Document';
                      final url = (d['file_url'] ?? d['fileUrl'])?.toString();
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: const Icon(Icons.description_outlined,
                            color: AppColors.blueprint),
                        title: Text(type),
                        trailing: url == null
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.open_in_new, size: 18),
                                onPressed: () => _openUrl(url, baseUrl),
                              ),
                      );
                    }),
                    if (agreement != null &&
                        agreement.toString().trim().isNotEmpty)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: const Icon(Icons.picture_as_pdf_outlined,
                            color: AppColors.blueprint),
                        title: const Text('Agreement'),
                        trailing: IconButton(
                          icon: const Icon(Icons.open_in_new, size: 18),
                          onPressed: () =>
                              _openUrl(agreement.toString(), baseUrl),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          if (!_isEnded)
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.blueprint,
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  final done = await showCheckoutSettlementSheet(
                    context: context,
                    ref: ref,
                    propertyId: propertyId,
                    tenancy: tenancy,
                    isEmergencyExit: _isEmergencyRequest(tenancy),
                  );
                  if (done) await onRefresh();
                },
                icon: const Icon(Icons.receipt_long_outlined),
                label: Text(
                  _isEmergencyRequest(tenancy)
                      ? 'Proceed to Emergency Settlement'
                      : 'Initiate Final Settlement',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            )
          else
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.blueprint,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => _reAdmit(context, ref),
                icon: const Icon(Icons.meeting_room_outlined),
                label: const Text(
                  'Re-Admit / Assign New Room',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static bool _hasMoveOutRequest(Map<String, dynamic> t) {
    final status = t['move_out_request_status']?.toString();
    if (status != null &&
        status.isNotEmpty &&
        status != 'rejected') {
      return true;
    }
    final notice = t['notice_given_at'] ?? t['noticeGivenAt'];
    return notice != null && notice.toString().trim().isNotEmpty;
  }

  static bool _isEmergencyRequest(Map<String, dynamic> t) {
    return t['move_out_is_emergency'] == true ||
        t['move_out_is_emergency']?.toString() == 'true';
  }

  Future<void> _openLedger(BuildContext context, WidgetRef ref) async {
    await openLedgerStatic(
      context: context,
      ref: ref,
      propertyId: propertyId,
      tenancy: tenancy,
      onRefresh: onRefresh,
    );
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
      roomLabel:
          (tenancy['node_name'] ?? tenancy['nodeName'])?.toString() ?? 'Room',
      phone: tenancy['phone']?.toString(),
      allInvoices: invoices,
    );
    await onRefresh();
  }

  Future<void> _reAdmit(BuildContext context, WidgetRef ref) async {
    await openAddTenantFlow(
      context: context,
      ref: ref,
      propertyId: propertyId,
      prefill: TenantPrefill.fromTenancy(tenancy),
    );
    await onRefresh();
  }

  static String? _emergencyContact(Map<String, dynamic> t) {
    final name = (t['emergency_contact_name'] ?? t['emergencyContactName'])
        ?.toString()
        .trim();
    final phone = (t['emergency_contact_phone'] ?? t['emergencyContactPhone'])
        ?.toString()
        .trim();
    final relation =
        (t['emergency_contact_relation'] ?? t['emergencyContactRelation'])
            ?.toString()
            .trim();
    if ((name == null || name.isEmpty) && (phone == null || phone.isEmpty)) {
      return null;
    }
    final parts = <String>[
      if (name != null && name.isNotEmpty) name,
      if (relation != null && relation.isNotEmpty) '($relation)',
      if (phone != null && phone.isNotEmpty) phone,
    ];
    return parts.join(' ');
  }

  static String? _fmtDate(dynamic raw) {
    if (raw == null || raw.toString().trim().isEmpty) return null;
    final d = DateTime.tryParse(raw.toString());
    if (d == null) return null;
    return _dateFmt.format(d.toLocal());
  }

  static String? _fmtDateTime(dynamic raw) {
    if (raw == null || raw.toString().trim().isEmpty) return null;
    final d = DateTime.tryParse(raw.toString());
    if (d == null) return null;
    return DateFormat('d MMM yyyy, h:mm a').format(d.toLocal());
  }

  static double _amount(dynamic raw) =>
      double.tryParse(raw?.toString() ?? '') ?? 0;

  static String _maskAadhaar(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 4) return raw;
    return 'XXXX XXXX ${digits.substring(digits.length - 4)}';
  }

  static String? _photoUrl(Map<String, dynamic> r, String baseUrl) {
    final raw = r['profile_photo_url'] ?? r['profilePhotoUrl'];
    if (raw == null || raw.toString().trim().isEmpty) return null;
    final s = raw.toString();
    if (s.startsWith('http')) return s;
    return '$baseUrl$s';
  }

  static Future<void> _openUrl(String url, String baseUrl) async {
    final full = url.startsWith('http') ? url : '$baseUrl$url';
    final uri = Uri.tryParse(full);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Widget _kv(String label, String value, {Color? valueColor}) {
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
            child: Text(
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
}

class _HeaderCard extends StatelessWidget {
  final String name;
  final String phone;
  final String? emergency;
  final String statusLabel;
  final Color statusColor;
  final String? photoUrl;

  const _HeaderCard({
    required this.name,
    required this.phone,
    required this.emergency,
    required this.statusLabel,
    required this.statusColor,
    required this.photoUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.canvas,
            backgroundImage:
                photoUrl != null ? NetworkImage(photoUrl!) : null,
            child: photoUrl == null
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.blueprint,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(phone, style: const TextStyle(color: AppColors.slate)),
                if (emergency != null && emergency!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Emergency: $emergency',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.slate,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _SectionCard({
    required this.title,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
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
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

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
          Text(
            'Status: ${status.replaceAll('_', ' ')}',
            style: const TextStyle(fontSize: 12, color: AppColors.slate),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.positive,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => _review(context, ref, 'approve'),
                child: const Text('Approve Notice Date'),
              ),
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
      firstDate: today, // Cannot set a past date
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
