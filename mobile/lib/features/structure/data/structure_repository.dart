// features/structure/data/structure_repository.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../domain/hierarchy_level.dart';

final structureRepositoryProvider = Provider<StructureRepository>((ref) {
  return StructureRepository(ref.watch(apiClientProvider));
});

class StructureRepository {
  final ApiClient _client;
  StructureRepository(this._client);

  Future<List<HierarchyLevel>> listLevels(String propertyId) async {
    final res = await _client.dio.get('/v1/properties/$propertyId/structure/levels');
    final data = res.data['data'] as List;
    return data.map((e) => HierarchyLevel.fromJson(e)).toList();
  }

  Future<HierarchyLevel> createLevel(
    String propertyId, {
    required String displayName,
    required String internalKey,
    String? parentLevelId,
    String icon = 'grid',
  }) async {
    final res = await _client.dio.post('/v1/properties/$propertyId/structure/levels', data: {
      'displayName': displayName,
      'internalKey': internalKey,
      'parentLevelId': parentLevelId,
      'icon': icon,
    });
    return HierarchyLevel.fromJson(res.data['data']);
  }

  Future<HierarchyLevel> renameLevel(String propertyId, String levelId, String displayName) async {
    final res = await _client.dio.patch(
      '/v1/properties/$propertyId/structure/levels/$levelId',
      data: {'displayName': displayName},
    );
    return HierarchyLevel.fromJson(res.data['data']);
  }

  Future<HierarchyLevel> setEnabled(String propertyId, String levelId, bool isEnabled) async {
    final res = await _client.dio.patch(
      '/v1/properties/$propertyId/structure/levels/$levelId',
      data: {'isEnabled': isEnabled},
    );
    return HierarchyLevel.fromJson(res.data['data']);
  }

  Future<void> deleteLevel(String propertyId, String levelId, {bool force = false}) async {
    await _client.dio.delete(
      '/v1/properties/$propertyId/structure/levels/$levelId',
      queryParameters: force ? {'force': 'true'} : null,
    );
  }

  Future<void> reorder(String propertyId, List<String> orderedIds) async {
    await _client.dio.post(
      '/v1/properties/$propertyId/structure/levels/reorder',
      data: {'orderedIds': orderedIds},
    );
  }

  Future<int> countNodes(String propertyId, String levelId) async {
    final res = await _client.dio.get('/v1/properties/$propertyId/structure/nodes', queryParameters: {
      'levelId': levelId,
    });
    return (res.data['data'] as List).length;
  }
  Future<List<Map<String, dynamic>>> listNodes(
    String propertyId,
    String levelId, {
    String? parentNodeId,
  }) async {
    final res = await _client.dio.get('/v1/properties/$propertyId/structure/nodes', queryParameters: {
      'levelId': levelId,
      if (parentNodeId != null) 'parentNodeId': parentNodeId,
    });
    return List<Map<String, dynamic>>.from(res.data['data']);
  }

  Future<Map<String, dynamic>> createNode(
    String propertyId, {
    required String levelId,
    String? parentNodeId,
    required String name,
    String? code,
  }) async {
    final res = await _client.dio.post('/v1/properties/$propertyId/structure/nodes', data: {
      'levelId': levelId,
      'parentNodeId': parentNodeId,
      'name': name,
      'code': code,
    });
    return Map<String, dynamic>.from(res.data['data']);
  }

  Future<Map<String, dynamic>> renameNode(String propertyId, String nodeId, String name) async {
    final res = await _client.dio.patch('/v1/properties/$propertyId/structure/nodes/$nodeId', data: {
      'name': name,
    });
    return Map<String, dynamic>.from(res.data['data']);
  }

  Future<void> deleteNode(String propertyId, String nodeId) async {
    await _client.dio.delete('/v1/properties/$propertyId/structure/nodes/$nodeId');
  }
}