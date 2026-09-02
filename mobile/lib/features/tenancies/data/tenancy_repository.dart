// features/tenancies/data/tenancy_repository.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import 'package:dio/dio.dart';

final tenancyRepositoryProvider = Provider<TenancyRepository>((ref) {
  return TenancyRepository(ref.watch(apiClientProvider));
});

/// Thrown when a tenancy update fails or the updated row cannot be verified.
class TenancyUpdateException implements Exception {
  final String message;
  TenancyUpdateException(this.message);

  @override
  String toString() => message;
}

class TenancyRepository {
  final ApiClient _client;
  TenancyRepository(this._client);

  static void _requireNonEmptyId(String value, String label) {
    if (value.trim().isEmpty) {
      throw TenancyUpdateException('$label is missing. Cannot update tenancy.');
    }
  }

  String _tenancyPatchPath(String propertyId, String tenancyId) {
    _requireNonEmptyId(propertyId, 'Property ID');
    _requireNonEmptyId(tenancyId, 'Tenancy ID');
    return '/v1/properties/${propertyId.trim()}/tenancies/${tenancyId.trim()}';
  }

  Map<String, dynamic> _parseRow(dynamic data) {
    if (data == null || data is! Map) {
      throw TenancyUpdateException('Server returned an empty tenancy response.');
    }
    return Map<String, dynamic>.from(data);
  }

  String _dioFriendlyMessage(DioException e, {String? action}) {
    final status = e.response?.statusCode;
    if (status == 404) {
      return 'Endpoint not found (404). Please ensure the backend is fully deployed.';
    }
    if (status == 403) {
      return 'You do not have permission to update this tenancy.';
    }
    if (status == 401) {
      return 'Session expired. Please log in again.';
    }
    final body = e.response?.data;
    if (body is Map && body['error'] != null) {
      return body['error'].toString();
    }
    final verb = action ?? 'complete this request';
    return 'Network error while trying to $verb.';
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
    _requireNonEmptyId(propertyId, 'Property ID');
    _requireNonEmptyId(nodeId, 'Node ID');
    final res = await _client.dio.get(
      '/v1/properties/${propertyId.trim()}/tenancies',
      queryParameters: {'nodeId': nodeId.trim()},
    );
    return (res.data['data'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> listByProperty(String propertyId) async {
    _requireNonEmptyId(propertyId, 'Property ID');
    final res =
        await _client.dio.get('/v1/properties/${propertyId.trim()}/tenancies');
    return (res.data['data'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  /// Reload a tenancy using list endpoints (compatible with all deployed backends).
  Future<Map<String, dynamic>> _reloadTenancy({
    required String propertyId,
    required String tenancyId,
    String? nodeId,
  }) async {
    if (nodeId != null && nodeId.trim().isNotEmpty) {
      try {
        final rows = await listByNode(propertyId, nodeId);
        for (final row in rows) {
          if (row['id']?.toString() == tenancyId) return row;
        }
      } on DioException {
        // Fall through to property-wide list.
      }
    }

    final rows = await listByProperty(propertyId);
    for (final row in rows) {
      if (row['id']?.toString() == tenancyId) return row;
    }

    throw TenancyUpdateException(
      'Updated tenancy could not be reloaded. Pull down to refresh the screen.',
    );
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

    final res = await _client.dio.post(
      '/v1/properties/${propertyId.trim()}/tenancies',
      data: body,
    );
    return _parseRow(res.data['data']);
  }

  Future<void> endTenancy(String propertyId, String tenancyId) async {
    await _client.dio.post('${_tenancyPatchPath(propertyId, tenancyId)}/end');
  }

  /// PATCH tenancy profile / financial fields.
  Future<Map<String, dynamic>> update(
    String propertyId,
    String tenancyId, {
    String? nodeId,
    double? monthlyRent,
    double? securityDeposit,
    String? fullName,
    String? email,
    String? address,
    String? notes,
    String? occupation,
    String? emergencyContactName,
    String? emergencyContactRelation,
    String? emergencyContactPhone,
    String? idType,
    String? aadhaarNumber,
    bool? policeVerificationDone,
    String? kycStatus,
    String? companyName,
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
    if (address != null) body['address'] = address;
    if (notes != null) body['notes'] = notes;
    if (occupation != null) body['occupation'] = occupation;
    if (emergencyContactName != null) {
      body['emergencyContactName'] = emergencyContactName;
      body['emergency_contact_name'] = emergencyContactName;
    }
    if (emergencyContactRelation != null) {
      body['emergencyContactRelation'] = emergencyContactRelation;
      body['emergency_contact_relation'] = emergencyContactRelation;
    }
    if (emergencyContactPhone != null) {
      body['emergencyContactPhone'] = emergencyContactPhone;
      body['emergency_contact_phone'] = emergencyContactPhone;
    }
    if (idType != null) {
      body['idType'] = idType;
      body['id_type'] = idType;
    }
    if (aadhaarNumber != null) body['aadhaarNumber'] = aadhaarNumber;
    if (policeVerificationDone != null) {
      body['policeVerificationDone'] = policeVerificationDone;
      body['police_verification_done'] = policeVerificationDone;
    }
    if (kycStatus != null) {
      body['kycStatus'] = kycStatus;
      body['kyc_status'] = kycStatus;
    }
    if (companyName != null) body['companyName'] = companyName;

    if (body.isEmpty) {
      throw TenancyUpdateException('No fields provided to update.');
    }

    final path = _tenancyPatchPath(propertyId, tenancyId);

    try {
      final res = await _client.dio.patch(path, data: body);
      var row = _parseRow(res.data['data']);

      // Re-load via list API if PATCH response omits financial columns.
      final needsRentCheck = monthlyRent != null &&
          readAmount(row, ['monthly_rent', 'monthlyRent']) == null;
      final needsDepositCheck = securityDeposit != null &&
          readAmount(row, ['security_deposit', 'securityDeposit']) == null;

      if (needsRentCheck || needsDepositCheck) {
        row = await _reloadTenancy(
          propertyId: propertyId,
          tenancyId: tenancyId,
          nodeId: nodeId,
        );
      }

      if (monthlyRent != null) {
        final saved = readAmount(row, ['monthly_rent', 'monthlyRent']);
        if (saved == null || (saved - monthlyRent).abs() > 0.009) {
          throw TenancyUpdateException(
            'Monthly rent was not saved. Deploy the latest backend and run '
            'migration 013 (monthly_rent column).',
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
      throw TenancyUpdateException(
        _dioFriendlyMessage(e, action: 'update tenancy'),
      );
    } on TenancyUpdateException {
      rethrow;
    } catch (e) {
      throw TenancyUpdateException('Could not update tenancy: $e');
    }
  }

  Future<List<Map<String, dynamic>>> listDocuments(
      String propertyId, String tenancyId) async {
    final res = await _client.dio.get(
      '${_tenancyPatchPath(propertyId, tenancyId)}/documents',
    );
    return (res.data['data'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<Map<String, dynamic>> uploadProfilePhoto(
    String propertyId,
    String tenancyId,
    String filePath,
  ) async {
    try {
      final formData = FormData.fromMap({
        'photo': await MultipartFile.fromFile(filePath, filename: 'photo.jpg'),
      });
      final res = await _client.dio.post(
        '${_tenancyPatchPath(propertyId, tenancyId)}/profile-photo',
        data: formData,
      );
      return _parseRow(res.data['data']);
    } on DioException catch (e) {
      throw TenancyUpdateException(
        _dioFriendlyMessage(e, action: 'upload profile photo'),
      );
    }
  }

  Future<Map<String, dynamic>> uploadDocument(
    String propertyId,
    String tenancyId,
    String filePath, {
    required String docType,
  }) async {
    try {
      final formData = FormData.fromMap({
        'document':
            await MultipartFile.fromFile(filePath, filename: '$docType.jpg'),
        'docType': docType,
      });
      final res = await _client.dio.post(
        '${_tenancyPatchPath(propertyId, tenancyId)}/documents',
        data: formData,
      );
      return _parseRow(res.data['data']);
    } on DioException catch (e) {
      throw TenancyUpdateException(
        _dioFriendlyMessage(e, action: 'upload document'),
      );
    }
  }

  Future<void> uploadAgreement(
      String propertyId, String tenancyId, String filePath) async {
    final formData = FormData.fromMap({
      'agreement':
          await MultipartFile.fromFile(filePath, filename: 'agreement.pdf'),
    });
    await _client.dio.post(
      '${_tenancyPatchPath(propertyId, tenancyId)}/agreement',
      data: formData,
    );
  }

  String get baseUrl => _client.dio.options.baseUrl;
}
