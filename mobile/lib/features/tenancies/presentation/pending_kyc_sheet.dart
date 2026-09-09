// features/tenancies/presentation/pending_kyc_sheet.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/image_compress.dart';
import '../../billing/presentation/whatsapp_reminder.dart' show whatsAppGreen;
import '../../dashboard/presentation/property_dashboard_provider.dart';
import '../data/tenancy_repository.dart';
import 'residents_list_screen.dart' show propertyResidentsProvider;
import 'tenant_profile_section.dart'
    show resolveFileUrl, tenancyDocumentsProvider;

const _kycAmber = Color(0xFFD97706);
const _kycAmberDark = Color(0xFF854D0E);
const _kycYellow = Color(0xFFFEF9C3);
const _missingOrange = Color(0xFFC2410C);

Future<void> showPendingKYCSheet({
  required BuildContext context,
  required String propertyId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => PendingKYCSheet(propertyId: propertyId),
  );
}

class PendingKYCSheet extends ConsumerWidget {
  final String propertyId;

  const PendingKYCSheet({
    super.key,
    required this.propertyId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenanciesAsync = ref.watch(propertyResidentsProvider(propertyId));

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.68,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      builder: (context, scrollController) {
        final pending = tenanciesAsync.maybeWhen(
          data: (rows) => rows.where(_isPendingKyc).toList(),
          orElse: () => const <Map<String, dynamic>>[],
        );

        return Material(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          clipBehavior: Clip.antiAlias,
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
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _kycYellow,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        color: _kycAmber,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Pending KYC Documents',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: tenanciesAsync.isLoading
                    ? const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _kycAmber,
                          ),
                        ),
                      )
                    : tenanciesAsync.hasError
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'Could not load pending KYC.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: AppColors.slate),
                                  ),
                                  const SizedBox(height: 12),
                                  TextButton(
                                    onPressed: () => ref.invalidate(
                                      propertyResidentsProvider(propertyId),
                                    ),
                                    style: TextButton.styleFrom(
                                      foregroundColor: _kycAmberDark,
                                    ),
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : pending.isEmpty
                            ? const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text(
                                    'All tenants have completed KYC.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: AppColors.slate),
                                  ),
                                ),
                              )
                            : ListView.builder(
                                controller: scrollController,
                                padding:
                                    const EdgeInsets.fromLTRB(8, 8, 8, 16),
                                itemCount: pending.length,
                                itemBuilder: (context, i) => _KycTile(
                                  propertyId: propertyId,
                                  tenant: pending[i],
                                ),
                              ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _KycTile extends ConsumerStatefulWidget {
  final String propertyId;
  final Map<String, dynamic> tenant;

  const _KycTile({
    required this.propertyId,
    required this.tenant,
  });

  @override
  ConsumerState<_KycTile> createState() => _KycTileState();
}

class _KycTileState extends ConsumerState<_KycTile> {
  String? _uploadingKey;
  final Set<String> _uploadedKeys = {};

  String get _tenancyId => (widget.tenant['id'] ?? '').toString();

  void _sendReminder() {
    final name = _tenantName(widget.tenant);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Reminder sent to $name')),
    );
  }

  Future<void> _showUploadOptionsDialog(
    BuildContext context,
    String documentName, {
    required String docType,
  }) async {
    if (_uploadingKey != null) return;
    final tenantName = _tenantName(widget.tenant);

    final source = await showDialog<ImageSource>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Upload $documentName for $tenantName'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.camera_alt_outlined, color: _kycAmber),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.photo_library_outlined,
                color: _kycAmberDark,
              ),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (source == null || !mounted) return;
    await _uploadDocument(docType: docType, source: source);
  }

  Future<void> _uploadDocument({
    required String docType,
    required ImageSource source,
  }) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    if (_tenancyId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not find this tenancy.')),
      );
      return;
    }

    setState(() => _uploadingKey = docType);
    try {
      final compressed = await compressKycImage(File(picked.path));
      if (!compressed.success) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              compressed.errorMessage ??
                  'Could not compress image. Please try another photo.',
            ),
            backgroundColor: AppColors.danger,
          ),
        );
        return;
      }

      final path = compressed.file!.path;
      if (docType == 'photo') {
        await ref.read(tenancyRepositoryProvider).uploadProfilePhoto(
              widget.propertyId,
              _tenancyId,
              path,
            );
      } else {
        await ref.read(tenancyRepositoryProvider).uploadDocument(
              widget.propertyId,
              _tenancyId,
              path,
              docType: docType,
            );
      }

      if (!mounted) return;
      setState(() {
        _uploadedKeys.add(docType);
        _uploadingKey = null;
      });
      ref.invalidate(
        tenancyDocumentsProvider((widget.propertyId, _tenancyId)),
      );
      ref.invalidate(propertyResidentsProvider(widget.propertyId));
      ref.invalidate(propertyDashboardProvider(widget.propertyId));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Document uploaded'),
          backgroundColor: AppColors.positive,
        ),
      );
    } on TenancyUpdateException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not upload image. Please try again.'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted && _uploadingKey == docType) {
        setState(() => _uploadingKey = null);
      }
    }
  }

  Future<void> _viewDocument(String? url) async {
    if (url == null || url.isEmpty) return;
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open this document.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _tenantName(widget.tenant);
    final room = _roomLabel(widget.tenant);
    final title = (room.isEmpty || room == '—') ? name : '$name · $room';
    final storedDocs = _tenancyId.isEmpty
        ? const <Map<String, dynamic>>[]
        : (ref
                .watch(tenancyDocumentsProvider((widget.propertyId, _tenancyId)))
                .valueOrNull ??
            const <Map<String, dynamic>>[]);
    final baseUrl = ref.watch(tenancyRepositoryProvider).baseUrl;
    final docs = _kycDocs(
      widget.tenant,
      storedDocs,
      _uploadedKeys,
      baseUrl,
    );
    final uploadedCount = docs.where((d) => d.isUploaded).length;
    final missing = docs.length - uploadedCount;
    final subtitle = missing == 0
        ? '$uploadedCount/${docs.length} Uploaded'
        : uploadedCount == 0
            ? (missing == 1 ? 'Missing 1 Document' : 'Missing $missing Documents')
            : '$uploadedCount/${docs.length} Uploaded';

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 8, 8),
        controlAffinity: ListTileControlAffinity.leading,
        iconColor: _kycAmber,
        collapsedIconColor: _kycAmberDark,
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: missing == 0 ? AppColors.positive : _missingOrange,
          ),
        ),
        trailing: IconButton(
          tooltip: 'WhatsApp reminder',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          onPressed: _sendReminder,
          icon: const Icon(Icons.chat, color: whatsAppGreen, size: 20),
        ),
        children: [
          for (final doc in docs)
            _KycDocRow(
              doc: doc,
              uploading: _uploadingKey == doc.key,
              onCapture: () => _showUploadOptionsDialog(
                context,
                doc.label,
                docType: doc.key,
              ),
              onView: doc.viewUrl == null
                  ? null
                  : () => _viewDocument(doc.viewUrl),
            ),
        ],
      ),
    );
  }
}

class _KycDoc {
  final String key;
  final String label;
  final bool isUploaded;
  final String? viewUrl;

  const _KycDoc({
    required this.key,
    required this.label,
    required this.isUploaded,
    this.viewUrl,
  });
}

class _KycDocRow extends StatelessWidget {
  final _KycDoc doc;
  final bool uploading;
  final VoidCallback onCapture;
  final VoidCallback? onView;

  const _KycDocRow({
    required this.doc,
    required this.uploading,
    required this.onCapture,
    this.onView,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 4, top: 2, bottom: 2),
      child: Row(
        children: [
          Icon(
            doc.isUploaded
                ? Icons.check_circle
                : Icons.insert_drive_file_outlined,
            size: 18,
            color: doc.isUploaded ? AppColors.positive : _kycAmber,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              doc.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
          ),
          if (uploading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _kycAmber,
                ),
              ),
            )
          else if (doc.isUploaded)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.check_circle,
                  color: AppColors.positive,
                  size: 18,
                ),
                const SizedBox(width: 4),
                const Text(
                  'Uploaded',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: AppColors.positive,
                  ),
                ),
                if (onView != null)
                  TextButton(
                    onPressed: onView,
                    style: TextButton.styleFrom(
                      foregroundColor: _kycAmberDark,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text(
                      'View',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                    ),
                  ),
              ],
            )
          else
            TextButton.icon(
              onPressed: onCapture,
              style: TextButton.styleFrom(
                foregroundColor: _kycAmber,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              icon: const Icon(Icons.camera_alt_outlined, size: 18),
              label: const Text(
                'Upload',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

bool _isBlank(dynamic value) {
  if (value == null) return true;
  return value.toString().trim().isEmpty;
}

String _kycStatus(Map<String, dynamic> t) =>
    (t['kyc_status'] ?? t['kycStatus'] ?? '').toString().toLowerCase();

bool _isPendingKyc(Map<String, dynamic> t) {
  final status = (t['status'] ?? 'active').toString().toLowerCase();
  if (status != 'active') return false;
  final kyc = _kycStatus(t);
  if (kyc == 'pending' || kyc == 'submitted') return true;
  if (kyc.isEmpty) return _missingDocLabels(t).isNotEmpty;
  return false;
}

String _tenantName(Map<String, dynamic> t) {
  for (final key in ['full_name', 'fullName', 'user_name', 'userName', 'name']) {
    final value = t[key]?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return 'Tenant';
}

String _roomLabel(Map<String, dynamic> t) {
  for (final key in ['node_name', 'nodeName', 'room']) {
    final value = t[key]?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return '—';
}

List<String> _missingDocKeys(Map<String, dynamic> t) {
  final keys = <String>[];
  if (_isBlank(t['aadhaar_number'] ?? t['aadhaarNumber'])) keys.add('aadhaar');
  if (_isBlank(t['profile_photo_url'] ?? t['profilePhotoUrl'])) keys.add('photo');
  if (_isBlank(t['agreement_pdf_url'] ?? t['agreementPdfUrl'])) {
    keys.add('agreement');
  }
  return keys;
}

List<String> _missingDocLabels(Map<String, dynamic> t) =>
    _missingDocKeys(t).map(_docLabel).toList();

String _docLabel(String key) {
  switch (key) {
    case 'aadhaar':
      return 'Aadhaar Card';
    case 'photo':
      return 'Photo';
    case 'agreement':
      return 'Agreement';
    default:
      return 'Document';
  }
}

const _kycDocKeys = ['aadhaar', 'photo', 'agreement'];

List<_KycDoc> _kycDocs(
  Map<String, dynamic> tenant,
  List<Map<String, dynamic>> storedDocs,
  Set<String> uploadedKeys,
  String baseUrl,
) {
  return [
    for (final key in _kycDocKeys)
      _KycDoc(
        key: key,
        label: _docLabel(key),
        isUploaded: uploadedKeys.contains(key) ||
            _isDocUploaded(tenant, storedDocs, key),
        viewUrl: _docViewUrl(tenant, storedDocs, key, baseUrl),
      ),
  ];
}

bool _isDocUploaded(
  Map<String, dynamic> tenant,
  List<Map<String, dynamic>> storedDocs,
  String key,
) {
  if (_hasStoredDoc(storedDocs, key)) return true;
  switch (key) {
    case 'aadhaar':
      return !_isBlank(tenant['aadhaar_number'] ?? tenant['aadhaarNumber']);
    case 'photo':
      return !_isBlank(
        tenant['profile_photo_url'] ?? tenant['profilePhotoUrl'],
      );
    case 'agreement':
      return !_isBlank(
        tenant['agreement_pdf_url'] ?? tenant['agreementPdfUrl'],
      );
    default:
      return false;
  }
}

bool _hasStoredDoc(List<Map<String, dynamic>> docs, String key) {
  for (final d in docs) {
    final type = (d['doc_type'] ?? d['docType'])?.toString();
    if (type != key) continue;
    final url = d['file_url'] ?? d['fileUrl'];
    if (url != null && url.toString().trim().isNotEmpty) return true;
  }
  return false;
}

String? _docViewUrl(
  Map<String, dynamic> tenant,
  List<Map<String, dynamic>> storedDocs,
  String key,
  String baseUrl,
) {
  for (final d in storedDocs) {
    final type = (d['doc_type'] ?? d['docType'])?.toString();
    if (type != key) continue;
    final url = resolveFileUrl(d['file_url'] ?? d['fileUrl'], baseUrl);
    if (url != null) return url;
  }
  if (key == 'photo') {
    return resolveFileUrl(
      tenant['profile_photo_url'] ?? tenant['profilePhotoUrl'],
      baseUrl,
    );
  }
  if (key == 'agreement') {
    return resolveFileUrl(
      tenant['agreement_pdf_url'] ?? tenant['agreementPdfUrl'],
      baseUrl,
    );
  }
  return null;
}
