// features/tenancies/presentation/tenancy_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/tenancy_repository.dart';

final propertyResidentsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>(
  (ref, propertyId) =>
      ref.watch(tenancyRepositoryProvider).listByProperty(propertyId),
);
