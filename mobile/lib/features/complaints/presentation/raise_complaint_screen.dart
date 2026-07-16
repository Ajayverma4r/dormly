// features/complaints/presentation/raise_complaint_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/complaints_repository.dart';

class RaiseComplaintScreen extends ConsumerStatefulWidget {
  final String propertyId;
  final String nodeId;
  const RaiseComplaintScreen({super.key, required this.propertyId, required this.nodeId});

  @override
  ConsumerState<RaiseComplaintScreen> createState() => _RaiseComplaintScreenState();
}

class _RaiseComplaintScreenState extends ConsumerState<RaiseComplaintScreen> {
  final _categoryController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _priority = 'medium';
  bool _saving = false;
  String? _error;

  Future<void> _submit() async {
    if (_categoryController.text.trim().isEmpty || _descriptionController.text.trim().isEmpty) {
      setState(() => _error = 'Enter a category and description.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await ref.read(complaintsRepositoryProvider).raiseMine(
            propertyId: widget.propertyId,
            nodeId: widget.nodeId,
            category: _categoryController.text.trim(),
            description: _descriptionController.text.trim(),
            priority: _priority,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = 'Could not submit: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Raise a Complaint')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _categoryController,
            decoration: const InputDecoration(labelText: 'Category', hintText: 'e.g. Plumbing, Electrical, Cleaning', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _descriptionController,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          const Text('Priority', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: ['low', 'medium', 'high'].map((p) => ChoiceChip(
                  label: Text(p),
                  selected: _priority == p,
                  onSelected: (_) => setState(() => _priority = p),
                )).toList(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 24),
          SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: _saving ? null : _submit,
              child: _saving ? const CircularProgressIndicator(color: Colors.white) : const Text('Submit Complaint'),
            ),
          ),
        ],
      ),
    );
  }
}