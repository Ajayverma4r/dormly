// features/tenancies/presentation/utils/tenancy_errors.dart
import 'package:dio/dio.dart';

/// Turns API / network failures into user-facing messages for tenancy actions.
String tenancyErrorMessage(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map) {
      final msg = data['error'];
      if (msg is String && msg.isNotEmpty) return msg;
      final details = data['details'];
      if (details is List && details.isNotEmpty) {
        final first = details.first;
        if (first is Map && first['message'] != null) {
          return first['message'].toString();
        }
      }
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return 'Request timed out. Check your connection and try again.';
    }
    if (error.response?.statusCode == 403) {
      return 'You do not have permission to add tenants to this property.';
    }
    if (error.response?.statusCode == 401) {
      return 'Your session expired. Please log in again.';
    }
  }
  return error.toString().replaceFirst('Exception: ', '');
}
