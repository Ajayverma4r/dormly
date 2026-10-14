// features/complaints/presentation/complaint_details_screen.dart
//
// Full complaint view shared by owners, staff and tenants. Only fields the API
// returns are shown; Edit (status + resolution note) is limited to the roles
// the backend lets update complaints. Assigned To and comments appear only
// when the server provides them; tenants get an "assigned" flag, never names.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/complaints_repository.dart';
import '../../structure/presentation/property_shell_screen.dart' show propertyDetailProvider;
import '../../tenant_portal/presentation/tenant_portal_providers.dart' show myTenancyProvider;
import 'complaint_ui.dart';
import 'complaints_list_screen.dart' show complaintsProvider;

/// Longer descriptions get a short headline plus the full text below.
const _headlineLimit = 80;

class ComplaintDetailsScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> complaint;
  final String? propertyName;
  final String? propertyAddress;

  const ComplaintDetailsScreen({
    super.key,
    required this.complaint,
    this.propertyName,
    this.propertyAddress,
  });

  @override
  ConsumerState<ComplaintDetailsScreen> createState() => _ComplaintDetailsScreenState();
}

class _ComplaintDetailsScreenState extends ConsumerState<ComplaintDetailsScreen> {
  late Map<String, dynamic> _c = Map<String, dynamic>.from(widget.complaint);

  String? get _propertyId => _c['property_id']?.toString();

  Future<void> _edit() async {
    final propertyId = _propertyId;
    if (propertyId == null || propertyId.isEmpty) return;
    final updated = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _EditComplaintSheet(propertyId: propertyId, complaint: _c),
    );
    if (updated == null || !mounted) return;
    setState(() => _c = updated);
    ref.invalidate(complaintsProvider(propertyId));
  }

  (String, String)? get _commentsKey {
    final propertyId = _propertyId;
    final id = _c['id']?.toString();
    if (propertyId == null || propertyId.isEmpty || id == null || id.isEmpty) return null;
    return (propertyId, id);
  }

  Future<void> _changeAssignee() async {
    final key = _commentsKey;
    if (key == null) return;
    final updated = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AssignSheet(propertyId: key.$1, complaint: _c),
    );
    if (updated == null || !mounted) return;
    setState(() => _c = {..._c, ...updated});
    ref.invalidate(complaintsProvider(key.$1));
    ref.invalidate(complaintCommentsProvider(key));
  }

  Future<void> _addComment(bool asTeam) async {
    final key = _commentsKey;
    if (key == null) return;
    final posted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CommentSheet(propertyId: key.$1, complaintId: key.$2, asTeam: asTeam),
    );
    if (posted == true && mounted) ref.invalidate(complaintCommentsProvider(key));
  }

  /// Caller-supplied property info first; otherwise the already-authorized
  /// source for the viewer's role, used only if it is the complaint's property.
  ComplaintProperty? _property(String? role) {
    final name = widget.propertyName?.trim() ?? '';
    final address = widget.propertyAddress?.trim() ?? '';
    if (name.isNotEmpty || address.isNotEmpty) return ComplaintProperty(name, address);

    final propertyId = _propertyId;
    if (propertyId == null || propertyId.isEmpty) return null;
    if (role == 'tenant') {
      return complaintPropertyFrom(
        ref.watch(myTenancyProvider).valueOrNull,
        propertyId,
        idKey: 'property_id',
        nameKey: 'property_name',
        addressKey: 'property_address',
        cityKey: 'property_city',
      );
    }
    if (canEditComplaints(role)) {
      return complaintPropertyFrom(
        ref.watch(propertyDetailProvider(propertyId)).valueOrNull,
        propertyId,
      );
    }
    return null;
  }

  void _preview(List<String> photos, int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _PhotoPreview(photos: photos, initialIndex: index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final status = complaintStatusOf(c);
    final created = complaintCreatedAt(c);
    final updated = complaintUpdatedAt(c);
    final description = complaintDescriptionOf(c);
    final category = complaintCategoryOf(c);
    final fullTitle = complaintTitle(c);
    final titleChars = fullTitle.characters;
    final truncated = titleChars.length > _headlineLimit;
    final headline = truncated
        ? '${titleChars.take(_headlineLimit).toString().trimRight()}…'
        : fullTitle;
    final role = ref.watch(complaintViewerRoleProvider).valueOrNull;
    final property = _property(role);
    final propertyName = property?.name ?? '';
    final room = complaintRoomOf(c);
    final location = [
      if (room.isNotEmpty) room,
      if (propertyName.isNotEmpty) propertyName,
    ].join(' · ');
    final address = property?.address ?? '';
    final photos = complaintPhotoUrls(c);
    final priority = complaintPriorityStyle(c['priority']?.toString());
    final ticket = c['ticket_number']?.toString().trim() ?? '';
    final note = c['resolution_note']?.toString().trim() ?? '';
    final isTeam = canEditComplaints(role);
    final isTenant = role == 'tenant';
    final commentsKey = _commentsKey;
    final canEdit = isTeam && commentsKey != null;
    final commentsAsync = (isTeam || isTenant) && commentsKey != null
        ? ref.watch(complaintCommentsProvider(commentsKey))
        : null;
    final comments = commentsAsync?.valueOrNull;
    final canComment = comments != null;
    // The list endpoints only include these keys once assignment is available.
    final showAssignee =
        isTeam ? c.containsKey('assigned_to') : isTenant && c.containsKey('is_assigned');
    final canAssign =
        canAssignComplaints(role) && c.containsKey('assigned_to') && commentsKey != null;

    final activity = <(DateTime, Widget)>[
      (
        created ?? DateTime.fromMillisecondsSinceEpoch(0),
        _ActivityEntry(
          title: 'Complaint raised',
          when: created == null ? null : formatComplaintDayTime(created),
        ),
      ),
      if (status != 'open' && updated != null)
        (
          updated,
          _ActivityEntry(
            title: 'Marked ${complaintStatusStyle(status).label}',
            when: formatComplaintDayTime(updated),
          ),
        ),
      for (final e in comments ?? const <Map<String, dynamic>>[])
        (
          DateTime.tryParse(e['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
          _CommentEntry(entry: e, asTeam: isTeam),
        ),
    ];
    final ordered = [for (var i = 0; i < activity.length; i++) (i, activity[i])]
      ..sort((a, b) {
        final byTime = a.$2.$1.compareTo(b.$2.$1);
        return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
      });

    return Scaffold(
      backgroundColor: ComplaintColors.bg,
      appBar: AppBar(
        backgroundColor: ComplaintColors.bg,
        foregroundColor: ComplaintColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Complaint Details',
          style: TextStyle(
            color: ComplaintColors.ink,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                _Card(
                  children: [
                    Row(
                      children: [
                        ComplaintStatusBadge(
                          key: const Key('complaint-detail-status'),
                          status: status,
                          withIcon: true,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            created == null ? '' : formatComplaintDayTime(created),
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: ComplaintColors.muted, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      headline,
                      key: const Key('complaint-detail-title'),
                      style: const TextStyle(
                        color: ComplaintColors.ink,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                    if (location.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        location,
                        style: const TextStyle(
                          color: ComplaintColors.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (address.isNotEmpty)
                      Text(
                        address,
                        style: const TextStyle(color: ComplaintColors.muted, fontSize: 12.5),
                      ),
                    if (truncated && description.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        description,
                        key: const Key('complaint-detail-description'),
                        style: const TextStyle(
                          color: ComplaintColors.ink,
                          fontSize: 14,
                          height: 1.45,
                        ),
                      ),
                    ],
                    if (photos.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 92,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: photos.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, i) => GestureDetector(
                            key: Key('complaint-photo-$i'),
                            onTap: () => _preview(photos, i),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                photos[i],
                                width: 92,
                                height: 92,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const _BrokenImage(size: 92),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                _Card(
                  children: [
                    if (category.isNotEmpty) _Field(label: 'Category', value: category),
                    if (priority != null)
                      _Field(label: 'Priority', value: priority.$1, valueColor: priority.$2),
                    if (ticket.isNotEmpty) _Field(label: 'Ticket', value: ticket),
                    _Field(label: 'Status', value: complaintStatusStyle(status).label),
                    if (showAssignee)
                      _AssigneeField(
                        complaint: c,
                        asTeam: isTeam,
                        onChange: canAssign ? _changeAssignee : null,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                _Card(
                  key: const Key('complaint-activity'),
                  children: [
                    const Text(
                      'Activity',
                      style: TextStyle(
                        color: ComplaintColors.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final entry in ordered) entry.$2.$2,
                    if (commentsAsync?.hasError == true && comments == null)
                      Row(
                        key: const Key('comments-error'),
                        children: [
                          const Expanded(
                            child: Text(
                              "Couldn't load comments.",
                              style: TextStyle(color: ComplaintColors.muted, fontSize: 12.5),
                            ),
                          ),
                          TextButton(
                            onPressed: () => ref.invalidate(complaintCommentsProvider(commentsKey!)),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    if (note.isNotEmpty)
                      Container(
                        key: const Key('complaint-resolution-note'),
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 6),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: ComplaintColors.brandSoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          note,
                          style: const TextStyle(color: ComplaintColors.ink, height: 1.4),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (canEdit || canComment)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    if (canEdit)
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: FilledButton.icon(
                            key: const Key('complaint-edit'),
                            onPressed: _edit,
                            style: FilledButton.styleFrom(
                              backgroundColor: ComplaintColors.brand,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            label: const Text(
                              'Edit',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ),
                    if (canEdit && canComment) const SizedBox(width: 10),
                    if (canComment)
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: OutlinedButton.icon(
                            key: const Key('complaint-add-comment'),
                            onPressed: () => _addComment(isTeam),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: ComplaintColors.brand,
                              side: const BorderSide(color: ComplaintColors.brand),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                            label: const Text(
                              'Add Comment',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EditComplaintSheet extends ConsumerStatefulWidget {
  final String propertyId;
  final Map<String, dynamic> complaint;

  const _EditComplaintSheet({required this.propertyId, required this.complaint});

  @override
  ConsumerState<_EditComplaintSheet> createState() => _EditComplaintSheetState();
}

class _EditComplaintSheetState extends ConsumerState<_EditComplaintSheet> {
  late String _status = complaintStatusOf(widget.complaint);
  late final _note = TextEditingController(
    text: widget.complaint['resolution_note']?.toString() ?? '',
  );
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final note = _note.text.trim();
    try {
      await ref.read(complaintsRepositoryProvider).updateStatus(
            widget.propertyId,
            widget.complaint['id'].toString(),
            _status,
            resolutionNote: note.isEmpty ? null : note,
          );
      if (!mounted) return;
      final now = DateTime.now().toUtc().toIso8601String();
      Navigator.of(context).pop(<String, dynamic>{
        ...widget.complaint,
        'status': _status,
        if (note.isNotEmpty) 'resolution_note': note,
        'updated_at': now,
        if (_status == 'resolved' || _status == 'closed')
          'resolved_at': widget.complaint['resolved_at'] ?? now,
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = complaintErrorMessage(e, saving: true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Edit Complaint',
            style: TextStyle(
              color: ComplaintColors.ink,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Status',
            style: TextStyle(color: ComplaintColors.muted, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in complaintStatuses)
                ChoiceChip(
                  key: Key('edit-status-$s'),
                  label: Text(complaintStatusStyle(s).label),
                  selected: _status == s,
                  selectedColor: ComplaintColors.brandSoft,
                  labelStyle: TextStyle(
                    color: _status == s ? ComplaintColors.brand : ComplaintColors.ink,
                    fontWeight: FontWeight.w600,
                  ),
                  onSelected: _saving ? null : (_) => setState(() => _status = s),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _note,
            maxLines: 3,
            enabled: !_saving,
            decoration: InputDecoration(
              labelText: 'Resolution note (optional)',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              key: const Key('edit-complaint-error'),
              style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            height: 48,
            child: FilledButton(
              key: const Key('edit-complaint-save'),
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(backgroundColor: ComplaintColors.brand),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }
}

const _warn = Color(0xFFD97706);

String _assignErrorMessage(Object e) {
  if (e is DioException) {
    final status = e.response?.statusCode;
    if (status == 422) {
      return "That person isn't on this property's team any more. Pick someone else.";
    }
    if (status == 503) return "Assignment isn't available yet.";
    if (status == 403) return "You don't have permission to assign this complaint.";
  }
  return complaintErrorMessage(e, saving: true);
}

String _commentErrorMessage(Object e) {
  if (e is DioException) {
    final status = e.response?.statusCode;
    if (status == 503) return "Comments aren't available yet.";
    if (status == 403) return "You can't comment on this complaint.";
    if (status == 404) return 'This complaint could not be found.';
    if (status == null) return 'Could not reach the server. Check your connection and try again.';
  }
  return "Couldn't post your comment. Please try again.";
}

class _AssigneeField extends StatelessWidget {
  final Map<String, dynamic> complaint;
  final bool asTeam;
  final VoidCallback? onChange;

  const _AssigneeField({required this.complaint, required this.asTeam, this.onChange});

  @override
  Widget build(BuildContext context) {
    final c = complaint;
    final String value;
    var muted = false;
    String? warning;
    if (asTeam) {
      final assigned = (c['assigned_to']?.toString() ?? '').isNotEmpty;
      if (assigned) {
        final name = c['assignee_name']?.toString().trim() ?? '';
        final role = complaintRoleLabel(c['assignee_role']?.toString());
        value = [name.isEmpty ? 'Team member' : name, if (role.isNotEmpty) role].join(' · ');
        if (c['assignee_active'] == false) {
          warning = onChange != null ? 'No longer on team · reassign' : 'No longer on team';
        }
      } else {
        value = 'Unassigned';
        muted = true;
      }
    } else {
      final assigned = c['is_assigned'] == true;
      value = assigned ? 'Assigned to property team' : 'Not yet assigned';
      muted = !assigned;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(
            width: 96,
            child: Text(
              'Assigned To',
              style: TextStyle(color: ComplaintColors.muted, fontSize: 13),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  key: const Key('complaint-assignee'),
                  style: TextStyle(
                    color: muted ? ComplaintColors.muted : ComplaintColors.ink,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (warning != null)
                  Text(
                    warning,
                    key: const Key('complaint-assignee-inactive'),
                    style: const TextStyle(color: _warn, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ),
          if (onChange != null)
            InkWell(
              key: const Key('complaint-assign-change'),
              onTap: onChange,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  (c['assigned_to']?.toString() ?? '').isEmpty ? 'Assign' : 'Change',
                  style: const TextStyle(
                    color: ComplaintColors.brand,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One comment or assignment event. Tenants only ever receive shared comments,
/// with team authors already anonymised by the server.
class _CommentEntry extends StatelessWidget {
  final Map<String, dynamic> entry;
  final bool asTeam;

  const _CommentEntry({required this.entry, required this.asTeam});

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final id = e['id']?.toString() ?? '';
    final kind = e['kind']?.toString() ?? 'comment';
    final at = DateTime.tryParse(e['created_at']?.toString() ?? '')?.toLocal();
    final when = at == null ? null : formatComplaintDayTime(at);
    final meta = e['meta'] is Map ? Map<String, dynamic>.from(e['meta'] as Map) : const {};
    final actor = e['author_name']?.toString().trim() ?? '';

    if (kind == 'assigned' || kind == 'unassigned') {
      final String title;
      if (kind == 'assigned') {
        final name = meta['assignee_name']?.toString().trim() ?? '';
        title = 'Assigned to ${name.isEmpty ? 'a team member' : name}';
      } else {
        final name = meta['previous_name']?.toString().trim() ?? '';
        title = name.isEmpty ? 'Unassigned' : 'Unassigned from $name';
      }
      final detail = [if (actor.isNotEmpty) 'by $actor', if (when != null) when].join(' · ');
      return _ActivityEntry(
        key: Key('complaint-event-$id'),
        title: title,
        when: detail.isEmpty ? null : detail,
      );
    }

    final role = e['author_role']?.toString() ?? '';
    final String author;
    if (asTeam) {
      final label = complaintRoleLabel(role);
      author = [if (actor.isNotEmpty) actor, if (label.isNotEmpty) label].join(' · ');
    } else {
      author = role == 'tenant' ? 'You' : 'Property team';
    }
    final internal = asTeam && e['visibility'] == 'internal';
    final body = e['body']?.toString() ?? '';

    return Padding(
      key: Key('complaint-comment-$id'),
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 5),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: internal ? _warn : ComplaintColors.brand,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        author.isEmpty ? 'Comment' : author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: ComplaintColors.ink,
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                    if (internal) ...[
                      const SizedBox(width: 6),
                      Container(
                        key: Key('comment-internal-$id'),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Internal',
                          style: TextStyle(color: _warn, fontSize: 10.5, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ],
                ),
                if (when != null)
                  Text(when, style: const TextStyle(color: ComplaintColors.muted, fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(color: ComplaintColors.ink, fontSize: 13.5, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AssignSheet extends ConsumerStatefulWidget {
  final String propertyId;
  final Map<String, dynamic> complaint;

  const _AssignSheet({required this.propertyId, required this.complaint});

  @override
  ConsumerState<_AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends ConsumerState<_AssignSheet> {
  bool _saving = false;
  String? _error;

  String get _current => widget.complaint['assigned_to']?.toString() ?? '';

  Future<void> _pick(String? userId) async {
    if (_saving) return;
    if ((userId ?? '') == _current) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await ref.read(complaintsRepositoryProvider).setAssignment(
            widget.propertyId,
            widget.complaint['id'].toString(),
            userId,
          );
      if (!mounted) return;
      Navigator.of(context).pop(updated);
    } catch (e) {
      if (!mounted) return;
      if (e is DioException && e.response?.statusCode == 422) {
        ref.invalidate(complaintAssigneesProvider(widget.propertyId));
      }
      setState(() {
        _saving = false;
        _error = _assignErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final assignees = ref.watch(complaintAssigneesProvider(widget.propertyId));
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Assign Complaint',
              style: TextStyle(
                color: ComplaintColors.ink,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              "Only this property's team is listed. Tenants see that it is assigned, not to whom.",
              style: TextStyle(color: ComplaintColors.muted, fontSize: 12.5),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                key: const Key('assign-error'),
                style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13),
              ),
            ],
            const SizedBox(height: 8),
            Flexible(
              child: assignees.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Padding(
                  key: const Key('assignees-error'),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    _assignErrorMessage(e),
                    style: const TextStyle(color: ComplaintColors.muted),
                  ),
                ),
                data: (people) => ListView(
                  shrinkWrap: true,
                  children: [
                    if (people.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'No team members to assign yet.',
                          style: TextStyle(color: ComplaintColors.muted),
                        ),
                      ),
                    for (final p in people)
                      ListTile(
                        key: Key('assignee-option-${p['user_id']}'),
                        contentPadding: EdgeInsets.zero,
                        enabled: !_saving,
                        leading: CircleAvatar(
                          backgroundColor: ComplaintColors.brandSoft,
                          child: Text(
                            (p['name']?.toString().trim().isNotEmpty ?? false)
                                ? p['name'].toString().trim()[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: ComplaintColors.brand,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        title: Text(
                          (p['name']?.toString().trim().isNotEmpty ?? false)
                              ? p['name'].toString().trim()
                              : 'Team member',
                        ),
                        subtitle: Text(complaintRoleLabel(p['role']?.toString())),
                        trailing: p['user_id']?.toString() == _current
                            ? const Icon(Icons.check_rounded, color: ComplaintColors.brand)
                            : null,
                        onTap: () => _pick(p['user_id']?.toString()),
                      ),
                    if (_current.isNotEmpty)
                      ListTile(
                        key: const Key('assignee-unassign'),
                        contentPadding: EdgeInsets.zero,
                        enabled: !_saving,
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFFF1F5F9),
                          child: Icon(Icons.person_off_outlined, color: ComplaintColors.muted),
                        ),
                        title: const Text('Unassign'),
                        onTap: () => _pick(null),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentSheet extends ConsumerStatefulWidget {
  final String propertyId;
  final String complaintId;
  final bool asTeam;

  const _CommentSheet({
    required this.propertyId,
    required this.complaintId,
    required this.asTeam,
  });

  @override
  ConsumerState<_CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends ConsumerState<_CommentSheet> {
  final _body = TextEditingController();
  bool _share = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final text = _body.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Write a comment first.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(complaintsRepositoryProvider).addComment(
            widget.propertyId,
            widget.complaintId,
            text,
            visibility: widget.asTeam ? (_share ? 'tenant_visible' : 'internal') : null,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _commentErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Add Comment',
            style: TextStyle(
              color: ComplaintColors.ink,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            key: const Key('comment-input'),
            controller: _body,
            maxLines: 4,
            minLines: 2,
            maxLength: 2000,
            enabled: !_saving,
            decoration: InputDecoration(
              hintText: widget.asTeam ? 'Add an update or note' : 'Write to the property team',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          if (widget.asTeam)
            SwitchListTile(
              key: const Key('comment-share-toggle'),
              contentPadding: EdgeInsets.zero,
              value: _share,
              activeThumbColor: ComplaintColors.brand,
              onChanged: _saving ? null : (v) => setState(() => _share = v),
              title: const Text(
                'Share with tenant',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              subtitle: Text(
                _share
                    ? 'The tenant who raised this will see it.'
                    : 'Internal note. Only your team can see it.',
                style: const TextStyle(fontSize: 12.5),
              ),
            )
          else
            const Text(
              'Your comment will be visible to the property team.',
              style: TextStyle(color: ComplaintColors.muted, fontSize: 12.5),
            ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              key: const Key('comment-error'),
              style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            height: 48,
            child: FilledButton(
              key: const Key('comment-submit'),
              onPressed: _saving ? null : _post,
              style: FilledButton.styleFrom(backgroundColor: ComplaintColors.brand),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Post'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final List<Widget> children;

  const _Card({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ComplaintColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ComplaintColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _Field({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label, style: const TextStyle(color: ComplaintColors.muted, fontSize: 13)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? ComplaintColors.ink,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityEntry extends StatelessWidget {
  final String title;
  final String? when;

  const _ActivityEntry({super.key, required this.title, this.when});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 5),
            width: 8,
            height: 8,
            decoration: const BoxDecoration(color: ComplaintColors.brand, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: ComplaintColors.ink,
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                  ),
                ),
                if (when != null)
                  Text(when!, style: const TextStyle(color: ComplaintColors.muted, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BrokenImage extends StatelessWidget {
  final double? size;

  const _BrokenImage({this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      color: const Color(0xFFF1F5F9),
      alignment: Alignment.center,
      child: const Icon(Icons.broken_image_outlined, color: ComplaintColors.muted),
    );
  }
}

class _PhotoPreview extends StatefulWidget {
  final List<String> photos;
  final int initialIndex;

  const _PhotoPreview({required this.photos, required this.initialIndex});

  @override
  State<_PhotoPreview> createState() => _PhotoPreviewState();
}

class _PhotoPreviewState extends State<_PhotoPreview> {
  late final _pages = PageController(initialPage: widget.initialIndex);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.photos;
    return Scaffold(
      key: const Key('complaint-photo-preview'),
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: PageView.builder(
        controller: _pages,
        itemCount: photos.length,
        itemBuilder: (_, i) => InteractiveViewer(
          minScale: 0.8,
          maxScale: 4,
          child: Center(
            child: Image.network(
              photos[i],
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Text(
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
