// features/tenancies/presentation/node_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/tenancy_repository.dart';
import '../../structure/data/structure_repository.dart';
import 'add_tenant_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';


final tenanciesForNodeProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, (String propertyId, String nodeId)>((ref, args) async {
  final repo = ref.watch(tenancyRepositoryProvider);
  return repo.listByNode(args.$1, args.$2);
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty && context.mounted) {
      try {
        await ref.read(structureRepositoryProvider).renameNode(propertyId, nodeId, newName);
        if (context.mounted) Navigator.of(context).pop(true); // signal parent to refresh
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not rename: $e')));
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
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
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
        await ref.read(structureRepositoryProvider).deleteNode(propertyId, nodeId);
        if (context.mounted) Navigator.of(context).pop(true);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not delete: $e')));
        }
      }
    }
  }

  Future<void> _endTenancy(BuildContext context, WidgetRef ref, String tenancyId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End this tenancy?'),
        content: const Text('This marks the tenant as moved out. Their records stay for history.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('End Tenancy')),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await ref.read(tenancyRepositoryProvider).endTenancy(propertyId, tenancyId);
        ref.invalidate(tenanciesForNodeProvider((propertyId, nodeId)));
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not end tenancy: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenanciesAsync = ref.watch(tenanciesForNodeProvider((propertyId, nodeId)));

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
      body: tenanciesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Something went wrong: $err')),
        data: (tenancies) {
          final active = tenancies.where((t) => t['status'] == 'active').toList();

          if (active.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person_outline, size: 56, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text('No tenant assigned to this $levelName',
                        textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2B5CFF)),
                      onPressed: () async {
                        final created = await Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                            builder: (context) => AddTenantScreen(propertyId: propertyId, nodeId: nodeId),
                          ),
                        );
                        if (created == true) {
                          ref.invalidate(tenanciesForNodeProvider((propertyId, nodeId)));
                        }
                      },
                      icon: const Icon(Icons.person_add_outlined, color: Colors.white),
                      label: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('Add Tenant', style: TextStyle(color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final tenant = active.first;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade200),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const CircleAvatar(
                          backgroundColor: Color(0xFFEFF2FF),
                          child: Icon(Icons.person, color: Color(0xFF2B5CFF)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tenant['full_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                              Text(tenant['phone'] ?? '', style: TextStyle(color: Colors.grey.shade600)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 28),
                    if (tenant['email'] != null) _detailRow('Email', tenant['email']),
                    if (tenant['address'] != null) _detailRow('Address', tenant['address']),
                    if (tenant['company_name'] != null) _detailRow('Company', tenant['company_name']),
                    if (tenant['aadhaar_number'] != null) _detailRow('Aadhaar', tenant['aadhaar_number']),
                    if (tenant['move_in_at'] != null) _detailRow('Move-in', tenant['move_in_at'].toString().split('T').first),
                    if (tenant['security_deposit'] != null) _detailRow('Security Deposit', '₹${tenant['security_deposit']}'),
                    if (tenant['notes'] != null && tenant['notes'].toString().isNotEmpty) _detailRow('Notes', tenant['notes']),
                    const SizedBox(height: 12),
                    if (tenant['agreement_pdf_url'] != null)
                      OutlinedButton.icon(
                        onPressed: () => _viewAgreement(context, ref, tenant['agreement_pdf_url']),
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('View Agreement'),
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: () => _uploadAgreement(context, ref, tenant['id']),
                        icon: const Icon(Icons.upload_file_outlined),
                        label: const Text('Upload Agreement'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                  minimumSize: const Size.fromHeight(50),
                ),
                onPressed: () => _endTenancy(context, ref, tenant['id']),
                child: const Text('End Tenancy', style: TextStyle(color: Colors.red)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(label, style: TextStyle(color: Colors.grey.shade600))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
  Future<void> _uploadAgreement(BuildContext context, WidgetRef ref, String tenancyId) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (result == null || result.files.single.path == null) return;

    try {
      await ref.read(tenancyRepositoryProvider).uploadAgreement(propertyId, tenancyId, result.files.single.path!);
      ref.invalidate(tenanciesForNodeProvider((propertyId, nodeId)));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Agreement uploaded')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    }
  }

  Future<void> _viewAgreement(BuildContext context, WidgetRef ref, String relativeUrl) async {
    final baseUrl = ref.read(tenancyRepositoryProvider).baseUrl;
    final uri = Uri.parse('$baseUrl$relativeUrl');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}