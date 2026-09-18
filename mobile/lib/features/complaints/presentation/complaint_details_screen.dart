// features/complaints/presentation/complaint_details_screen.dart
//
// Screen 9 — ticket header, status card, vertical tracker, add reply.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/network/api_config.dart';

const _brand = Color(0xFF6D28D9);
const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _bg = Color(0xFFF8FAFC);
const _border = Color(0xFFE2E8F0);

final _dtFmt = DateFormat('d MMM yyyy, h:mm a');

class ComplaintDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> complaint;

  const ComplaintDetailsScreen({super.key, required this.complaint});

  @override
  State<ComplaintDetailsScreen> createState() => _ComplaintDetailsScreenState();
}

class _ComplaintDetailsScreenState extends State<ComplaintDetailsScreen> {
  final _replyController = TextEditingController();

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.complaint;
    final title = c['category']?.toString() ?? 'Complaint';
    final desc = c['description']?.toString() ?? '';
    final id = c['id']?.toString() ?? '';
    final ticket = c['ticket_number']?.toString() ??
        (id.length >= 8
            ? 'CMP-${id.substring(0, 8).toUpperCase()}'
            : id.toUpperCase());
    final shortId = ticket;
    final status = c['status']?.toString() ?? 'open';
    final created = DateTime.tryParse(c['created_at']?.toString() ?? '');
    final updated = DateTime.tryParse(c['updated_at']?.toString() ?? '');
    final resolved = DateTime.tryParse(c['resolved_at']?.toString() ?? '');
    final photos = <String>[];
    final rawPhotos = c['photo_urls'] ?? c['photoUrls'];
    final base = resolveApiBaseUrl();
    if (rawPhotos is List) {
      for (final p in rawPhotos) {
        final s = p?.toString().trim();
        if (s == null || s.isEmpty) continue;
        photos.add(s.startsWith('http') ? s : '$base$s');
      }
    }

    final steps = _buildSteps(status, created, updated, resolved);
    final (statusLabel, statusSub) = _statusCopy(status);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        foregroundColor: _ink,
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3E8FF),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.desktop_windows_outlined,
                          color: _brand),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: _ink,
                            ),
                          ),
                          Text(
                            'Ticket #$shortId',
                            style: const TextStyle(
                              fontSize: 13,
                              color: _muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(desc, style: const TextStyle(color: _muted, height: 1.4)),
                ],
                if (photos.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 88,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: photos.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final url = photos[i];
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            url,
                            width: 88,
                            height: 88,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 88,
                              height: 88,
                              color: const Color(0xFFF1F5F9),
                              child: const Icon(Icons.broken_image_outlined),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3E8FF),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        statusLabel,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: _brand,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        statusSub,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF5B21B6),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Status Tracker',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 14),
                ...List.generate(steps.length, (i) {
                  final step = steps[i];
                  final isLast = i == steps.length - 1;
                  return _TrackerStep(
                    title: step.$1,
                    subtitle: step.$2,
                    state: step.$3,
                    showLine: !isLast,
                  );
                }),
                if ((c['resolution_note']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _border),
                    ),
                    child: Text(
                      'Note: ${c['resolution_note']}',
                      style: const TextStyle(color: _muted, height: 1.4),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () => _openReply(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _brand,
                    side: const BorderSide(color: _brand),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: const Text(
                    'Add a Reply',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openReply(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            16 + MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Add a Reply',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _replyController,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Write an update for the technician…',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Reply saved locally. Live replies coming soon.',
                      ),
                    ),
                  );
                  _replyController.clear();
                },
                style: FilledButton.styleFrom(backgroundColor: _brand),
                child: const Text('Send'),
              ),
            ],
          ),
        );
      },
    );
  }

  /// state: 0 done, 1 active, 2 pending
  List<(String, String, int)> _buildSteps(
    String status,
    DateTime? created,
    DateTime? updated,
    DateTime? resolved,
  ) {
    final s = status.toLowerCase();
    final raisedAt =
        created == null ? '—' : _dtFmt.format(created.toLocal());
    final assignedAt =
        updated == null ? raisedAt : _dtFmt.format(updated.toLocal());
    final resolvedAt =
        resolved == null ? '—' : _dtFmt.format(resolved.toLocal());

    if (s == 'resolved' || s == 'closed') {
      return [
        ('Complaint Raised', raisedAt, 0),
        ('Technician Assigned', assignedAt, 0),
        ('In Progress', assignedAt, 0),
        ('Resolved', resolvedAt, 0),
      ];
    }
    if (s == 'in_progress') {
      return [
        ('Complaint Raised', raisedAt, 0),
        ('Technician Assigned', assignedAt, 0),
        ('In Progress', 'In progress now', 1),
        ('Resolved', 'Pending', 2),
      ];
    }
    if (s == 'assigned') {
      return [
        ('Complaint Raised', raisedAt, 0),
        ('Technician Assigned', assignedAt, 0),
        ('In Progress', 'Pending', 2),
        ('Resolved', 'Pending', 2),
      ];
    }
    // open / default
    return [
      ('Complaint Raised', raisedAt, 0),
      ('Technician Assigned', 'Pending', 1),
      ('In Progress', 'Pending', 2),
      ('Resolved', 'Pending', 2),
    ];
  }

  (String, String) _statusCopy(String status) {
    switch (status.toLowerCase()) {
      case 'resolved':
        return (
          'Resolved',
          'This issue has been marked as resolved.',
        );
      case 'closed':
        return ('Closed', 'This complaint is closed.');
      case 'in_progress':
        return (
          'In Progress',
          'Our team is actively working on this issue.',
        );
      case 'assigned':
        return (
          'Technician Assigned',
          'Our technician has been assigned and will visit soon.',
        );
      default:
        return (
          'Complaint Raised',
          'We have received your complaint and will assign a technician shortly.',
        );
    }
  }
}

class _TrackerStep extends StatelessWidget {
  final String title;
  final String subtitle;
  final int state; // 0 done, 1 active, 2 pending
  final bool showLine;

  const _TrackerStep({
    required this.title,
    required this.subtitle,
    required this.state,
    required this.showLine,
  });

  @override
  Widget build(BuildContext context) {
    final done = state == 0;
    final active = state == 1;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? _brand : Colors.transparent,
                border: Border.all(
                  color: done || active ? _brand : const Color(0xFFCBD5E1),
                  width: 2,
                ),
              ),
              child: done
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : active
                      ? Center(
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: _brand,
                              shape: BoxShape.circle,
                            ),
                          ),
                        )
                      : null,
            ),
            if (showLine)
              Container(
                width: 2,
                height: 36,
                color: done
                    ? _brand.withValues(alpha: 0.45)
                    : const Color(0xFFE2E8F0),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: done || active ? _ink : _muted,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: _muted),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
