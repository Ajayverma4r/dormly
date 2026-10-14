// features/tenant_portal/presentation/widgets/tenant_load_error.dart
//
// Friendly load-failure state for tenant screens. Raw exception text, server
// messages and stack traces are never shown to the tenant.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _brand = Color(0xFF5218D1);
const _border = Color(0xFFE5E7EB);

String tenantLoadErrorMessage(Object error) {
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return "We couldn't reach Dormly. Check your internet connection and try again.";
      default:
        break;
    }
    final status = error.response?.statusCode;
    if (status == 401 || status == 403) {
      return "We couldn't confirm access to your stay. Please sign in again.";
    }
    if (status == 404) {
      return "We couldn't find an active stay for your account.";
    }
  }
  return 'Something went wrong on our side. Please try again in a moment.';
}

class TenantLoadError extends StatelessWidget {
  final String title;
  final Object error;
  final VoidCallback onRetry;
  final bool compact;

  const TenantLoadError({
    super.key,
    required this.title,
    required this.error,
    required this.onRetry,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final message = tenantLoadErrorMessage(error);
    final retry = OutlinedButton.icon(
      onPressed: onRetry,
      icon: const Icon(Icons.refresh_rounded, size: 18),
      label: const Text('Retry'),
      style: OutlinedButton.styleFrom(
        foregroundColor: _brand,
        side: const BorderSide(color: _brand),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

    if (compact) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: Row(
          children: [
            const Icon(Icons.cloud_off_rounded, color: _muted, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    style: const TextStyle(fontSize: 12, color: _muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            retry,
          ],
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFFF3E8FF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.cloud_off_rounded,
                  color: _brand, size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: _ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: _muted, height: 1.4),
            ),
            const SizedBox(height: 18),
            retry,
          ],
        ),
      ),
    );
  }
}
