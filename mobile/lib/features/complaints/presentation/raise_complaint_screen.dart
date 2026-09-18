// features/complaints/presentation/raise_complaint_screen.dart
//
// Screen 8 — category grid, description, optional photos, sticky submit.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../data/complaints_repository.dart';

const _brand = Color(0xFF6D28D9);
const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _bg = Color(0xFFF8FAFC);
const _border = Color(0xFFE2E8F0);

class RaiseComplaintScreen extends ConsumerStatefulWidget {
  final String propertyId;
  final String nodeId;
  const RaiseComplaintScreen({
    super.key,
    required this.propertyId,
    required this.nodeId,
  });

  @override
  ConsumerState<RaiseComplaintScreen> createState() =>
      _RaiseComplaintScreenState();
}

class _RaiseComplaintScreenState extends ConsumerState<RaiseComplaintScreen> {
  final _searchController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _picker = ImagePicker();
  String _category = 'Electricity';
  final List<XFile> _photos = [];
  bool _saving = false;
  String? _error;

  static const _categories = [
    (Icons.bolt_rounded, 'Electricity'),
    (Icons.water_drop_outlined, 'Plumbing'),
    (Icons.ac_unit_rounded, 'AC / Cooling'),
    (Icons.chair_outlined, 'Furniture'),
    (Icons.cleaning_services_outlined, 'Cleaning'),
    (Icons.more_horiz_rounded, 'Other'),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    if (_photos.length >= 3) return;
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
    );
    if (file == null) return;
    setState(() => _photos.add(file));
  }

  Future<void> _submit() async {
    final desc = _descriptionController.text.trim();
    final search = _searchController.text.trim();
    if (desc.isEmpty && search.isEmpty) {
      setState(() => _error = 'Please describe the issue.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final description = desc.isEmpty ? search : desc;
      await ref.read(complaintsRepositoryProvider).raiseMine(
            propertyId: widget.propertyId,
            nodeId: widget.nodeId,
            category: _category,
            description: description,
            photoPaths: _photos.map((p) => p.path).toList(),
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
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        foregroundColor: _ink,
        title: const Text(
          'Raise a Complaint',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: "What's the issue?",
                    hintStyle: const TextStyle(color: _muted),
                    prefixIcon:
                        const Icon(Icons.search_rounded, color: _muted),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: _border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: _border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide:
                          const BorderSide(color: _brand, width: 1.4),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Category',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 12),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _categories.length,
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.05,
                  ),
                  itemBuilder: (_, i) {
                    final item = _categories[i];
                    final selected = _category == item.$2;
                    return Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        onTap: () => setState(() => _category = item.$2),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: selected ? _brand : _border,
                              width: selected ? 1.8 : 1,
                            ),
                            boxShadow: selected
                                ? [
                                    BoxShadow(
                                      color:
                                          _brand.withValues(alpha: 0.18),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(item.$1,
                                  color: _brand, size: 28),
                              const SizedBox(height: 8),
                              Text(
                                item.$2,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: selected ? _brand : _ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 22),
                const Text(
                  'Description',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _descriptionController,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: 'Tell us more about the issue...',
                    hintStyle: const TextStyle(color: _muted),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: _border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: _border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide:
                          const BorderSide(color: _brand, width: 1.4),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'Add Photos (Optional)',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    ..._photos.map(
                      (p) => Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            File(p.path),
                            width: 72,
                            height: 72,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                    if (_photos.length < 3)
                      InkWell(
                        onTap: _pickPhoto,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _border,
                              style: BorderStyle.solid,
                            ),
                          ),
                          child: const Icon(Icons.camera_alt_outlined,
                              color: _brand),
                        ),
                      ),
                    const Spacer(),
                    Text(
                      '${_photos.length}/3 photos',
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(_error!,
                      style: const TextStyle(color: Color(0xFFDC2626))),
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
                height: 54,
                child: FilledButton(
                  onPressed: _saving ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: _brand,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Submit Complaint',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
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
