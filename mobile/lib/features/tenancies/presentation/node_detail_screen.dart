// features/tenancies/presentation/node_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../billing/data/billing_repository.dart';
import '../../billing/presentation/invoices_list_screen.dart' show invoicesProvider;
import '../../billing/presentation/tenant_ledger_sheet.dart';
import '../../complaints/data/complaints_repository.dart';
import '../../structure/data/structure_repository.dart';
import '../../structure/presentation/dynamic_dashboard/dynamic_dashboard_screen.dart'
    show hierarchyLevelsProvider;
import '../data/tenancy_repository.dart';
import '../domain/assignable_unit.dart';
import 'add_tenant_screen.dart';
import 'tenant_profile_section.dart';

final tenanciesForNodeProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, (String propertyId, String nodeId)>(
        (ref, args) async {
  final repo = ref.watch(tenancyRepositoryProvider);
  return repo.listByNode(args.$1, args.$2);
});

final roomComplaintsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, (String propertyId, String nodeId)>(
        (ref, args) async {
  final all =
      await ref.watch(complaintsRepositoryProvider).listForProperty(args.$1);
  final nodeId = args.$2.toLowerCase();
  return all
      .map((e) => Map<String, dynamic>.from(e as Map))
      .where((c) {
        final nid = (c['node_id'] ?? c['nodeId'])?.toString().toLowerCase();
        return nid == nodeId;
      })
      .toList();
});

final tenancyInvoicesProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, (String propertyId, String tenancyId)>(
        (ref, args) async {
  final all =
      await ref.watch(billingRepositoryProvider).listInvoices(args.$1);
  final tenancyId = args.$2.toLowerCase();
  return all.where((i) {
    final tid = (i['tenancy_id'] ?? i['tenancyId'])?.toString().toLowerCase();
    return tid == tenancyId;
  }).toList();
});

class NodeDetailScreen extends ConsumerWidget {
  final String propertyId;
  final String nodeId;
  final String nodeName;
  final String levelName;

  const NodeDetailScreen({
    super.key,
    required this.propertyId,
    required this.nodeId,
    required this.nodeName,
    required this.levelName,
  });

  Future<void> _renameNode(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: nodeName);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(context, controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty && context.mounted) {
      try {
        await ref
            .read(structureRepositoryProvider)
            .renameNode(propertyId, nodeId, newName);
        if (context.mounted) Navigator.of(context).pop(true);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not rename: $e')));
        }
      }
    }
  }

  Future<void> _deleteNode(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "$nodeName"?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      try {
        await ref
            .read(structureRepositoryProvider)
            .deleteNode(propertyId, nodeId);
        if (context.mounted) Navigator.of(context).pop(true);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not delete: $e')));
        }
      }
    }
  }

  Future<void> _endTenancy(
      BuildContext context, WidgetRef ref, String tenancyId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End this tenancy?'),
        content: const Text(
            'This marks the tenant as moved out. Their records stay for history.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('End Tenancy')),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await ref
            .read(tenancyRepositoryProvider)
            .endTenancy(propertyId, tenancyId);
        ref.invalidate(tenanciesForNodeProvider((propertyId, nodeId)));
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not end tenancy: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenanciesAsync =
        ref.watch(tenanciesForNodeProvider((propertyId, nodeId)));
    final levelsAsync = ref.watch(hierarchyLevelsProvider(propertyId));

    return Scaffold(
      appBar: AppBar(
        title: Text(nodeName),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'rename') _renameNode(context, ref);
              if (value == 'delete') _deleteNode(context, ref);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      body: levelsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Something went wrong: $err')),
        data: (levels) {
          final level =
              levels.where((l) => l.displayName == levelName).firstOrNull;
          final assignable =
              level != null && isAssignableLevel(level.id, levels);

          return tenanciesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) =>
                Center(child: Text('Something went wrong: $err')),
            data: (tenancies) {
              final active =
                  tenancies.where((t) => t['status'] == 'active').toList();

              if (active.isEmpty) {
                if (!assignable && level != null) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.info_outline,
                              size: 56, color: Colors.grey),
                          const SizedBox(height: 16),
                          Text(
                            nonAssignableReason(level.id, levels) ??
                                'Tenants are assigned to a more specific unit under this $levelName.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Open the Rooms tab, expand this section, and pick a bed or unit.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.person_outline,
                            size: 56, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text('No tenant assigned to this $levelName',
                            textAlign: TextAlign.center,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: () async {
                            final created =
                                await Navigator.of(context).push<bool>(
                              MaterialPageRoute(
                                builder: (context) => AddTenantScreen(
                                  propertyId: propertyId,
                                  nodeId: nodeId,
                                ),
                              ),
                            );
                            if (created == true) {
                              ref.invalidate(
                                  tenanciesForNodeProvider((propertyId, nodeId)));
                            }
                          },
                          icon: const Icon(Icons.person_add_outlined),
                          label: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text('Add Tenant'),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final tenant = active.first;
              return _TenantDetailBody(
                propertyId: propertyId,
                nodeId: nodeId,
                tenant: tenant,
                onEndTenancy: (tenancyId) =>
                    _endTenancy(context, ref, tenancyId),
                onUploadAgreement: (tenancyId) =>
                    _uploadAgreement(context, ref, tenancyId),
                onViewAgreement: (url) =>
                    _viewAgreement(context, ref, url),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _uploadAgreement(
      BuildContext context, WidgetRef ref, String tenancyId) async {
    final result = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['pdf']);
    if (result == null || result.files.single.path == null) return;

    try {
      await ref.read(tenancyRepositoryProvider).uploadAgreement(
          propertyId, tenancyId, result.files.single.path!);
      ref.invalidate(tenanciesForNodeProvider((propertyId, nodeId)));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Agreement uploaded')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    }
  }

  Future<void> _viewAgreement(
      BuildContext context, WidgetRef ref, String relativeUrl) async {
    final baseUrl = ref.read(tenancyRepositoryProvider).baseUrl;
    final uri = Uri.parse('$baseUrl$relativeUrl');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _TenantDetailBody extends ConsumerWidget {
  final String propertyId;
  final String nodeId;
  final Map<String, dynamic> tenant;
  final Future<void> Function(String tenancyId) onEndTenancy;
  final Future<void> Function(String tenancyId) onUploadAgreement;
  final Future<void> Function(String url) onViewAgreement;

  const _TenantDetailBody({
    required this.propertyId,
    required this.nodeId,
    required this.tenant,
    required this.onEndTenancy,
    required this.onUploadAgreement,
    required this.onViewAgreement,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenancyId = tenant['id']?.toString() ?? '';
    final invoicesAsync =
        ref.watch(tenancyInvoicesProvider((propertyId, tenancyId)));
    final baseUrl = ref.watch(tenancyRepositoryProvider).baseUrl;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        _TenantHeroSection(
          propertyId: propertyId,
          nodeId: nodeId,
          tenancyId: tenancyId,
          tenant: tenant,
          baseUrl: baseUrl,
        ),
        const SizedBox(height: 16),
        TenantProfileSection(
          propertyId: propertyId,
          nodeId: nodeId,
          tenancyId: tenancyId,
          baseUrl: baseUrl,
        ),
        const SizedBox(height: 16),
        _ComplaintsSection(propertyId: propertyId, nodeId: nodeId),
        const SizedBox(height: 16),
        invoicesAsync.when(
          loading: () => _FinancialOverviewCard(
            propertyId: propertyId,
            nodeId: nodeId,
            tenancyId: tenancyId,
            pendingDues: null,
            invoices: const [],
          ),
          error: (_, __) => _FinancialOverviewCard(
            propertyId: propertyId,
            nodeId: nodeId,
            tenancyId: tenancyId,
            pendingDues: 0,
            invoices: const [],
          ),
          data: (invoices) => _FinancialOverviewCard(
            propertyId: propertyId,
            nodeId: nodeId,
            tenancyId: tenancyId,
            pendingDues: _computePendingDues(invoices),
            invoices: invoices,
          ),
        ),
        const SizedBox(height: 16),
        _LeaseDocumentsCard(
          tenant: tenant,
          onUpload: () => onUploadAgreement(tenancyId),
          onView: () {
            final url = tenant['agreement_pdf_url']?.toString();
            if (url != null) onViewAgreement(url);
          },
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppColors.danger),
            minimumSize: const Size.fromHeight(50),
          ),
          onPressed: () => onEndTenancy(tenancyId),
          child: const Text('End Tenancy',
              style: TextStyle(color: AppColors.danger)),
        ),
      ],
    );
  }
}

class _TenantHeroSection extends ConsumerWidget {
  final String propertyId;
  final String nodeId;
  final String tenancyId;
  final Map<String, dynamic> tenant;
  final String baseUrl;

  const _TenantHeroSection({
    required this.propertyId,
    required this.nodeId,
    required this.tenancyId,
    required this.tenant,
    required this.baseUrl,
  });

  Map<String, dynamic> _liveTenant(WidgetRef ref) {
    final async = ref.watch(tenanciesForNodeProvider((propertyId, nodeId)));
    return async.maybeWhen(
      data: (tenancies) {
        for (final raw in tenancies) {
          final t = Map<String, dynamic>.from(raw);
          if (t['id']?.toString() == tenancyId) return t;
        }
        return tenant;
      },
      orElse: () => tenant,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = _liveTenant(ref);
    final name = _tenantName(live);
    final phone = _tenantPhone(live);
    final photoUrl = _profilePhotoUrl(live, baseUrl);
    final initials = _tenantInitials(name);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => openTenantProfilePhotoViewer(
                  context,
                  propertyId: propertyId,
                  nodeId: nodeId,
                  tenancyId: tenancyId,
                  baseUrl: baseUrl,
                  tenantName: name,
                  initials: initials,
                  photoUrl: photoUrl,
                ),
                customBorder: const CircleBorder(),
                child: _buildAvatar(photoUrl, initials),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              name,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              phone.isEmpty ? 'No phone on file' : phone,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (phone.isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _QuickActionButton(
                    icon: Icons.phone_outlined,
                    label: 'Call',
                    onTap: () => _launchCall(phone),
                  ),
                  const SizedBox(width: 12),
                  _QuickActionButton(
                    icon: Icons.chat_outlined,
                    label: 'WhatsApp',
                    color: const Color(0xFF25D366),
                    onTap: () => _launchWhatsApp(phone, name),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(String? photoUrl, String initials) {
    if (photoUrl != null && photoUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 40,
        backgroundColor: AppColors.blueprint.withValues(alpha: 0.1),
        child: ClipOval(
          child: Image.network(
            photoUrl,
            width: 80,
            height: 80,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _initialsAvatar(initials),
          ),
        ),
      );
    }
    return _initialsAvatar(initials);
  }

  Widget _initialsAvatar(String initials) {
    return CircleAvatar(
      radius: 40,
      backgroundColor: AppColors.blueprint.withValues(alpha: 0.12),
      child: Text(
        initials,
        style: const TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w800,
          color: AppColors.blueprint,
        ),
      ),
    );
  }

  Future<void> _launchCall(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _launchWhatsApp(String phone, String name) async {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    final uri = Uri.parse(
        'https://wa.me/$digits?text=${Uri.encodeComponent('Hi $name,')}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final tint = color ?? AppColors.blueprint;
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: tint),
      label: Text(label, style: TextStyle(color: tint)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: tint.withValues(alpha: 0.35)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
    );
  }
}

class _ComplaintsSection extends ConsumerWidget {
  final String propertyId;
  final String nodeId;

  const _ComplaintsSection({
    required this.propertyId,
    required this.nodeId,
  });

  Future<void> _showAddComplaint(BuildContext context, WidgetRef ref) async {
    final categoryController = TextEditingController();
    final descriptionController = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Complaint'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: categoryController,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'e.g. Leaking Tap',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );

    if (saved != true || !context.mounted) return;

    final category = categoryController.text.trim();
    final description = descriptionController.text.trim();
    if (category.isEmpty || description.isEmpty) return;

    try {
      await ref.read(complaintsRepositoryProvider).createForProperty(
            propertyId,
            nodeId: nodeId,
            category: category,
            description: description,
          );
      ref.invalidate(roomComplaintsProvider((propertyId, nodeId)));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Complaint submitted')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not submit complaint: $e')));
      }
    }
  }

  void _openComplaintDetail(
    BuildContext context,
    Map<String, dynamic> complaint,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ComplaintDetailSheet(
        propertyId: propertyId,
        nodeId: nodeId,
        complaint: complaint,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final complaintsAsync =
        ref.watch(roomComplaintsProvider((propertyId, nodeId)));

    return _SectionCard(
      title: 'Recent Complaints',
      trailing: TextButton(
        onPressed: () => _showAddComplaint(context, ref),
        child: const Text('+ Add Complaint'),
      ),
      child: complaintsAsync.when(
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        error: (err, _) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Text(
                'Could not load complaints',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(
                  roomComplaintsProvider((propertyId, nodeId)),
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (complaints) {
          if (complaints.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No complaints logged for this unit yet.',
                style: TextStyle(color: Colors.grey),
              ),
            );
          }

          return ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: complaints.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final c = complaints[i];
              final title = _complaintTitle(c);
              final date = _formatComplaintDate(c);
              final status = c['status']?.toString() ?? 'open';
              final badge = _statusBadge(status);

              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(date),
                trailing: badge,
                onTap: () => _openComplaintDetail(context, c),
              );
            },
          );
        },
      ),
    );
  }
}

class _ComplaintDetailSheet extends ConsumerStatefulWidget {
  final String propertyId;
  final String nodeId;
  final Map<String, dynamic> complaint;

  const _ComplaintDetailSheet({
    required this.propertyId,
    required this.nodeId,
    required this.complaint,
  });

  @override
  ConsumerState<_ComplaintDetailSheet> createState() =>
      _ComplaintDetailSheetState();
}

class _ComplaintDetailSheetState extends ConsumerState<_ComplaintDetailSheet> {
  late String _status;
  bool _saving = false;

  static const _statusOptions = ['open', 'in_progress', 'resolved'];

  @override
  void initState() {
    super.initState();
    _status = _normalizeStatus(widget.complaint['status']?.toString());
  }

  String _normalizeStatus(String? raw) {
    if (raw == null || raw.isEmpty) return 'open';
    if (raw == 'closed') return 'resolved';
    if (_statusOptions.contains(raw)) return raw;
    return 'open';
  }

  Future<void> _updateStatus(String next) async {
    if (next == _status || _saving) return;
    setState(() {
      _saving = true;
      _status = next;
    });

    try {
      await ref.read(complaintsRepositoryProvider).updateStatus(
            widget.propertyId,
            widget.complaint['id'].toString(),
            next,
          );
      ref.invalidate(
        roomComplaintsProvider((widget.propertyId, widget.nodeId)),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Complaint status updated')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _status = _normalizeStatus(
              widget.complaint['status']?.toString(),
            ));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update status: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final complaint = widget.complaint;
    final title = _complaintTitle(complaint);
    final description = complaint['description']?.toString().trim() ?? '';
    final reportedOn = _formatComplaintDateLong(complaint);
    final resolvedRaw = complaint['resolved_at'] ?? complaint['resolvedAt'];
    final showResolved = _status == 'resolved' ||
        _status == 'closed' ||
        resolvedRaw != null;
    final resolvedOn = showResolved
        ? (resolvedRaw != null
            ? _formatComplaintDateLong({'created_at': resolvedRaw})
            : null)
        : null;
    final imageUrl = _complaintImageUrl(complaint);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.hairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              description.isEmpty ? 'No description provided.' : description,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            _TimelineRow(label: 'Reported on', value: reportedOn),
            if (resolvedOn != null) ...[
              const SizedBox(height: 8),
              _TimelineRow(label: 'Resolved on', value: resolvedOn),
            ],
            const SizedBox(height: 16),
            if (imageUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  imageUrl,
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _imagePlaceholder(),
                ),
              )
            else
              _imagePlaceholder(),
            const SizedBox(height: 20),
            Text('Update status',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'open',
                  label: Text('Pending', style: TextStyle(fontSize: 12)),
                ),
                ButtonSegment(
                  value: 'in_progress',
                  label: Text('In Progress', style: TextStyle(fontSize: 12)),
                ),
                ButtonSegment(
                  value: 'resolved',
                  label: Text('Resolved', style: TextStyle(fontSize: 12)),
                ),
              ],
              selected: {_status},
              onSelectionChanged: _saving
                  ? null
                  : (selection) => _updateStatus(selection.first),
            ),
            if (_saving) ...[
              const SizedBox(height: 12),
              const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      width: double.infinity,
      height: 120,
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.hairline),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_outlined, color: AppColors.slate, size: 28),
          SizedBox(height: 6),
          Text(
            'No photos attached',
            style: TextStyle(color: AppColors.slate, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final String label;
  final String value;

  const _TimelineRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
        ),
      ],
    );
  }
}

class _FinancialOverviewCard extends ConsumerWidget {
  final String propertyId;
  final String nodeId;
  final String tenancyId;
  final double? pendingDues;
  final List<Map<String, dynamic>> invoices;

  const _FinancialOverviewCard({
    required this.propertyId,
    required this.nodeId,
    required this.tenancyId,
    required this.pendingDues,
    required this.invoices,
  });

  Map<String, dynamic> _activeTenancy(WidgetRef ref) {
    final async = ref.watch(tenanciesForNodeProvider((propertyId, nodeId)));
    return async.maybeWhen(
      data: (tenancies) {
        for (final raw in tenancies) {
          final t = Map<String, dynamic>.from(raw);
          if (t['status']?.toString() == 'active') return t;
        }
        return const {};
      },
      orElse: () => const {},
    );
  }

  Future<void> _showEditAmountDialog(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required double? currentValue,
    required Future<Map<String, dynamic>> Function(double amount) onSave,
  }) async {
    final controller = TextEditingController(
      text: currentValue != null && currentValue > 0
          ? currentValue.toStringAsFixed(
              currentValue == currentValue.roundToDouble() ? 0 : 2,
            )
          : '',
    );
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              prefixText: '₹ ',
              labelText: 'Amount',
              border: OutlineInputBorder(),
            ),
            validator: (v) {
              final n = double.tryParse(v?.trim() ?? '');
              if (n == null || n < 0) return 'Enter a valid amount';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved != true) return;

    final amount = double.tryParse(controller.text.trim());
    if (amount == null) return;

    try {
      await onSave(amount);

      ref.invalidate(tenanciesForNodeProvider((propertyId, nodeId)));
      await ref.read(tenanciesForNodeProvider((propertyId, nodeId)).future);
      ref.invalidate(tenancyInvoicesProvider((propertyId, tenancyId)));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$title updated'),
            backgroundColor: AppColors.positive,
          ),
        );
      }
    } on TenancyUpdateException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Something went wrong. Please try again.'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _showAddChargeDialog(BuildContext context, WidgetRef ref) async {
    final reasonController = TextEditingController();
    final amountController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Charge'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: reasonController,
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  hintText: 'e.g. Electricity',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Enter a reason' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  prefixText: '₹ ',
                  labelText: 'Amount',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final n = double.tryParse(v?.trim() ?? '');
                  if (n == null || n <= 0) return 'Enter a valid amount';
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (saved != true) return;

    final reason = reasonController.text.trim();
    final amount = double.tryParse(amountController.text.trim());
    if (amount == null) return;

    try {
      final today = DateTime.now();
      final iso = today.toIso8601String().split('T').first;
      final due = today.add(const Duration(days: 7)).toIso8601String().split('T').first;

      await ref.read(billingRepositoryProvider).createInvoice(
            propertyId,
            tenancyId: tenancyId,
            periodStart: iso,
            periodEnd: iso,
            dueDate: due,
            lineItems: [
              {'description': reason, 'amount': amount},
            ],
          );

      ref.invalidate(tenancyInvoicesProvider((propertyId, tenancyId)));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Charge added: $reason')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Charge saved locally pending sync: $reason · ${_formatCurrency(amount)}',
            ),
          ),
        );
      }
    }
  }

  Future<void> _showLedgerSheet(BuildContext context, WidgetRef ref) async {
    final tenant = _activeTenancy(ref);
    final tenantName = _tenantName(tenant);
    final roomLabel = (tenant['node_name'] ?? tenant['nodeName'] ?? 'Room')
        .toString();

    // Prefer property-wide list (same source as Payments); fall back to
    // tenancy invoices already loaded on this card.
    var allInvoices = invoices;
    try {
      allInvoices =
          await ref.read(billingRepositoryProvider).listInvoices(propertyId);
    } catch (_) {
      // Keep local list.
    }

    if (!context.mounted) return;

    await showTenantLedgerSheet(
      context: context,
      ref: ref,
      propertyId: propertyId,
      tenancyId: tenancyId,
      tenantName: tenantName.isEmpty ? 'Tenant' : tenantName,
      roomLabel: roomLabel,
      allInvoices: allInvoices,
    );

    ref.invalidate(tenancyInvoicesProvider((propertyId, tenancyId)));
    ref.invalidate(invoicesProvider(propertyId));
  }

  Future<void> _showRecordPaymentSheet(
      BuildContext context, WidgetRef ref) async {
    Map<String, dynamic>? target;
    var maxPayable = 0.0;

    for (final inv in invoices) {
      final status = inv['status']?.toString() ?? '';
      if (!{'pending', 'partial', 'overdue'}.contains(status)) continue;
      final total = double.tryParse(
            inv['total_amount']?.toString() ??
                inv['totalAmount']?.toString() ??
                '',
          ) ??
          0;
      final paid = double.tryParse(
            inv['paid_amount']?.toString() ??
                inv['paidAmount']?.toString() ??
                '',
          ) ??
          0;
      final balance = total - paid;
      if (balance > 0) {
        target = inv;
        maxPayable = balance;
        break;
      }
    }

    if (target == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No outstanding dues to record against')),
        );
      }
      return;
    }

    final controller =
        TextEditingController(text: maxPayable.toStringAsFixed(0));
    final formKey = GlobalKey<FormState>();

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Record Payment',
                  style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                'Outstanding: ${_formatCurrency(maxPayable)}',
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: controller,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  prefixText: '₹ ',
                  labelText: 'Amount received',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final n = double.tryParse(v?.trim() ?? '');
                  if (n == null || n <= 0) return 'Enter a valid amount';
                  if (n > maxPayable + 0.01) {
                    return 'Cannot exceed outstanding balance';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    if (formKey.currentState?.validate() ?? false) {
                      Navigator.pop(ctx, true);
                    }
                  },
                  child: const Text('Record Payment'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (saved != true) return;

    final amount = double.tryParse(controller.text.trim());
    if (amount == null) return;

    try {
      await ref.read(billingRepositoryProvider).recordPayment(
            propertyId,
            target['id'].toString(),
            amount,
            'cash',
          );
      ref.invalidate(tenancyInvoicesProvider((propertyId, tenancyId)));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Payment recorded: ${_formatCurrency(amount)}')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not record payment: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = _activeTenancy(ref);
    final rent = _readTenancyAmount(tenant, ['monthly_rent', 'monthlyRent']);
    final deposit = _readTenancyAmount(
      tenant,
      ['security_deposit', 'securityDeposit'],
    );
    final moveIn = tenant['move_in_at'] ?? tenant['moveInAt'];
    final outstanding = pendingDues;
    final outstandingLabel = outstanding == null
        ? '…'
        : _formatCurrency(outstanding);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionCard(
          title: 'Current Outstanding',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                outstandingLabel,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: (outstanding ?? 0) > 0
                          ? AppColors.danger
                          : AppColors.positive,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                (outstanding ?? 0) > 0
                    ? 'Total unpaid across all invoices'
                    : 'No pending dues',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
              ),
              Align(
                alignment: Alignment.center,
                child: TextButton.icon(
                  onPressed: () => _showAddChargeDialog(context, ref),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Charge'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.blueprint,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _showLedgerSheet(context, ref),
                      child: const Text('View Ledger'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _showRecordPaymentSheet(context, ref),
                      child: const Text('Record Payment'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Lease & Financials',
          child: Column(
            children: [
              _EditableFinancialRow(
                label: 'Base Monthly Rent',
                value: rent != null ? _formatCurrency(rent) : '—',
                onEdit: () => _showEditAmountDialog(
                  context,
                  ref,
                  title: 'Update Base Rent',
                  currentValue: rent,
                  onSave: (amount) => ref
                      .read(tenancyRepositoryProvider)
                      .update(
                        propertyId,
                        tenancyId,
                        nodeId: nodeId,
                        monthlyRent: amount,
                      ),
                ),
              ),
              const Divider(height: 20),
              _EditableFinancialRow(
                label: 'Security Deposit',
                value: deposit != null ? _formatCurrency(deposit) : '—',
                onEdit: () => _showEditAmountDialog(
                  context,
                  ref,
                  title: 'Update Security Deposit',
                  currentValue: deposit,
                  onSave: (amount) => ref
                      .read(tenancyRepositoryProvider)
                      .update(
                        propertyId,
                        tenancyId,
                        nodeId: nodeId,
                        securityDeposit: amount,
                      ),
                ),
              ),
              const Divider(height: 20),
              _FinancialRow(
                label: 'Move-in Date',
                value: moveIn != null
                    ? moveIn.toString().split('T').first
                    : 'Not recorded',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EditableFinancialRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onEdit;

  const _EditableFinancialRow({
    required this.label,
    required this.value,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        IconButton(
          onPressed: onEdit,
          icon: Icon(Icons.edit, size: 18, color: Colors.grey.shade500),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
      ],
    );
  }
}

class _LeaseDocumentsCard extends StatelessWidget {
  final Map<String, dynamic> tenant;
  final VoidCallback onUpload;
  final VoidCallback onView;

  const _LeaseDocumentsCard({
    required this.tenant,
    required this.onUpload,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    final agreementUrl = tenant['agreement_pdf_url'] ?? tenant['agreementPdfUrl'];

    return _SectionCard(
      title: 'Documents',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (agreementUrl != null)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onView,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('View Agreement'),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onUpload,
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Upload Agreement'),
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
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title, style: Theme.of(context).textTheme.titleMedium),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _FinancialRow extends StatelessWidget {
  final String label;
  final String value;

  const _FinancialRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    );
  }
}

// ---- Helpers ----

double? _readTenancyAmount(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final raw = data[key];
    if (raw == null) continue;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString());
  }
  return null;
}

String _complaintTitle(Map<String, dynamic> complaint) {
  return complaint['category']?.toString().trim().isNotEmpty == true
      ? complaint['category'].toString()
      : 'Complaint';
}

String? _complaintImageUrl(Map<String, dynamic> complaint) {
  for (final key in [
    'image_url',
    'imageUrl',
    'attachment_url',
    'attachmentUrl',
  ]) {
    final raw = complaint[key]?.toString().trim();
    if (raw != null && raw.isNotEmpty) return raw;
  }
  return null;
}

String _formatComplaintDateLong(Map<String, dynamic> complaint) {
  final raw = complaint['created_at'] ?? complaint['createdAt'];
  if (raw == null) return 'Unknown date';
  final date = DateTime.tryParse(raw.toString());
  if (date == null) return raw.toString().split('T').first;
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final weekday = weekdays[date.weekday - 1];
  return '$weekday, ${months[date.month - 1]} ${date.day}, ${date.year}';
}

String _tenantName(Map<String, dynamic> tenant) {
  for (final key in ['full_name', 'fullName', 'user_name', 'userName']) {
    final v = tenant[key]?.toString().trim();
    if (v != null && v.isNotEmpty) return v;
  }
  return 'Tenant';
}

String _tenantPhone(Map<String, dynamic> tenant) {
  return tenant['phone']?.toString().trim() ?? '';
}

String? _profilePhotoUrl(Map<String, dynamic> tenant, String baseUrl) {
  final raw = tenant['profile_photo_url'] ?? tenant['profilePhotoUrl'];
  if (raw == null) return null;
  final url = raw.toString().trim();
  if (url.isEmpty) return null;
  if (url.startsWith('http')) return url;
  return '$baseUrl$url';
}

String _tenantInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    return parts.first.isNotEmpty ? parts.first[0].toUpperCase() : '?';
  }
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}

String _formatCurrency(dynamic amount) {
  final n = double.tryParse(amount.toString()) ?? 0;
  if (n == n.roundToDouble()) return '₹${n.toInt()}';
  return '₹${n.toStringAsFixed(2)}';
}

double _computePendingDues(List<Map<String, dynamic>> invoices) {
  var total = 0.0;
  for (final invoice in invoices) {
    final status = invoice['status']?.toString() ?? '';
    if (!{'pending', 'partial', 'overdue'}.contains(status)) continue;
    final invoiceTotal =
        double.tryParse(invoice['total_amount']?.toString() ?? '') ??
            double.tryParse(invoice['totalAmount']?.toString() ?? '') ??
            0;
    final paid =
        double.tryParse(invoice['paid_amount']?.toString() ?? '') ??
            double.tryParse(invoice['paidAmount']?.toString() ?? '') ??
            0;
    total += (invoiceTotal - paid).clamp(0, double.infinity);
  }
  return total;
}

String _formatComplaintDate(Map<String, dynamic> complaint) {
  final raw = complaint['created_at'] ?? complaint['createdAt'];
  if (raw == null) return 'Date unknown';
  final date = DateTime.tryParse(raw.toString());
  if (date == null) return raw.toString().split('T').first;
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

Widget _statusBadge(String status) {
  late String label;
  late Color color;

  switch (status) {
    case 'in_progress':
      label = '🟡 In Progress';
      color = AppColors.caution;
    case 'resolved':
    case 'closed':
      label = '🟢 Resolved';
      color = AppColors.positive;
    default:
      label = '🔴 Pending';
      color = AppColors.danger;
  }

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
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

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
