// features/tenant_portal/presentation/request_move_out_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../data/tenant_portal_repository.dart';
import 'tenant_dashboard_screen.dart' show myTenancyProvider;

final _dateFmt = DateFormat('d MMM yyyy');
final _dateTimeFmt = DateFormat('d MMM yyyy, h:mm a');

Future<bool> showRequestMoveOutSheet({
  required BuildContext context,
  required WidgetRef ref,
  required Map<String, dynamic> tenancy,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => RequestMoveOutSheet(tenancy: tenancy),
  );
  return result == true;
}

class RequestMoveOutSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> tenancy;
  const RequestMoveOutSheet({super.key, required this.tenancy});

  @override
  ConsumerState<RequestMoveOutSheet> createState() =>
      _RequestMoveOutSheetState();
}

class _RequestMoveOutSheetState extends ConsumerState<RequestMoveOutSheet> {
  DateTime? _proposedDate;
  bool _isEmergency = false;
  String _reason = 'Standard Move-out (Regular Notice)';
  bool _submitting = false;
  String? _error;

  static const _emergencyReasons = [
    'Job relocation',
    'Family emergency',
    'Medical',
  ];

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _proposedDate ?? today,
      firstDate: today, // Strict: no backdating
      lastDate: today.add(const Duration(days: 90)),
    );
    if (picked != null) setState(() => _proposedDate = picked);
  }

  Future<void> _callOwner() async {
    final phone = widget.tenancy['owner_phone']?.toString() ?? '';
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Owner phone not available.')),
      );
      return;
    }
    final uri = Uri(scheme: 'tel', path: digits);
    await launchUrl(uri);
  }

  Future<void> _submit() async {
    if (_proposedDate == null) {
      setState(() => _error = 'Please select a proposed move-out date.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(tenantPortalRepositoryProvider).requestMoveOut(
            proposedExitDate: _proposedDate!.toIso8601String(),
            isEmergency: _isEmergency,
            reason: _isEmergency ? _reason : 'Standard Move-out (Regular Notice)',
          );
      ref.invalidate(myTenancyProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final ownerName = widget.tenancy['owner_name']?.toString() ?? 'Owner';

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
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
            const SizedBox(height: 16),
            Text(
              'Request Move-Out',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Your submit time is logged permanently and cannot be changed.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.slate,
                    fontSize: 13,
                  ),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Proposed move-out date'),
              subtitle: Text(
                _proposedDate == null
                    ? 'Tap to choose (today or later)'
                    : _dateFmt.format(_proposedDate!),
              ),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: _pickDate,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Emergency Move-Out'),
              subtitle: const Text(
                'Job relocation, family emergency, or medical',
              ),
              value: _isEmergency,
              activeThumbColor: AppColors.caution,
              onChanged: (v) => setState(() {
                _isEmergency = v;
                if (v && !_emergencyReasons.contains(_reason)) {
                  _reason = _emergencyReasons.first;
                }
                if (!v) {
                  _reason = 'Standard Move-out (Regular Notice)';
                }
              }),
            ),
            if (_isEmergency) ...[
              const SizedBox(height: 4),
              DropdownButtonFormField<String>(
                initialValue: _emergencyReasons.contains(_reason)
                    ? _reason
                    : _emergencyReasons.first,
                decoration: const InputDecoration(
                  labelText: 'Emergency reason',
                  border: OutlineInputBorder(),
                ),
                items: _emergencyReasons
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _reason = v);
                },
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _callOwner,
              icon: const Icon(Icons.call_outlined),
              label: Text('Call Owner / Manager ($ownerName)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ],
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.blueprint,
                  foregroundColor: Colors.white,
                ),
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Submit Move-Out Request',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Logged on submit: ${_dateTimeFmt.format(DateTime.now())} (server clock final)',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: AppColors.slate),
            ),
          ],
        ),
      ),
    );
  }
}
