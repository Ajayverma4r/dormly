// features/tenancies/data/tenancy_repository.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import 'package:dio/dio.dart';

final tenancyRepositoryProvider = Provider<TenancyRepository>((ref) {
  return TenancyRepository(ref.watch(apiClientProvider));
});

/// Thrown when a tenancy PATCH succeeds but the updated row cannot be loaded.
class TenancyUpdateException implements Exception {
  final String message;
  TenancyUpdateException(this.message);

  @override
  String toString() => message;
}

class TenancyRepository {
  final ApiClient _client;
  TenancyRepository(this._client);

  Map<String, dynamic> _parseRow(dynamic data) {
    if (data == null || data is! Map) {
      throw TenancyUpdateException('Server returned an empty tenancy response.');
    }
    return Map<String, dynamic>.from(data);
  }

  double? readAmount(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final raw = data[key];
      if (raw == null) continue;
      if (raw is num) return raw.toDouble();
      return double.tryParse(raw.toString());
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> listByNode(
      String propertyId, String nodeId) async {
    final res = await _client.dio.get(
      '/v1/properties/$propertyId/tenancies',
      queryParameters: {'nodeId': nodeId},
    );
    return (res.data['data'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> listByProperty(String propertyId) async {
    final res = await _client.dio.get('/v1/properties/$propertyId/tenancies');
    return (res.data['data'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<Map<String, dynamic>> getById(
      String propertyId, String tenancyId) async {
    final res = await _client.dio.get(
      '/v1/properties/$propertyId/tenancies/$tenancyId',
    );
    return _parseRow(res.data['data']);
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

    final res =
        await _client.dio.post('/v1/properties/$propertyId/tenancies', data: body);
    return _parseRow(res.data['data']);
  }

  Future<void> endTenancy(String propertyId, String tenancyId) async {
    await _client.dio.post(
        '/v1/properties/$propertyId/tenancies/$tenancyId/end');
  }

  /// PATCH tenancy and re-fetch the full row (API equivalent of `.select().single()`).
  Future<Map<String, dynamic>> update(
    String propertyId,
    String tenancyId, {
    double? monthlyRent,
    double? securityDeposit,
    String? fullName,
    String? email,
    String? notes,
  }) async {
    final body = <String, dynamic>{};
    if (monthlyRent != null) {
      body['monthlyRent'] = monthlyRent;
      body['monthly_rent'] = monthlyRent;
    }
    if (securityDeposit != null) {
      body['securityDeposit'] = securityDeposit;
      body['security_deposit'] = securityDeposit;
    }
    if (fullName != null) body['fullName'] = fullName;
    if (email != null) body['email'] = email;
    if (notes != null) body['notes'] = notes;

    if (body.isEmpty) {
      throw TenancyUpdateException('No fields provided to update.');
    }

    try {
      final res = await _client.dio.patch(
        '/v1/properties/$propertyId/tenancies/$tenancyId',
        data: body,
      );
      var row = _parseRow(res.data['data']);

      // Ensure financial columns are present — refetch if PATCH body omitted them.
      if (monthlyRent != null &&
          readAmount(row, ['monthly_rent', 'monthlyRent']) == null) {
        row = await getById(propertyId, tenancyId);
      }
      if (securityDeposit != null &&
          readAmount(row, ['security_deposit', 'securityDeposit']) == null) {
        row = await getById(propertyId, tenancyId);
      }

      if (monthlyRent != null) {
        final saved = readAmount(row, ['monthly_rent', 'monthlyRent']);
        if (saved == null || (saved - monthlyRent).abs() > 0.009) {
          throw TenancyUpdateException(
            'Monthly rent was not saved. The database may be missing the '
            'monthly_rent column — run migration 013 and redeploy the backend.',
          );
        }
      }

      if (securityDeposit != null) {
        final saved = readAmount(row, ['security_deposit', 'securityDeposit']);
        if (saved == null || (saved - securityDeposit).abs() > 0.009) {
          throw TenancyUpdateException(
            'Security deposit was not saved. Please retry after the backend syncs.',
          );
        }
      }

      return row;
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response!.data as Map)['error']?.toString()
          : null;
      throw TenancyUpdateException(
        msg ?? e.message ?? 'Network error while updating tenancy.',
      );
    } on TenancyUpdateException {
      rethrow;
    } catch (e) {
      throw TenancyUpdateException('Could not update tenancy: $e');
    }
  }

  Future<void> uploadAgreement(
      String propertyId, String tenancyId, String filePath) async {
    final formData = FormData.fromMap({
      'agreement':
          await MultipartFile.fromFile(filePath, filename: 'agreement.pdf'),
    });
    await _client.dio.post(
      '/v1/properties/$propertyId/tenancies/$tenancyId/agreement',
      data: formData,
    );
  }

  String get baseUrl => _client.dio.options.baseUrl;
}
