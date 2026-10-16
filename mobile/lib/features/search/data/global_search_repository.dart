// features/search/data/global_search_repository.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../domain/global_search.dart';

final globalSearchRepositoryProvider = Provider<GlobalSearchRepository>((ref) {
  return GlobalSearchRepository(ref.watch(apiClientProvider));
});

class GlobalSearchRepository {
  final ApiClient _client;
  GlobalSearchRepository(this._client);

  /// Searches the signed-in workspace. Scope (organization, property or
  /// tenancy) comes from the token on the server, so none is sent here.
  Future<SearchResponse> search({
    required String query,
    SearchCategory? category,
    SearchQuickFilter? filter,
    CancelToken? cancelToken,
  }) async {
    final res = await _client.dio.get(
      '/v1/search',
      queryParameters: {
        if (query.trim().isNotEmpty) 'q': query.trim(),
        if (category != null) 'category': category.wire,
        if (filter != null) 'filter': filter.wire,
      },
      cancelToken: cancelToken,
    );
    return SearchResponse.fromJson((res.data as Map?)?['data']);
  }
}
