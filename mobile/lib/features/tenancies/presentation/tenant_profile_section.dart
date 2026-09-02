// features/tenancies/presentation/tenant_profile_section.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/image_compress.dart';
import '../data/tenancy_repository.dart';
import 'node_detail_screen.dart' show tenanciesForNodeProvider;
import 'utils/aadhaar_validation.dart';

final tenancyDocumentsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, (String propertyId, String tenancyId)>(
        (ref, args) async {
  try {
    return await ref
        .watch(tenancyRepositoryProvider)
        .listDocuments(args.$1, args.$2);
  } catch (_) {
    return const [];
  }
});

class TenantProfileSection extends ConsumerWidget {
  final String propertyId;
  final String nodeId;
  final String tenancyId;
  final String baseUrl;

  const TenantProfileSection({
    super.key,
    required this.propertyId,
    required this.nodeId,
    required this.tenancyId,
    required this.baseUrl,
  });

  Map<String, dynamic> _activeTenancy(WidgetRef ref) {
    final async = ref.watch(tenanciesForNodeProvider((propertyId, nodeId)));
    return async.maybeWhen(
      data: (tenancies) {
        for (final raw in tenancies) {
          final t = Map<String, dynamic>.from(raw);
          if (t['id']?.toString() == tenancyId &&
              t['status']?.toString() == 'active') {
            return t;
          }
        }
        return const {};
      },
      orElse: () => const {},
    );
  }

  void _openEditProfile(BuildContext context, Map<String, dynamic> tenant) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => TenantProfileEditSheet(
        propertyId: propertyId,
        nodeId: nodeId,
        tenancyId: tenancyId,
        tenant: tenant,
        baseUrl: baseUrl,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = _activeTenancy(ref);
    if (tenant.isEmpty) return const SizedBox.shrink();

    final docsAsync =
        ref.watch(tenancyDocumentsProvider((propertyId, tenancyId)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Tenant 360', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _openEditProfile(context, tenant),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit Profile'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _PersonalInformationCard(tenant: tenant),
        const SizedBox(height: 12),
        docsAsync.when(
          loading: () => _KycDocumentsCard(
            tenant: tenant,
            documents: const [],
            baseUrl: baseUrl,
          ),
          error: (_, __) => _KycDocumentsCard(
            tenant: tenant,
            documents: const [],
            baseUrl: baseUrl,
          ),
          data: (docs) => _KycDocumentsCard(
            tenant: tenant,
            documents: docs,
            baseUrl: baseUrl,
          ),
        ),
      ],
    );
  }
}

class _PersonalInformationCard extends StatelessWidget {
  final Map<String, dynamic> tenant;

  const _PersonalInformationCard({required this.tenant});

  @override
  Widget build(BuildContext context) {
    final email = tenantField(tenant, ['email']);
    final address = tenantField(tenant, ['address']);
    final occupation = formatOccupation(
      tenantField(tenant, ['occupation', 'company_name', 'companyName']),
    );
    final ecName = tenantField(tenant, [
      'emergency_contact_name',
      'emergencyContactName',
    ]);
    final ecRelation = tenantField(tenant, [
      'emergency_contact_relation',
      'emergencyContactRelation',
    ]);
    final ecPhone = tenantField(tenant, [
      'emergency_contact_phone',
      'emergencyContactPhone',
    ]);

    return _ProfileCard(
      title: 'Personal Information',
      child: Column(
        children: [
          _ProfileInfoRow(
            label: 'Email Address',
            value: email ?? 'Not provided',
          ),
          const Divider(height: 20),
          _ProfileInfoRow(
            label: 'Permanent Address',
            value: address ?? 'Not provided',
          ),
          const Divider(height: 20),
          _ProfileInfoRow(
            label: 'Occupation',
            value: occupation,
          ),
          const Divider(height: 20),
          _EmergencyContactRow(
            name: ecName,
            relation: ecRelation,
            phone: ecPhone,
          ),
        ],
      ),
    );
  }
}

class _KycDocumentsCard extends StatelessWidget {
  final Map<String, dynamic> tenant;
  final List<Map<String, dynamic>> documents;
  final String baseUrl;

  const _KycDocumentsCard({
    required this.tenant,
    required this.documents,
    required this.baseUrl,
  });

  @override
  Widget build(BuildContext context) {
    final idType = resolveIdType(tenant);
    final idNumber = tenantField(tenant, ['aadhaar_number', 'aadhaarNumber']);
    final kycStatus =
        tenantField(tenant, ['kyc_status', 'kycStatus']) ?? 'pending';
    final policeDone = tenantBool(tenant, [
      'police_verification_done',
      'policeVerificationDone',
    ]);
    final doc = primaryIdDocument(documents, idType);
    final fileUrl = doc != null
        ? resolveFileUrl(doc['file_url'] ?? doc['fileUrl'], baseUrl)
        : null;

    return _ProfileCard(
      title: 'KYC & Documents',
      trailing: kycStatusBadge(kycStatus),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProfileInfoRow(label: 'ID Type', value: formatIdType(idType)),
          const SizedBox(height: 12),
          _ProfileInfoRow(
            label: 'ID Number',
            value: maskIdNumber(idNumber, idType),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(
                policeDone ? Icons.verified_user : Icons.verified_user_outlined,
                size: 20,
                color: policeDone ? AppColors.positive : AppColors.slate,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Police Verification Done',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              Icon(
                policeDone ? Icons.check_circle : Icons.radio_button_unchecked,
                color: policeDone ? AppColors.positive : AppColors.slate,
                size: 22,
              ),
            ],
          ),
          if (fileUrl != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(fileUrl),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.attach_file_outlined),
                label: const Text('View Attached Document'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _ProfileCard({
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

class _ProfileInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _ProfileInfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
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

class _EmergencyContactRow extends StatelessWidget {
  final String? name;
  final String? relation;
  final String? phone;

  const _EmergencyContactRow({
    required this.name,
    required this.relation,
    required this.phone,
  });

  @override
  Widget build(BuildContext context) {
    final hasContact =
        (name != null && name!.isNotEmpty) || (phone != null && phone!.isNotEmpty);

    if (!hasContact) {
      return _ProfileInfoRow(
        label: 'Emergency Contact',
        value: 'Not provided',
      );
    }

    final subtitle = [
      if (relation != null && relation!.isNotEmpty) relation!,
      if (name != null && name!.isNotEmpty) name!,
    ].join(' · ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text('Emergency Contact',
              style: Theme.of(context).textTheme.bodyMedium),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                subtitle,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
              if (phone != null && phone!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(phone!, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ],
          ),
        ),
        if (phone != null && phone!.isNotEmpty)
          IconButton(
            onPressed: () => launchUrl(Uri.parse('tel:$phone')),
            icon: const Icon(Icons.phone_outlined, size: 20),
            color: AppColors.blueprint,
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }
}

class TenantProfileEditSheet extends ConsumerStatefulWidget {
  final String propertyId;
  final String nodeId;
  final String tenancyId;
  final Map<String, dynamic> tenant;
  final String baseUrl;

  const TenantProfileEditSheet({
    super.key,
    required this.propertyId,
    required this.nodeId,
    required this.tenancyId,
    required this.tenant,
    required this.baseUrl,
  });

  @override
  ConsumerState<TenantProfileEditSheet> createState() =>
      _TenantProfileEditSheetState();
}

class _TenantProfileEditSheetState extends ConsumerState<TenantProfileEditSheet> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  late final TextEditingController _emailController;
  late final TextEditingController _addressController;
  late final TextEditingController _ecNameController;
  late final TextEditingController _ecRelationController;
  late final TextEditingController _ecPhoneController;
  late final TextEditingController _idNumberController;

  String _occupation = 'student';
  String _idType = 'aadhaar';
  String _kycStatus = 'pending';
  bool _policeVerification = false;
  bool _saving = false;
  bool _processingImage = false;
  String? _localProfilePreview;
  String? _localDocPreview;

  @override
  void initState() {
    super.initState();
    final t = widget.tenant;
    _emailController = TextEditingController(
      text: tenantField(t, ['email']) ?? '',
    );
    _addressController = TextEditingController(
      text: tenantField(t, ['address']) ?? '',
    );
    _ecNameController = TextEditingController(
      text: tenantField(t, ['emergency_contact_name', 'emergencyContactName']) ??
          '',
    );
    _ecRelationController = TextEditingController(
      text: tenantField(t, [
            'emergency_contact_relation',
            'emergencyContactRelation',
          ]) ??
          '',
    );
    _ecPhoneController = TextEditingController(
      text: tenantField(t, [
            'emergency_contact_phone',
            'emergencyContactPhone',
          ]) ??
          '',
    );
    _idNumberController = TextEditingController(
      text: tenantField(t, ['aadhaar_number', 'aadhaarNumber']) ?? '',
    );

    final occ = tenantField(t, ['occupation'])?.toLowerCase();
    if (occ == 'working' || occ == 'student') {
      _occupation = occ!;
    }

    _idType = resolveIdType(t);
    _kycStatus =
        tenantField(t, ['kyc_status', 'kycStatus']) ?? 'pending';
    _policeVerification = tenantBool(t, [
      'police_verification_done',
      'policeVerificationDone',
    ]);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _addressController.dispose();
    _ecNameController.dispose();
    _ecRelationController.dispose();
    _ecPhoneController.dispose();
    _idNumberController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadImage({required bool isProfilePhoto}) async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    setState(() => _processingImage = true);
    try {
      final compressed = await compressImage(File(picked.path));
      if (!compressed.success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                compressed.errorMessage ??
                    'Please select a smaller or less complex image.',
              ),
              backgroundColor: AppColors.danger,
            ),
          );
        }
        return;
      }

      final repo = ref.read(tenancyRepositoryProvider);
      if (isProfilePhoto) {
        await repo.uploadProfilePhoto(
          widget.propertyId,
          widget.tenancyId,
          compressed.file!.path,
        );
        setState(() => _localProfilePreview = compressed.file!.path);
      } else {
        await repo.uploadDocument(
          widget.propertyId,
          widget.tenancyId,
          compressed.file!.path,
          docType: mapDocumentType(_idType),
        );
        setState(() => _localDocPreview = compressed.file!.path);
      }

      ref.invalidate(tenanciesForNodeProvider(
          (widget.propertyId, widget.nodeId)));
      ref.invalidate(tenancyDocumentsProvider(
          (widget.propertyId, widget.tenancyId)));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isProfilePhoto ? 'Profile photo updated' : 'Document uploaded'),
            backgroundColor: AppColors.positive,
          ),
        );
      }
    } on TenancyUpdateException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not upload image. Please try again.'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _processingImage = false);
    }
  }

  String? _validateIdNumber(String? value) {
    if (_idType == 'aadhaar') {
      return validateAadhaarNumber(value, required: false);
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      await ref.read(tenancyRepositoryProvider).update(
            widget.propertyId,
            widget.tenancyId,
            nodeId: widget.nodeId,
            email: _emailController.text.trim(),
            address: _addressController.text.trim(),
            occupation: _occupation,
            emergencyContactName: _ecNameController.text.trim(),
            emergencyContactRelation: _ecRelationController.text.trim(),
            emergencyContactPhone: _ecPhoneController.text.trim(),
            idType: _idType,
            aadhaarNumber: _idNumberController.text.trim(),
            policeVerificationDone: _policeVerification,
            kycStatus: _kycStatus,
          );
      ref.invalidate(tenanciesForNodeProvider(
          (widget.propertyId, widget.nodeId)));
      ref.invalidate(tenancyDocumentsProvider(
          (widget.propertyId, widget.tenancyId)));
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated'),
            backgroundColor: AppColors.positive,
          ),
        );
      }
    } on TenancyUpdateException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save profile. Please try again.'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final remotePhoto = resolveFileUrl(
      tenantField(widget.tenant, ['profile_photo_url', 'profilePhotoUrl']),
      widget.baseUrl,
    );
    final profilePreview = _localProfilePreview ?? remotePhoto;
    final isBusy = _saving || _processingImage;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Stack(
        children: [
          SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Edit Profile',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  Center(
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 44,
                          backgroundColor: AppColors.hairline,
                          backgroundImage: _profileImageProvider(profilePreview),
                          child: profilePreview == null
                              ? const Icon(Icons.person_outline, size: 40)
                              : null,
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: isBusy
                              ? null
                              : () => _pickAndUploadImage(isProfilePhoto: true),
                          icon: const Icon(Icons.camera_alt_outlined, size: 18),
                          label: const Text('Change Profile Photo'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email Address',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _addressController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Permanent Address',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _occupation,
                    decoration: const InputDecoration(
                      labelText: 'Occupation',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'student', child: Text('Student')),
                      DropdownMenuItem(value: 'working', child: Text('Working')),
                    ],
                    onChanged: isBusy
                        ? null
                        : (v) => setState(() => _occupation = v ?? 'student'),
                  ),
                  const SizedBox(height: 16),
                  Text('Emergency Contact',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _ecNameController,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _ecRelationController,
                    decoration: const InputDecoration(
                      labelText: 'Relation',
                      hintText: 'e.g. Parent, Spouse',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _ecPhoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('KYC & Identity',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _idType,
                    decoration: const InputDecoration(
                      labelText: 'ID Type',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'aadhaar', child: Text('Aadhaar')),
                      DropdownMenuItem(value: 'pan', child: Text('PAN')),
                      DropdownMenuItem(
                          value: 'passport', child: Text('Passport')),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: isBusy
                        ? null
                        : (v) => setState(() => _idType = v ?? 'aadhaar'),
                  ),
                  const SizedBox(height: 8),
                  if (_idType == 'aadhaar')
                    TextFormField(
                      controller: _idNumberController,
                      keyboardType: TextInputType.number,
                      maxLength: 12,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: _validateIdNumber,
                      decoration: const InputDecoration(
                        labelText: 'Aadhaar Number',
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                    )
                  else
                    TextFormField(
                      controller: _idNumberController,
                      decoration: InputDecoration(
                        labelText: '${formatIdType(_idType)} Number',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: isBusy
                        ? null
                        : () => _pickAndUploadImage(isProfilePhoto: false),
                    icon: const Icon(Icons.upload_file_outlined),
                    label: Text(_localDocPreview != null
                        ? 'ID Document Selected'
                        : 'Upload ID Document Photo'),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _kycStatus,
                    decoration: const InputDecoration(
                      labelText: 'KYC Status',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'pending', child: Text('Pending')),
                      DropdownMenuItem(
                          value: 'submitted', child: Text('Submitted')),
                      DropdownMenuItem(
                          value: 'verified', child: Text('Verified')),
                      DropdownMenuItem(
                          value: 'rejected', child: Text('Rejected')),
                    ],
                    onChanged: isBusy
                        ? null
                        : (v) => setState(() => _kycStatus = v ?? 'pending'),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Police Verification Done'),
                    value: _policeVerification,
                    onChanged: isBusy
                        ? null
                        : (v) => setState(() => _policeVerification = v),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: isBusy ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Save Profile'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_processingImage)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black26,
                child: Center(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(
                            'Compressing and uploading…',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
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

// ---- Shared helpers ----

ImageProvider? _profileImageProvider(String? path) {
  if (path == null) return null;
  if (path.startsWith('http')) return NetworkImage(path);
  return FileImage(File(path));
}

String mapDocumentType(String idType) {
  const allowed = {
    'aadhaar',
    'pan',
    'photo',
    'agreement',
    'address_proof',
    'other',
  };
  if (allowed.contains(idType)) return idType;
  return 'other';
}

String? tenantField(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final v = data[key]?.toString().trim();
    if (v != null && v.isNotEmpty) return v;
  }
  return null;
}

bool tenantBool(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final raw = data[key];
    if (raw is bool) return raw;
    if (raw?.toString().toLowerCase() == 'true') return true;
  }
  return false;
}

String formatOccupation(String? raw) {
  if (raw == null || raw.isEmpty) return 'Not specified';
  switch (raw.toLowerCase()) {
    case 'student':
      return 'Student';
    case 'working':
      return 'Working';
    default:
      return raw;
  }
}

String resolveIdType(Map<String, dynamic> tenant) {
  final explicit = tenantField(tenant, ['id_type', 'idType']);
  if (explicit != null) return explicit.toLowerCase();
  if (tenantField(tenant, ['aadhaar_number', 'aadhaarNumber']) != null) {
    return 'aadhaar';
  }
  return 'aadhaar';
}

String formatIdType(String type) {
  switch (type.toLowerCase()) {
    case 'aadhaar':
      return 'Aadhaar';
    case 'pan':
      return 'PAN';
    case 'passport':
      return 'Passport';
    default:
      return type.toUpperCase();
  }
}

String maskIdNumber(String? raw, String idType) {
  if (raw == null || raw.isEmpty) return 'Not provided';
  final digits = raw.replaceAll(RegExp(r'\s'), '');
  if (digits.length <= 4) return '•••• $digits';
  final last4 = digits.substring(digits.length - 4);
  if (idType == 'aadhaar' && digits.length >= 12) {
    return '•••• •••• $last4';
  }
  return '•••• •••• $last4';
}

Map<String, dynamic>? primaryIdDocument(
  List<Map<String, dynamic>> docs,
  String idType,
) {
  for (final d in docs) {
    if (d['doc_type']?.toString() == idType ||
        d['docType']?.toString() == idType) {
      return d;
    }
  }
  for (final d in docs) {
    final t = d['doc_type']?.toString() ?? d['docType']?.toString();
    if (t == 'aadhaar' || t == 'pan') return d;
  }
  return docs.isNotEmpty ? docs.first : null;
}

String? resolveFileUrl(String? raw, String baseUrl) {
  if (raw == null || raw.trim().isEmpty) return null;
  if (raw.startsWith('http')) return raw;
  return '$baseUrl$raw';
}

Widget kycStatusBadge(String status) {
  late String label;
  late Color color;

  switch (status.toLowerCase()) {
    case 'verified':
      label = 'Verified';
      color = AppColors.positive;
    case 'rejected':
      label = 'Rejected';
      color = AppColors.danger;
    case 'submitted':
      label = 'In Review';
      color = AppColors.caution;
    default:
      label = 'Pending';
      color = AppColors.slate;
  }

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
