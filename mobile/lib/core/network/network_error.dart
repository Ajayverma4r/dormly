// core/network/network_error.dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

String networkErrorMessage(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['error'] != null) {
      return data['error'].toString();
    }
    final status = error.response?.statusCode;
    if (status == 401) {
      return 'Session expired. Please log out and sign in again.';
    }
    if (status == 404) {
      return 'This property could not be found. Pull to refresh or pick it again from the list.';
    }
    if (status != null) {
      return 'Server error ($status). Please try again.';
    }

    final raw = '${error.error ?? ''} ${error.message ?? ''}'.toLowerCase();
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        raw.contains('connection abort') ||
        raw.contains('connection reset') ||
        raw.contains('failed host lookup') ||
        error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.unknown) {
      return 'Could not reach the server. Check your connection and try again. If you just opened the app, the backend may still be waking up.';
    }
  }
  return 'Something went wrong. Please try again.';
}

class DormlyLoadError extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const DormlyLoadError({
    super.key,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.wifi_off_outlined,
              size: 48,
              color: AppColors.slate,
            ),
            const SizedBox(height: 16),
            const Text(
              'Could not load this property',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              networkErrorMessage(error),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.4,
                color: AppColors.slate,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
