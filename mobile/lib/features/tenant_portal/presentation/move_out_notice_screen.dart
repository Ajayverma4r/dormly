// features/tenant_portal/presentation/move_out_notice_screen.dart
//
// Screen 12 — approved/pending move-out tracker with milestones.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

const _brand = Color(0xFF6D28D9);
const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _bg = Color(0xFFF8FAFC);
const _success = Color(0xFF10B981);

final _dFmt = DateFormat('d MMM yyyy');
final _dtFmt = DateFormat('d MMM yyyy, h:mm a');

class MoveOutNoticeScreen extends StatelessWidget {
  final Map<String, dynamic> tenancy;

  const MoveOutNoticeScreen({super.key, required this.tenancy});

  @override
  Widget build(BuildContext context) {
    final status = tenancy['move_out_request_status']?.toString() ?? '';
    final approved = status == 'approved' ||
        status == 'modified_by_mutual_agreement';
    final pending = status == 'pending';
    final proposed = DateTime.tryParse(
      (tenancy['planned_move_out_at'] ?? tenancy['plannedMoveOutAt'])
              ?.toString() ??
          '',
    );
    final submitted = DateTime.tryParse(
      (tenancy['notice_given_at'] ?? tenancy['noticeGivenAt'])?.toString() ??
          '',
    );
    final updated = DateTime.tryParse(
      tenancy['updated_at']?.toString() ?? '',
    );
    final dateLabel =
        proposed == null ? '—' : _dFmt.format(proposed.toLocal());
    final days = proposed == null
        ? null
        : proposed.toLocal().difference(DateTime.now()).inDays;
    final ownerPhone = tenancy['owner_phone']?.toString();

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        foregroundColor: _ink,
        title: const Text(
          'Move-Out Notice',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: approved
                  ? const Color(0xFFD1FAE5)
                  : pending
                      ? const Color(0xFFFEF3C7)
                      : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(
                  approved ? Icons.check_circle : Icons.schedule,
                  color: approved ? _success : const Color(0xFFD97706),
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        approved
                            ? 'Move-Out Approved'
                            : pending
                                ? 'Move-Out Pending'
                                : 'No Active Request',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: approved
                              ? const Color(0xFF065F46)
                              : const Color(0xFF92400E),
                        ),
                      ),
                      Text(
                        days == null
                            ? 'for $dateLabel'
                            : days >= 0
                                ? 'for $dateLabel • $days days remaining'
                                : 'for $dateLabel',
                        style: TextStyle(
                          fontSize: 13,
                          color: approved
                              ? const Color(0xFF047857)
                              : const Color(0xFFB45309),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _Milestone(
            title: 'Request Submitted',
            subtitle: submitted == null
                ? '—'
                : _dtFmt.format(submitted.toLocal()),
            state: submitted != null ? 0 : 2,
            showLine: true,
          ),
          _Milestone(
            title: 'Approved by Owner',
            subtitle: approved
                ? (updated == null
                    ? 'Approved'
                    : _dtFmt.format(updated.toLocal()))
                : pending
                    ? 'Awaiting owner review'
                    : 'Pending',
            state: approved ? 0 : (pending ? 1 : 2),
            showLine: true,
            green: true,
          ),
          _Milestone(
            title: 'Move-Out Date',
            subtitle: dateLabel,
            state: approved ? 1 : 2,
            showLine: true,
          ),
          const _Milestone(
            title: 'Complete',
            subtitle: 'Pending checkout settlement',
            state: 2,
            showLine: false,
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              approved
                  ? 'Your move-out for $dateLabel is confirmed. Please clear dues and complete handover with the owner before the exit date.'
                  : pending
                      ? 'Your notice is with the owner. You will be notified once they approve or propose a new date.'
                      : 'Submit a move-out request from Home → Quick Actions when you are ready to leave.',
              style: const TextStyle(
                color: Color(0xFF1E3A8A),
                height: 1.4,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              onPressed: () async {
                final digits = (ownerPhone ?? '').replaceAll(RegExp(r'\D'), '');
                if (digits.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Owner phone not available.'),
                    ),
                  );
                  return;
                }
                await launchUrl(Uri(scheme: 'tel', path: digits));
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: _brand,
                side: const BorderSide(color: _brand),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.headset_mic_outlined),
              label: const Text(
                'Contact Support',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Milestone extends StatelessWidget {
  final String title;
  final String subtitle;
  final int state; // 0 done, 1 active, 2 pending
  final bool showLine;
  final bool green;

  const _Milestone({
    required this.title,
    required this.subtitle,
    required this.state,
    required this.showLine,
    this.green = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = green && state == 0 ? _success : _brand;
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
                color: done ? color : Colors.transparent,
                border: Border.all(
                  color: done || active ? color : const Color(0xFFCBD5E1),
                  width: 2.2,
                ),
              ),
              child: done
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : active
                      ? Center(
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                        )
                      : null,
            ),
            if (showLine)
              Container(
                width: 2,
                height: 40,
                color: done
                    ? color.withValues(alpha: 0.4)
                    : const Color(0xFFE2E8F0),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 20),
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
                  style: const TextStyle(fontSize: 12.5, color: _muted),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
