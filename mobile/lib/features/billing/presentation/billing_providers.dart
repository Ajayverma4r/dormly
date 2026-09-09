// features/billing/presentation/billing_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/billing_repository.dart';

final invoicesProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, propertyId) =>
      ref.watch(billingRepositoryProvider).listInvoices(propertyId),
);

final receivedThisMonthProvider =
    FutureProvider.autoDispose.family<double, String>((ref, propertyId) async {
  try {
    return await ref
        .watch(billingRepositoryProvider)
        .receivedThisMonth(propertyId);
  } catch (_) {
    // Endpoint may not be deployed yet — treat as zero.
    return 0;
  }
});

final paymentsProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, propertyId) async {
    try {
      return await ref
          .watch(billingRepositoryProvider)
          .listPayments(propertyId);
    } catch (_) {
      // Endpoint may not be deployed yet — empty list; UI falls back to invoices.
      return [];
    }
  },
);

enum LiveCollectionStatusFilter { all, pending, paid, overdue }

/// Set before switching to the Payments tab to pre-select a status chip.
final liveCollectionFilterRequestProvider =
    StateProvider<LiveCollectionStatusFilter?>((ref) => null);
