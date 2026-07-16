// features/auth/presentation/context_picker_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/auth_repository.dart';
import 'login_flow.dart';
// Shared by both the auto-select path (OTP verify, only one context) and
// the manual picker below — keeps routing-after-login logic in one place.


class ContextPickerScreen extends ConsumerWidget {
  final List<Map<String, dynamic>> contexts;
  const ContextPickerScreen({super.key, required this.contexts});

  IconData _iconFor(String role) {
    switch (role) {
      case 'tenant':
        return Icons.person_outline;
      case 'owner':
      case 'admin':
        return Icons.business_center_outlined;
      default:
        return Icons.badge_outlined;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Choose how to continue', style: TextStyle(color: Colors.black87)),
        automaticallyImplyLeading: false,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: contexts.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final ctx = contexts[index];
          return Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: CircleAvatar(
                backgroundColor: const Color(0xFFEFF2FF),
                child: Icon(_iconFor(ctx['role']), color: const Color(0xFF2B5CFF)),
              ),
              title: Text(ctx['label'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text((ctx['role'] as String).toUpperCase(), style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await ref.read(authRepositoryProvider).selectContext(ctx['type'], ctx['id']);
                if (context.mounted) {
                  await routeAfterContextSelection(context, ref, ctx);
                }
              },
            ),
          );
        },
      ),
    );
  }
}