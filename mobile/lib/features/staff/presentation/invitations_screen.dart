// features/staff/presentation/invitations_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/staff_repository.dart';
import '../../auth/presentation/login_flow.dart';
import '../../../core/theme/app_theme.dart';

class InvitationsScreen extends ConsumerStatefulWidget {
  final List<Map<String, dynamic>> invitations;
  const InvitationsScreen({super.key, required this.invitations});

  @override
  ConsumerState<InvitationsScreen> createState() => _InvitationsScreenState();
}

class _InvitationsScreenState extends ConsumerState<InvitationsScreen> {
  late List<Map<String, dynamic>> _pending;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _pending = List.from(widget.invitations);
  }

  Future<void> _respond(Map<String, dynamic> invite, bool accept) async {
    setState(() => _busy = true);
    try {
      final repo = ref.read(staffRepositoryProvider);
      if (accept) {
        await repo.acceptInvitation(invite['id']);
      } else {
        await repo.declineInvitation(invite['id']);
      }
      setState(() => _pending.removeWhere((i) => i['id'] == invite['id']));

      if (_pending.isEmpty && mounted) {
        await completeLogin(context, ref);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not respond: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('Invitations'), automaticallyImplyLeading: false),
      body: _pending.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text("You've been invited", style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  'Confirm each invitation below to gain access to that property.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                ..._pending.map((invite) => Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(invite['property_name'] ?? '', style: theme.textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text('Role: ${invite['role'].toString().toUpperCase()}', style: theme.textTheme.bodyMedium),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _busy ? null : () => _respond(invite, false),
                                  child: const Text('Decline'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _busy ? null : () => _respond(invite, true),
                                  child: const Text('Accept'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )),
              ],
            ),
    );
  }
}