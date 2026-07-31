// features/structure/presentation/property_structure_tab_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../domain/hierarchy_level.dart';
import '../../../core/widgets/dormly_empty_state.dart';
import '../../../core/widgets/dynamic_icon.dart';
import '../../../core/theme/app_theme.dart';
import 'dynamic_dashboard/dynamic_dashboard_screen.dart' show hierarchyLevelsProvider, nodeCountProvider;
import 'node_list/node_list_screen.dart';

class PropertyStructureTabScreen extends ConsumerWidget {
  final String propertyId;
  final bool canManage;

  const PropertyStructureTabScreen({super.key, required this.propertyId, required this.canManage});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final levelsAsync = ref.watch(hierarchyLevelsProvider(propertyId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Structure'),
        actions: [
          if (canManage)
            IconButton(
              icon: const Icon(Icons.tune, size: 20),
              tooltip: 'Structure settings',
              onPressed: () => context.push('/dashboard/$propertyId/structure'),
            ),
        ],
      ),
      body: levelsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Something went wrong: $err')),
        data: (levels) {
          if (levels.isEmpty) {
            return DormlyEmptyState(
              title: 'No structure configured yet',
              subtitle: canManage
                  ? 'Tap the settings icon above to define levels for this property.'
                  : 'Ask the property owner to configure the structure.',
              action: canManage
                  ? FilledButton(
                      onPressed: () => context.push('/dashboard/$propertyId/structure'),
                      child: const Text('Open Structure Settings'),
                    )
                  : null,
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1.1,
            ),
            itemCount: levels.length,
            itemBuilder: (context, index) {
              final level = levels[index];
              return _LevelCard(level: level, propertyId: propertyId, allLevels: levels);
            },
          );
        },
      ),
    );
  }
}

class _LevelCard extends ConsumerWidget {
  final HierarchyLevel level;
  final String propertyId;
  final List<HierarchyLevel> allLevels;

  const _LevelCard({required this.level, required this.propertyId, required this.allLevels});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countAsync = ref.watch(nodeCountProvider((propertyId, level.id)));
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: theme.dividerColor)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (context) => NodeListScreen(propertyId: propertyId, level: level, allLevels: allLevels),
          ));
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DynamicIcon(name: level.icon, colorHex: level.color, size: 28),
              const Spacer(),
              Text(level.displayName, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              countAsync.when(
                data: (count) => Text('$count', style: theme.textTheme.headlineSmall),
                loading: () => const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                error: (_, __) => const Text('—'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}