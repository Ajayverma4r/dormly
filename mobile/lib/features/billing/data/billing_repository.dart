// features/billing/data/billing_repository.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

final billingRepositoryProvider = Provider<BillingRepository>((ref) {
  return BillingRepository(ref.watch(apiClientProvider));
});

class BillingRepository {
  final ApiClient _client;
  BillingRepository(this._client);

  Future<List<Map<String, dynamic>>> listChargeTypes(String propertyId) async {
    final res = await _client.dio.get('/v1/properties/$propertyId/billing/charge-types');
    return List<Map<String, dynamic>>.from(res.data['data']);
  }

  Future<List<Map<String, dynamic>>> listInvoices(String propertyId) async {
    final res = await _client.dio.get('/v1/properties/$propertyId/billing/invoices');
    return List<Map<String, dynamic>>.from(res.data['data']);
  }

  Future<Map<String, dynamic>> getInvoice(String propertyId, String invoiceId) async {
    final res = await _client.dio.get('/v1/properties/$propertyId/billing/invoices/$invoiceId');
    return Map<String, dynamic>.from(res.data['data']);
  }

  Future<Map<String, dynamic>> createInvoice(
    String propertyId, {
    required String tenancyId,
    required String periodStart,
    required String periodEnd,
    required String dueDate,
    required List<Map<String, dynamic>> lineItems,
  }) async {
    final res = await _client.dio.post('/v1/properties/$propertyId/billing/invoices', data: {
      'tenancyId': tenancyId,
      'periodStart': periodStart,
      'periodEnd': periodEnd,
      'dueDate': dueDate,
      'lineItems': lineItems,
    });
    return Map<String, dynamic>.from(res.data['data']);
  }

  Future<void> recordPayment(String propertyId, String invoiceId, double amount, String method) async {
    await _client.dio.post('/v1/properties/$propertyId/billing/invoices/$invoiceId/payments', data: {
      'amount': amount,
      'method': method,
    });
  }

  Future<void> sendReminder(String propertyId, String invoiceId) async {
    await _client.dio.post('/v1/properties/$propertyId/billing/invoices/$invoiceId/remind');
  }

  Future<List<Map<String, dynamic>>> listTenanciesForProperty(String propertyId) async {
    final res = await _client.dio.get('/v1/properties/$propertyId/tenancies');
    return List<Map<String, dynamic>>.from(res.data['data']);
  }
}