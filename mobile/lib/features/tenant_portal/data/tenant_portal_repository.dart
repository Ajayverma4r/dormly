// features/tenant_portal/data/tenant_portal_repository.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

final tenantPortalRepositoryProvider = Provider<TenantPortalRepository>((ref) {
  return TenantPortalRepository(ref.watch(apiClientProvider));
});

class TenantPortalRepository {
  final ApiClient _client;
  TenantPortalRepository(this._client);

  Future<Map<String, dynamic>> getMyTenancy() async {
    final res = await _client.dio.get('/v1/tenant-portal/me');
    return Map<String, dynamic>.from(res.data['data']);
  }

  Future<Map<String, dynamic>> requestMoveOut({
    required String proposedExitDate,
    bool isEmergency = false,
    String? reason,
  }) async {
    final res = await _client.dio.post(
      '/v1/tenant-portal/move-out-request',
      data: {
        'proposedExitDate': proposedExitDate,
        'isEmergency': isEmergency,
        if (reason != null) 'reason': reason,
      },
    );
    return Map<String, dynamic>.from(res.data['data']);
  }

  Future<List<Map<String, dynamic>>> listMyInvoices() async {
    final res = await _client.dio.get('/v1/tenant-portal/invoices');
    return List<Map<String, dynamic>>.from(res.data['data']);
  }

  Future<List<Map<String, dynamic>>> getMessMenu() async {
    final res = await _client.dio.get('/v1/tenant-portal/mess-menu');
    return List<Map<String, dynamic>>.from(res.data['data'] as List);
  }

  Future<List<Map<String, dynamic>>> listMessMenuForProperty(
    String propertyId,
  ) async {
    final res =
        await _client.dio.get('/v1/properties/$propertyId/mess-menu');
    return List<Map<String, dynamic>>.from(res.data['data'] as List);
  }

  Future<void> upsertMessMenuDay({
    required String propertyId,
    required int dayOfWeek,
    required String breakfast,
    required String lunch,
    required String dinner,
  }) async {
    await _client.dio.put(
      '/v1/properties/$propertyId/mess-menu/day',
      data: {
        'dayOfWeek': dayOfWeek,
        'breakfast': breakfast,
        'lunch': lunch,
        'dinner': dinner,
      },
    );
  }

  Future<List<Map<String, dynamic>>> myMeterReadings() async {
    final res = await _client.dio.get('/v1/tenant-portal/meter-readings');
    return List<Map<String, dynamic>>.from(res.data['data'] as List);
  }

  Future<Map<String, dynamic>> submitMeterReading({
    required double readingValue,
    String? billingCycle,
    double? ratePerUnit,
    String? imagePath,
  }) async {
    final form = FormData.fromMap({
      'readingValue': readingValue,
      if (billingCycle != null) 'billingCycle': billingCycle,
      if (ratePerUnit != null) 'ratePerUnit': ratePerUnit,
      if (imagePath != null)
        'meterImage': await MultipartFile.fromFile(
          imagePath,
          filename: 'meter.jpg',
        ),
    });
    final res = await _client.dio.post(
      '/v1/tenant-portal/meter-readings',
      data: form,
    );
    return Map<String, dynamic>.from(res.data['data'] as Map);
  }

  Future<List<Map<String, dynamic>>> listMeterReadingsForProperty(
    String propertyId,
  ) async {
    final res =
        await _client.dio.get('/v1/properties/$propertyId/meter-readings');
    return List<Map<String, dynamic>>.from(res.data['data'] as List);
  }

  Future<Map<String, dynamic>> submitMeterReadingForProperty({
    required String propertyId,
    required String unitId,
    required double readingValue,
    String? tenancyId,
    String? billingCycle,
    double? ratePerUnit,
    String? imagePath,
  }) async {
    final form = FormData.fromMap({
      'unitId': unitId,
      'readingValue': readingValue,
      if (tenancyId != null) 'tenancyId': tenancyId,
      if (billingCycle != null) 'billingCycle': billingCycle,
      if (ratePerUnit != null) 'ratePerUnit': ratePerUnit,
      if (imagePath != null)
        'meterImage': await MultipartFile.fromFile(
          imagePath,
          filename: 'meter.jpg',
        ),
    });
    final res = await _client.dio.post(
      '/v1/properties/$propertyId/meter-readings',
      data: form,
    );
    return Map<String, dynamic>.from(res.data['data'] as Map);
  }

  Future<List<Map<String, dynamic>>> myGatePasses() async {
    final res = await _client.dio.get('/v1/tenant-portal/gate-passes');
    return List<Map<String, dynamic>>.from(res.data['data'] as List);
  }

  Future<Map<String, dynamic>> createGatePass({
    required String visitorName,
    String purpose = 'visitor',
    String? notes,
  }) async {
    final res = await _client.dio.post(
      '/v1/tenant-portal/gate-passes',
      data: {
        'visitorName': visitorName,
        'purpose': purpose,
        if (notes != null) 'notes': notes,
      },
    );
    return Map<String, dynamic>.from(res.data['data'] as Map);
  }

  Future<List<Map<String, dynamic>>> societyNotices() async {
    final res = await _client.dio.get('/v1/tenant-portal/society-notices');
    return List<Map<String, dynamic>>.from(res.data['data'] as List);
  }

  Future<Map<String, dynamic>> leaseDetails() async {
    final res = await _client.dio.get('/v1/tenant-portal/lease-details');
    return Map<String, dynamic>.from(res.data['data'] as Map);
  }

  String get baseUrl => _client.dio.options.baseUrl;
}
