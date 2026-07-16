// features/staff/data/staff_repository.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

final staffRepositoryProvider = Provider<StaffRepository>((ref) {
  return StaffRepository(ref.watch(apiClientProvider));
});

class StaffRepository {
  final ApiClient _client;
  StaffRepository(this._client);

  Future<List<Map<String, dynamic>>> listForProperty(String propertyId) async {
    final res = await _client.dio.get('/v1/properties/$propertyId/staff');
    return List<Map<String, dynamic>>.from(res.data['data']);
  }

  Future<void> assign(String propertyId, String phone, String role) async {
    await _client.dio.post('/v1/properties/$propertyId/staff', data: {
      'phone': phone,
      'role': role,
    });
  }

  Future<void> remove(String propertyId, String staffId) async {
    await _client.dio.delete('/v1/properties/$propertyId/staff/$staffId');
  }
  Future<List<Map<String, dynamic>>> listMyInvitations() async {
    final res = await _client.dio.get('/v1/invitations');
    return List<Map<String, dynamic>>.from(res.data['data']);
  }

  Future<void> acceptInvitation(String assignmentId) async {
    await _client.dio.post('/v1/invitations/$assignmentId/accept');
  }

  Future<void> declineInvitation(String assignmentId) async {
    await _client.dio.post('/v1/invitations/$assignmentId/decline');
  }
}