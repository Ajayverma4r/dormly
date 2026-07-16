// features/complaints/data/complaints_repository.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

final complaintsRepositoryProvider = Provider<ComplaintsRepository>((ref) {
  return ComplaintsRepository(ref.watch(apiClientProvider));
});

class ComplaintsRepository {
  final ApiClient _client;
  ComplaintsRepository(this._client);

  Future<List<Map<String, dynamic>>> listForProperty(String propertyId) async {
    final res = await _client.dio.get('/v1/properties/$propertyId/complaints');
    return List<Map<String, dynamic>>.from(res.data['data']);
  }

  Future<void> updateStatus(String propertyId, String complaintId, String status, {String? resolutionNote}) async {
    await _client.dio.patch('/v1/properties/$propertyId/complaints/$complaintId', data: {
      'status': status,
      if (resolutionNote != null) 'resolutionNote': resolutionNote,
    });
  }

  // Tenant-facing
  Future<List<Map<String, dynamic>>> myComplaints() async {
    final res = await _client.dio.get('/v1/tenant-portal/complaints');
    return List<Map<String, dynamic>>.from(res.data['data']);
  }

  Future<void> raiseMine({
    required String propertyId,
    required String nodeId,
    required String category,
    required String description,
    String priority = 'medium',
  }) async {
    await _client.dio.post('/v1/tenant-portal/complaints', data: {
      'propertyId': propertyId,
      'nodeId': nodeId,
      'category': category,
      'description': description,
      'priority': priority,
    });
  }
}