// features/complaints/presentation/maintenance_action_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../billing/presentation/whatsapp_reminder.dart' show whatsAppGreen;
import '../../dashboard/presentation/property_dashboard_provider.dart';
import '../../expenses/presentation/add_expense_sheet.dart';
import '../../tenancies/presentation/residents_list_screen.dart'
    show propertyResidentsProvider;
import '../data/complaints_repository.dart';
import 'complaints_list_screen.dart' show complaintsProvider;

const _accent = AppColors.primary;

Future<void> showMaintenanceActionSheet({
  required BuildContext context,
  required String propertyId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => MaintenanceActionSheet(propertyId: propertyId),
  );
}

class MaintenanceActionSheet extends ConsumerWidget {
  final String propertyId;

  const MaintenanceActionSheet({
    super.key,
    required this.propertyId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final complaintsAsync = ref.watch(complaintsProvider(propertyId));
    final tenanciesAsync = ref.watch(propertyResidentsProvider(propertyId));

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      builder: (context, scrollController) {
        final all = complaintsAsync.maybeWhen(
          data: (rows) => rows,
          orElse: () => const <Map<String, dynamic>>[],
        );
        final tenancies = tenanciesAsync.maybeWhen(
          data: (rows) => rows,
          orElse: () => const <Map<String, dynamic>>[],
        );
        final open = all.where(_isOpenComplaint).toList();

        return Material(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 10),
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.hairline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Open Maintenance Requests',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      _CountBadge(count: open.length),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: complaintsAsync.isLoading
                      ? const Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _accent,
                            ),
                          ),
                        )
                      : complaintsAsync.hasError
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      'Could not load maintenance requests.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: AppColors.slate),
                                    ),
                                    const SizedBox(height: 12),
                                    TextButton(
                                      onPressed: () => ref.invalidate(
                                        complaintsProvider(propertyId),
                                      ),
                                      style: TextButton.styleFrom(
                                        foregroundColor: _accent,
                                      ),
                                      child: const Text('Retry'),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : open.isEmpty
                              ? const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Text(
                                      'No open maintenance requests.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: AppColors.slate),
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  controller: scrollController,
                                  padding:
                                      const EdgeInsets.fromLTRB(8, 8, 8, 16),
                                  itemCount: open.length,
                                  itemBuilder: (context, i) => _ComplaintTile(
                                    propertyId: propertyId,
                                    complaint: open[i],
                                    tenancies: tenancies,
                                  ),
                                ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CountBadge extends StatelessWidget {
  final int count;

  const _CountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 28),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: _accent,
        ),
      ),
    );
  }
}

class _ComplaintTile extends StatelessWidget {
  final String propertyId;
  final Map<String, dynamic> complaint;
  final List<Map<String, dynamic>> tenancies;

  const _ComplaintTile({
    required this.propertyId,
    required this.complaint,
    required this.tenancies,
  });

  @override
  Widget build(BuildContext context) {
    final style = _categoryStyle(_category(complaint));
    final description = _description(complaint);
    final tenant = _tenantName(complaint, tenancies);
    final room = _roomLabel(complaint, tenancies);
    final reported = _reportedLabel(complaint);
    final location = [
      if (tenant.isNotEmpty) tenant,
      if (room.isNotEmpty && room != '—') room,
    ].join(' · ');

    return ListTile(
      onTap: () => showDialog<void>(
        context: context,
        useRootNavigator: true,
        builder: (_) => ComplaintDetailDialog(
          propertyId: propertyId,
          complaint: complaint,
          tenancies: tenancies,
        ),
      ),
      contentPadding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      leading: CircleAvatar(
        backgroundColor: style.bg,
        child: Icon(style.icon, color: style.color, size: 20),
      ),
      title: Text(
        description,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
          fontSize: 14,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          [if (location.isNotEmpty) location, reported].join('\n'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12,
            height: 1.35,
            color: AppColors.slate,
          ),
        ),
      ),
      isThreeLine: true,
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: AppColors.slate,
      ),
    );
  }
}

class ComplaintDetailDialog extends ConsumerStatefulWidget {
  final String propertyId;
  final Map<String, dynamic> complaint;
  final List<Map<String, dynamic>> tenancies;

  const ComplaintDetailDialog({
    super.key,
    required this.propertyId,
    required this.complaint,
    required this.tenancies,
  });

  @override
  ConsumerState<ComplaintDetailDialog> createState() =>
      _ComplaintDetailDialogState();
}

class _ComplaintDetailDialogState extends ConsumerState<ComplaintDetailDialog> {
  bool _resolving = false;

  void _forwardJob() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Job forwarded to technician')),
    );
  }

  Future<void> _resolve() async {
    if (_resolving) return;
    final id = (widget.complaint['id'] ?? '').toString();
    if (id.isEmpty) return;

    setState(() => _resolving = true);
    try {
      await ref.read(complaintsRepositoryProvider).updateStatus(
            widget.propertyId,
            id,
            'resolved',
          );
      if (!mounted) return;

      final notes = _expenseNotes();
      ref.invalidate(complaintsProvider(widget.propertyId));
      ref.invalidate(propertyDashboardProvider(widget.propertyId));

      final addExpense = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          title: const Text('Marked as Resolved!'),
          content: const Text('Did this repair cost money?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: _accent),
              child: const Text('Yes, Add Expense'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (addExpense == true) {
        await showAddExpenseSheet(
          context: context,
          ref: ref,
          propertyId: widget.propertyId,
          initialNotes: notes,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not mark as resolved: $e')),
      );
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  String? _expenseNotes() {
    final description = _description(widget.complaint);
    final room = _roomLabel(widget.complaint, widget.tenancies);
    if (description.isEmpty) return null;
    if (room.isEmpty || room == '—') return description;
    return '$description — $room';
  }

  void _openFullScreenImage(String url) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _FullScreenComplaintImage(url: url),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.complaint;
    final style = _categoryStyle(_category(c));
    final title = _dialogTitle(c);
    final tenant = _tenantName(c, widget.tenancies);
    final room = _roomLabel(c, widget.tenancies);
    final description = _description(c);
    final imageUrl = _complaintImageUrl(c);
    final location = [
      if (tenant.isNotEmpty) tenant,
      if (room.isNotEmpty && room != '—') room,
    ].join(' · ');

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 420,
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: style.bg,
                    child: Icon(style.icon, color: style.color, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                        if (location.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            location,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.slate,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: AppColors.slate),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.48,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ComplaintImageSection(
                        imageUrl: imageUrl,
                        onOpen: imageUrl == null
                            ? null
                            : () => _openFullScreenImage(imageUrl),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Description',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.slate,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        description,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.45,
                          color: AppColors.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _forwardJob,
                icon: const Icon(Icons.chat, color: whatsAppGreen, size: 18),
                label: const Text('Forward to Technician'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.ink,
                  side: const BorderSide(color: AppColors.hairline),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _resolving ? null : _resolve,
                icon: _resolving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_circle_outline, size: 18),
                label: Text(_resolving ? 'Resolving…' : 'Mark Resolved'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.positive,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComplaintImageSection extends StatelessWidget {
  final String? imageUrl;
  final VoidCallback? onOpen;

  const _ComplaintImageSection({
    required this.imageUrl,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Material(
        color: const Color(0xFFF3F4F6),
        child: InkWell(
          onTap: imageUrl == null ? null : onOpen,
          child: SizedBox(
            height: 180,
            width: double.infinity,
            child: imageUrl == null
                ? const _NoImageAttached()
                : Image.network(
                    imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const _NoImageAttached(),
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _accent,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

class _NoImageAttached extends StatelessWidget {
  const _NoImageAttached();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFFF3F4F6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_outlined, color: AppColors.slate, size: 32),
          SizedBox(height: 8),
          Text(
            'No image attached',
            style: TextStyle(
              color: AppColors.slate,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _FullScreenComplaintImage extends StatelessWidget {
  final String url;

  const _FullScreenComplaintImage({required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 4,
          child: Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Could not load image',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryStyle {
  final IconData icon;
  final Color color;
  final Color bg;

  const _CategoryStyle({
    required this.icon,
    required this.color,
    required this.bg,
  });
}

bool _isOpenComplaint(Map<String, dynamic> c) {
  final status = (c['status'] ?? 'open').toString().toLowerCase();
  return status == 'open' || status == 'in_progress';
}

String _category(Map<String, dynamic> c) =>
    (c['category'] ?? '').toString().trim();

String _description(Map<String, dynamic> c) {
  final description = (c['description'] ?? '').toString().trim();
  if (description.isNotEmpty) return description;
  final category = _category(c);
  return category.isEmpty ? 'Maintenance request' : category;
}

String _dialogTitle(Map<String, dynamic> c) {
  final category = _category(c);
  if (category.isNotEmpty) return category;
  return 'Maintenance request';
}

const _apiBase = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://dormly-backend.onrender.com',
);

String? _complaintImageUrl(Map<String, dynamic> c) {
  for (final key in [
    'image_url',
    'imageUrl',
    'attachment_url',
    'attachmentUrl',
    'photo_url',
    'photoUrl',
  ]) {
    final raw = c[key]?.toString().trim();
    if (raw == null || raw.isEmpty) continue;
    if (raw.startsWith('http')) return raw;
    if (raw.startsWith('/')) return '$_apiBase$raw';
    return raw;
  }
  return _mockImageForCategory(_category(c));
}

/// Category-matched Unsplash preview when the complaint has no uploaded photo.
String _mockImageForCategory(String category) {
  final c = category.toLowerCase();
  if (c.contains('plumb') ||
      c.contains('tap') ||
      c.contains('water') ||
      c.contains('leak') ||
      c.contains('pipe')) {
    return 'https://images.unsplash.com/photo-1585704032915-c3400ca199c7?auto=format&fit=crop&w=1200&q=80';
  }
  if (c.contains('ac') ||
      c.contains('cool') ||
      c.contains('hvac') ||
      c.contains('air')) {
    return 'https://images.unsplash.com/photo-1581276879432-15e50529f34b?auto=format&fit=crop&w=1200&q=80';
  }
  if (c.contains('electr') ||
      c.contains('light') ||
      c.contains('wiring') ||
      c.contains('power')) {
    return 'https://images.unsplash.com/photo-1473341304170-971dccb5ac1e?auto=format&fit=crop&w=1200&q=80';
  }
  return 'https://images.unsplash.com/photo-1581578731548-c64695cc6952?auto=format&fit=crop&w=1200&q=80';
}

String _roomLabel(
  Map<String, dynamic> c,
  List<Map<String, dynamic>> tenancies,
) {
  final fromComplaint = (c['node_name'] ?? c['nodeName'] ?? c['room'])
      ?.toString()
      .trim();
  if (fromComplaint != null && fromComplaint.isNotEmpty) return fromComplaint;

  final nodeId = (c['node_id'] ?? c['nodeId'])?.toString();
  if (nodeId == null || nodeId.isEmpty) return '—';
  for (final t in tenancies) {
    final tid = (t['node_id'] ?? t['nodeId'])?.toString();
    if (tid != nodeId) continue;
    final room = (t['node_name'] ?? t['nodeName'] ?? t['room'])?.toString().trim();
    if (room != null && room.isNotEmpty) return room;
  }
  return '—';
}

String _tenantName(
  Map<String, dynamic> c,
  List<Map<String, dynamic>> tenancies,
) {
  for (final key in [
    'tenant_name',
    'tenantName',
    'full_name',
    'fullName',
    'raised_by_name',
    'raisedByName',
  ]) {
    final value = c[key]?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
  }

  final nodeId = (c['node_id'] ?? c['nodeId'])?.toString();
  final raisedBy = (c['raised_by'] ?? c['raisedBy'])?.toString();
  String? byUser;
  for (final t in tenancies) {
    final status = (t['status'] ?? 'active').toString().toLowerCase();
    if (status != 'active' && status != 'pending') continue;
    final name =
        (t['full_name'] ?? t['fullName'] ?? t['name'])?.toString().trim();
    if (name == null || name.isEmpty) continue;
    final tid = (t['node_id'] ?? t['nodeId'])?.toString();
    if (nodeId != null && tid == nodeId) return name;
    final uid = (t['user_id'] ?? t['userId'])?.toString();
    if (raisedBy != null && uid == raisedBy) byUser = name;
  }
  return byUser ?? 'Tenant';
}

String _reportedLabel(Map<String, dynamic> c) {
  final raw = c['created_at'] ?? c['createdAt'];
  if (raw == null) return 'Reported recently';
  final date = DateTime.tryParse(raw.toString())?.toLocal();
  if (date == null) return 'Reported recently';

  final diff = DateTime.now().difference(date);
  if (diff.inMinutes < 1) return 'Reported just now';
  if (diff.inMinutes < 60) {
    final n = diff.inMinutes;
    return 'Reported $n min ago';
  }
  if (diff.inHours < 24) {
    final n = diff.inHours;
    return n == 1 ? 'Reported 1 hour ago' : 'Reported $n hours ago';
  }
  final n = diff.inDays;
  if (n == 1) return 'Reported 1 day ago';
  if (n < 30) return 'Reported $n days ago';
  final months = (n / 30).floor();
  if (months == 1) return 'Reported 1 month ago';
  return 'Reported $months months ago';
}

_CategoryStyle _categoryStyle(String category) {
  final c = category.toLowerCase();
  if (c.contains('plumb') ||
      c.contains('tap') ||
      c.contains('water') ||
      c.contains('leak') ||
      c.contains('pipe')) {
    return const _CategoryStyle(
      icon: Icons.plumbing,
      color: Color(0xFF0284C7),
      bg: Color(0xFFE0F2FE),
    );
  }
  if (c.contains('electr') ||
      c.contains('light') ||
      c.contains('wiring') ||
      c.contains('power') ||
      c.contains('socket')) {
    return const _CategoryStyle(
      icon: Icons.electrical_services,
      color: Color(0xFFD97706),
      bg: Color(0xFFFEF3C7),
    );
  }
  if (c.contains('clean') || c.contains('housekeep') || c.contains('hygiene')) {
    return const _CategoryStyle(
      icon: Icons.cleaning_services,
      color: Color(0xFF0D9488),
      bg: Color(0xFFCCFBF1),
    );
  }
  if (c.contains('ac') ||
      c.contains('cool') ||
      c.contains('hvac') ||
      c.contains('air')) {
    return const _CategoryStyle(
      icon: Icons.ac_unit,
      color: Color(0xFF2563EB),
      bg: Color(0xFFDBEAFE),
    );
  }
  if (c.contains('wifi') ||
      c.contains('internet') ||
      c.contains('network') ||
      c.contains('router')) {
    return const _CategoryStyle(
      icon: Icons.wifi,
      color: _accent,
      bg: AppColors.primarySoft,
    );
  }
  if (c.contains('carpent') ||
      c.contains('wood') ||
      c.contains('door') ||
      c.contains('furniture')) {
    return const _CategoryStyle(
      icon: Icons.chair_outlined,
      color: Color(0xFFB45309),
      bg: Color(0xFFFED7AA),
    );
  }
  return const _CategoryStyle(
    icon: Icons.handyman_outlined,
    color: Color(0xFFEA580C),
    bg: Color(0xFFFFEDD5),
  );
}
