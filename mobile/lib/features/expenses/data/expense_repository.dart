// features/expenses/data/expense_repository.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/expense.dart';

final expenseRepositoryProvider = Provider<ExpenseRepository>((ref) {
  return ExpenseRepository(ref.watch(apiClientProvider));
});

class ExpenseRepository {
  final ApiClient _client;
  ExpenseRepository(this._client);

  Future<List<Expense>> list(String propertyId) async {
    final res = await _client.dio.get('/v1/properties/$propertyId/expenses');
    final raw = res.data['data'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Expense.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<double> totalThisMonth(String propertyId) async {
    final res = await _client.dio
        .get('/v1/properties/$propertyId/expenses/summary/this-month');
    final data = res.data['data'];
    if (data is Map) {
      return double.tryParse(
            (data['totalThisMonth'] ?? data['total_this_month'])?.toString() ??
                '',
          ) ??
          0;
    }
    return 0;
  }

  Future<Expense> create(
    String propertyId, {
    required String title,
    required double amount,
    DateTime? date,
  }) async {
    final res = await _client.dio.post(
      '/v1/properties/$propertyId/expenses',
      data: {
        'title': title,
        'amount': amount,
        if (date != null)
          'expenseDate': date.toIso8601String().split('T').first,
      },
    );
    return Expense.fromJson(Map<String, dynamic>.from(res.data['data'] as Map));
  }
}
