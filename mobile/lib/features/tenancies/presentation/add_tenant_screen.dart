// features/tenancies/presentation/add_tenant_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/tenancy_repository.dart';

class AddTenantScreen extends ConsumerStatefulWidget {
  final String propertyId;
  final String nodeId;
  const AddTenantScreen({super.key, required this.propertyId, required this.nodeId});

  @override
  ConsumerState<AddTenantScreen> createState() => _AddTenantScreenState();
}

class _AddTenantScreenState extends ConsumerState<AddTenantScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _companyController = TextEditingController();
  final _aadhaarController = TextEditingController();
  final _depositController = TextEditingController();
  final _notesController = TextEditingController();
  DateTime? _moveInDate;
  bool _saving = false;
  String? _error;

  Future<void> _pickMoveInDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _moveInDate = picked);
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty || _phoneController.text.trim().isEmpty) {
      setState(() => _error = 'Name and phone number are required.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await ref.read(tenancyRepositoryProvider).create(
            widget.propertyId,
            nodeId: widget.nodeId,
            phone: '+91${_phoneController.text.trim()}',
            fullName: _nameController.text.trim(),
            email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
            address: _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
            companyName: _companyController.text.trim().isEmpty ? null : _companyController.text.trim(),
            aadhaarNumber: _aadhaarController.text.trim().isEmpty ? null : _aadhaarController.text.trim(),
            moveInAt: _moveInDate?.toIso8601String(),
            securityDeposit: double.tryParse(_depositController.text.trim()),
            notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = 'Could not add tenant: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

 Widget _field(String label, TextEditingController controller,
      {TextInputType? type, bool required = false, int? maxLength}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        keyboardType: type,
        maxLength: maxLength,
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          counterText: maxLength != null ? '' : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Tenant')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _field('Full Name', _nameController, required: true),
          _field('Mobile Number', _phoneController, type: TextInputType.phone, required: true, maxLength: 10),
          _field('Email', _emailController, type: TextInputType.emailAddress),
          _field('Address', _addressController),
          _field('Company Name (Optional)', _companyController),
          _field('Aadhaar Number', _aadhaarController),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_moveInDate == null
                ? 'Move-in Date'
                : 'Move-in: ${_moveInDate!.toLocal().toString().split(' ').first}'),
            trailing: const Icon(Icons.calendar_today_outlined),
            onTap: _pickMoveInDate,
          ),
          const SizedBox(height: 14),
          _field('Security Deposit', _depositController, type: TextInputType.number),
          _field('Notes', _notesController),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 20),
          SizedBox(
            height: 54,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2B5CFF),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Save Tenant', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}