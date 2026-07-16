// features/tenancies/data/tenancy_repository.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import 'dart:io';
import 'package:dio/dio.dart';
final tenancyRepositoryProvider = Provider<TenancyRepository>((ref) {
  return TenancyRepository(ref.watch(apiClientProvider));
});

class TenancyRepository {
  final ApiClient _client;
  TenancyRepository(this._client);

  Future<List<Map<String, dynamic>>> listByNode(String propertyId, String nodeId) async {
    final res = await _client.dio.get('/v1/properties/$propertyId/tenancies', queryParameters: {
      'nodeId': nodeId,
    });
    return List<Map<String, dynamic>>.from(res.data['data']);
  }

  Future<Map<String, dynamic>> create(
    String propertyId, {
    required String nodeId,
    required String phone,
    required String fullName,
    String? email,
    String? address,
    String? companyName,
    String? aadhaarNumber,
    String? moveInAt,
    double? securityDeposit,
    String? notes,
  }) async {
    final body = <String, dynamic>{
      'nodeId': nodeId,
      'phone': phone,
      'fullName': fullName,
    };
    if (email != null) body['email'] = email;
    if (address != null) body['address'] = address;
    if (companyName != null) body['companyName'] = companyName;
    if (aadhaarNumber != null) body['aadhaarNumber'] = aadhaarNumber;
    if (moveInAt != null) body['moveInAt'] = moveInAt;
    if (securityDeposit != null) body['securityDeposit'] = securityDeposit;
    if (notes != null) body['notes'] = notes;

    final res = await _client.dio.post('/v1/properties/$propertyId/tenancies', data: body);
    return Map<String, dynamic>.from(res.data['data']);
  }

  Future<void> endTenancy(String propertyId, String tenancyId) async {
    await _client.dio.post('/v1/properties/$propertyId/tenancies/$tenancyId/end');
  }
  Future<void> uploadAgreement(String propertyId, String tenancyId, String filePath) async {
    final formData = FormData.fromMap({
      'agreement': await MultipartFile.fromFile(filePath, filename: 'agreement.pdf'),
    });
    await _client.dio.post('/v1/properties/$propertyId/tenancies/$tenancyId/agreement', data: formData);
  }

  String get baseUrl => _client.dio.options.baseUrl;
}