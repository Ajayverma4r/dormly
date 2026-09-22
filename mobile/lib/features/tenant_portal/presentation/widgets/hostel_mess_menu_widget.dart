// features/tenant_portal/presentation/widgets/hostel_mess_menu_widget.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../mess_menu_screen.dart';
import '../tenant_portal_providers.dart';
import 'module_async_body.dart';

const _brand = Color(0xFF5218D1);
const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);

/// Hostel / PG only — prefetches mess menu in isolation; failures stay local.
class HostelMessMenuWidget extends ConsumerWidget {
  const HostelMessMenuWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(tenantMessMenuProvider);

    return ModuleAsyncBody<List<Map<String, dynamic>>>(
      async: async,
      errorLabel: 'Failed to load menu',
      onRetry: () => ref.invalidate(tenantMessMenuProvider),
      builder: (_) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MessMenuScreen()),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1FAE5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.restaurant_outlined,
                    color: Color(0xFF059669),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mess Menu',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: _ink,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        "Check today's meals and weekly menu.",
                        style: TextStyle(fontSize: 12.5, color: _muted),
                      ),
                    ],
                  ),
                ),
                const Text(
                  'View Menu →',
                  style: TextStyle(
                    color: _brand,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
