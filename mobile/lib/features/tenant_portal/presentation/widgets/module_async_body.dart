// features/tenant_portal/presentation/widgets/module_async_body.dart
//
// Local loading / error shells so a failed feature never blanks the dashboard.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _muted = Color(0xFF64748B);
const _brand = Color(0xFF5218D1);

class ModuleAsyncBody<T> extends StatelessWidget {
  final AsyncValue<T> async;
  final Widget Function(T data) builder;
  final String errorLabel;
  final VoidCallback? onRetry;
  final double skeletonHeight;

  const ModuleAsyncBody({
    super.key,
    required this.async,
    required this.builder,
    this.errorLabel = 'Failed to load',
    this.onRetry,
    this.skeletonHeight = 72,
  });

  @override
  Widget build(BuildContext context) {
    return async.when(
      loading: () => _Skeleton(height: skeletonHeight),
      error: (e, _) => _ModuleError(
        label: errorLabel,
        detail: e.toString(),
        onRetry: onRetry,
      ),
      data: builder,
    );
  }
}

class _Skeleton extends StatelessWidget {
  final double height;
  const _Skeleton({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}

class _ModuleError extends StatelessWidget {
  final String label;
  final String detail;
  final VoidCallback? onRetry;

  const _ModuleError({
    required this.label,
    required this.detail,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF991B1B),
                    fontSize: 13,
                  ),
                ),
                Text(
                  detail.length > 80 ? '${detail.substring(0, 80)}…' : detail,
                  style: const TextStyle(fontSize: 11, color: _muted),
                ),
              ],
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(foregroundColor: _brand),
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}
