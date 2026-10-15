// features/staff_home/presentation/staff_gate_passes_screen.dart
//
// Visitor gate passes for the property team. The server lets staff list and
// approve/deny (requirePropertyTeam); a 403 is shown as a friendly message.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../gate_passes/data/gate_passes_repository.dart';
import '../../properties/domain/property_archetype.dart';
import 'staff_ui.dart';

enum GatePassTab { pending, approved, rejected }

GatePassTab gatePassTabOf(Map<String, dynamic> pass) {
  switch (pass['status']?.toString().toLowerCase() ?? 'pending') {
    case 'pending':
      return GatePassTab.pending;
    case 'approved':
      return GatePassTab.approved;
    default:
      return GatePassTab.rejected;
  }
}

final _when = DateFormat('d MMM, h:mm a');

String? _formatTime(Object? raw) {
  final d = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
  return d == null ? null : _when.format(d);
}

class StaffGatePassesScreen extends ConsumerStatefulWidget {
  final String propertyId;
  final bool asTab;

  const StaffGatePassesScreen(
      {super.key, required this.propertyId, this.asTab = false});

  @override
  ConsumerState<StaffGatePassesScreen> createState() =>
      _StaffGatePassesScreenState();
}

class _StaffGatePassesScreenState extends ConsumerState<StaffGatePassesScreen> {
  GatePassTab _tab = GatePassTab.pending;
  final Set<String> _busy = {};

  Future<void> _refresh() async {
    await ref
        .refresh(staffGatePassesProvider(widget.propertyId).future)
        .then<void>((_) {}, onError: (_) {});
  }

  Future<void> _decide(Map<String, dynamic> pass, bool approve) async {
    final id = pass['id']?.toString() ?? '';
    if (id.isEmpty || _busy.contains(id)) return;

    if (!approve) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Reject gate pass?'),
          content: Text(
            'The resident will be told that ${pass['visitor_name'] ?? 'this visitor'} was not approved.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style:
                  FilledButton.styleFrom(backgroundColor: StaffColors.danger),
              child: const Text('Reject'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }

    setState(() => _busy.add(id));
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(gatePassesRepositoryProvider)
          .decide(widget.propertyId, id, approve ? 'approved' : 'denied');
      ref.invalidate(staffGatePassesProvider(widget.propertyId));
      messenger.showSnackBar(
        SnackBar(
            content:
                Text(approve ? 'Gate pass approved' : 'Gate pass rejected')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            staffErrorMessage(e,
                fallback: 'Could not update the gate pass. Please try again.'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final archetype = staffPropertyArchetype(ref, widget.propertyId);
    final appBar = StaffAppBar(title: 'Gate Passes', showBack: !widget.asTab);

    if (archetype != null && !archetype.showsGatePass) {
      return Scaffold(
        backgroundColor: StaffColors.bg,
        appBar: appBar,
        body: const StaffMessage(
          key: Key('staff-gate-passes-unsupported'),
          icon: Icons.badge_outlined,
          title: 'Gate passes are not used here',
          subtitle:
              'Visitor gate passes are available for gated communities and societies.',
        ),
      );
    }

    final async = ref.watch(staffGatePassesProvider(widget.propertyId));

    return Scaffold(
      backgroundColor: StaffColors.bg,
      appBar: appBar,
      body: RefreshIndicator(
        color: StaffColors.brand,
        onRefresh: _refresh,
        child: async.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: StaffColors.brand)),
          error: (e, _) => StaffScrollableMessage(
            child: StaffErrorState(
              key: const Key('staff-gate-passes-error'),
              error: e,
              fallback: "Couldn't load gate passes. Please try again.",
              onRetry: () =>
                  ref.invalidate(staffGatePassesProvider(widget.propertyId)),
            ),
          ),
          data: (all) {
            final counts = {for (final t in GatePassTab.values) t: 0};
            for (final p in all) {
              counts[gatePassTabOf(p)] = counts[gatePassTabOf(p)]! + 1;
            }
            final visible = all.where((p) => gatePassTabOf(p) == _tab).toList();

            return ListView(
              key: const Key('staff-gate-passes-list'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: staffCardDecoration(radius: 14),
                  child: Row(
                    children: [
                      for (final t in GatePassTab.values)
                        Expanded(
                          child: _Segment(
                            key: Key('gate-pass-tab-${t.name}'),
                            label: switch (t) {
                              GatePassTab.pending => 'Pending',
                              GatePassTab.approved => 'Approved',
                              GatePassTab.rejected => 'Rejected',
                            },
                            count: counts[t]!,
                            selected: _tab == t,
                            onTap: () => setState(() => _tab = t),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (visible.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 48),
                    child: StaffMessage(
                      key: const Key('staff-gate-passes-empty'),
                      icon: Icons.badge_outlined,
                      title: switch (_tab) {
                        GatePassTab.pending => 'No pending gate passes',
                        GatePassTab.approved => 'No approved gate passes',
                        GatePassTab.rejected => 'No rejected gate passes',
                      },
                      subtitle: _tab == GatePassTab.pending
                          ? 'Visitor requests from residents will appear here for approval.'
                          : null,
                    ),
                  )
                else
                  for (final p in visible) ...[
                    _GatePassCard(
                      pass: p,
                      busy: _busy.contains(p['id']?.toString()),
                      onApprove: () => _decide(p, true),
                      onReject: () => _decide(p, false),
                    ),
                    const SizedBox(height: 10),
                  ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _Segment({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? StaffColors.brand : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Text(
            '$label ($count)',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? Colors.white : StaffColors.ink,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _GatePassCard extends StatelessWidget {
  final Map<String, dynamic> pass;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _GatePassCard({
    required this.pass,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final p = pass;
    final tab = gatePassTabOf(p);
    final visitor = p['visitor_name']?.toString().trim() ?? '';
    final purpose = p['purpose']?.toString().trim() ?? '';
    final notes = p['notes']?.toString().trim() ?? '';
    final unit = p['unit_name']?.toString().trim() ?? '';
    final requester = p['requested_by_name']?.toString().trim() ?? '';
    final created = _formatTime(p['created_at']);
    final validUntil = _formatTime(p['valid_until']);
    final decided = _formatTime(p['decided_at']);
    final status = p['status']?.toString().toLowerCase() ?? 'pending';
    final (statusLabel, fg, bg) = switch (status) {
      'pending' => ('Pending', StaffColors.warning, StaffColors.warningSoft),
      'approved' => ('Approved', StaffColors.success, StaffColors.successSoft),
      'expired' => ('Expired', StaffColors.muted, const Color(0xFFF1F5F9)),
      _ => ('Rejected', StaffColors.danger, StaffColors.dangerSoft),
    };

    return Container(
      key: Key('gate-pass-${p['id']}'),
      decoration: staffCardDecoration(),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: StaffColors.brandSoft,
                child: Text(
                  initialOf(visitor),
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
                      visitor.isEmpty ? 'Visitor' : visitor,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: StaffColors.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w700),
                    ),
                    if (purpose.isNotEmpty)
                      Text(
                        purpose[0].toUpperCase() + purpose.substring(1),
                        style: const TextStyle(
                            color: StaffColors.muted, fontSize: 12.5),
                      ),
                  ],
                ),
              ),
              StaffPill(label: statusLabel, fg: fg, bg: bg),
            ],
          ),
          const SizedBox(height: 10),
          if (unit.isNotEmpty) _InfoLine(icon: Icons.home_outlined, text: unit),
          if (requester.isNotEmpty)
            _InfoLine(
                icon: Icons.person_outline_rounded,
                text: 'Requested by $requester'),
          if (created != null)
            _InfoLine(icon: Icons.schedule_rounded, text: 'Requested $created'),
          if (validUntil != null)
            _InfoLine(
                icon: Icons.event_available_outlined,
                text: 'Valid until $validUntil'),
          if (tab != GatePassTab.pending && decided != null)
            _InfoLine(icon: Icons.done_all_rounded, text: 'Decided $decided'),
          if (notes.isNotEmpty)
            _InfoLine(icon: Icons.notes_rounded, text: notes),
          if (tab == GatePassTab.pending) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: Key('gate-pass-reject-${p['id']}'),
                    onPressed: busy ? null : onReject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: StaffColors.danger,
                      side: const BorderSide(color: StaffColors.dangerSoft),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    key: Key('gate-pass-approve-${p['id']}'),
                    onPressed: busy ? null : onApprove,
                    style: FilledButton.styleFrom(
                      backgroundColor: StaffColors.brand,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Approve'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: StaffColors.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: const TextStyle(color: StaffColors.ink, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}
