// features/properties/data/properties_repository.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

final propertiesRepositoryProvider = Provider<PropertiesRepository>((ref) {
  return PropertiesRepository(ref.watch(apiClientProvider));
});

class PropertiesRepository {
  final ApiClient _client;
  PropertiesRepository(this._client);

  Future<List<dynamic>> list(String organizationId) async {
    final res = await _client.dio.get('/v1/properties', queryParameters: {
      'organizationId': organizationId,
    });
    return res.data['data'] as List;
  }

  Future<Map<String, dynamic>> create(Map<String, dynamic> body) async {
    final res = await _client.dio.post('/v1/properties', data: body);
    return res.data['data'];
  }

  Future<List<dynamic>> listTypes() async {
    final res = await _client.dio.get('/v1/property-types');
    return res.data['data'] as List;
  }

  Future<Map<String, dynamic>> getById(String propertyId) async {
    final res = await _client.dio.get('/v1/properties/$propertyId');
    return Map<String, dynamic>.from(res.data['data']);
  }

  // Returns raw template rows (snake_case, straight from Postgres) —
  // display_name, internal_key, parent_template_id, icon, order_index, etc.
  Future<List<Map<String, dynamic>>> previewTemplate(String typeKey) async {
    final res = await _client.dio.get('/v1/property-types/$typeKey/template');
    return List<Map<String, dynamic>>.from(res.data['data']);
  }
}