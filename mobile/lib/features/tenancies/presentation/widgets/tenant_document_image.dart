// features/tenancies/presentation/widgets/tenant_document_image.dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/tenancy_repository.dart';

typedef TenantDocumentRef = ({
  String propertyId,
  String tenancyId,
  String documentId,
});

/// Bytes of a private ID document, loaded through the authenticated API.
final tenantDocumentBytesProvider =
    FutureProvider.autoDispose.family<Uint8List, TenantDocumentRef>(
  (ref, doc) => ref
      .watch(tenancyRepositoryProvider)
      .documentFile(doc.propertyId, doc.tenancyId, doc.documentId),
);

/// Id of the first stored document whose type is in [types].
String? storedDocumentId(
  List<Map<String, dynamic>> docs,
  Set<String> types,
) {
  for (final d in docs) {
    final t = (d['doc_type'] ?? d['docType'])?.toString().toLowerCase() ?? '';
    final id = d['id']?.toString();
    if (types.contains(t) && id != null && id.isNotEmpty) return id;
  }
  return null;
}

void openTenantDocumentViewer(
  BuildContext context,
  TenantDocumentRef doc, {
  String title = 'ID Card',
}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => TenantDocumentViewerScreen(document: doc, title: title),
    ),
  );
}

class TenantDocumentThumbnail extends ConsumerWidget {
  final TenantDocumentRef document;
  final double width;
  final double height;

  const TenantDocumentThumbnail({
    super.key,
    required this.document,
    this.width = 96,
    this.height = 60,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(tenantDocumentBytesProvider(document));
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: width,
        height: height,
        child: bytes.when(
          data: (b) => Image.memory(
            b,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _placeholder(),
          ),
          loading: () => Container(
            color: AppColors.hairline,
            alignment: Alignment.center,
            child: const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          error: (_, __) => _placeholder(),
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: AppColors.hairline,
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image_outlined, color: AppColors.slate),
      );
}

class TenantDocumentViewerScreen extends ConsumerWidget {
  final TenantDocumentRef document;
  final String title;

  const TenantDocumentViewerScreen({
    super.key,
    required this.document,
    this.title = 'ID Card',
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(tenantDocumentBytesProvider(document));
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title),
      ),
      body: Center(
        child: bytes.when(
          data: (b) => InteractiveViewer(
            maxScale: 5,
            child: Image.memory(
              b,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const _ViewerMessage(
                'This file could not be shown as an image.',
              ),
            ),
          ),
          loading: () => const CircularProgressIndicator(color: Colors.white),
          error: (_, __) => _ViewerMessage(
            'Could not load the document.',
            onRetry: () => ref.invalidate(tenantDocumentBytesProvider(document)),
          ),
        ),
      ),
    );
  }
}

class _ViewerMessage extends StatelessWidget {
  final String text;
  final VoidCallback? onRetry;

  const _ViewerMessage(this.text, {this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text, style: const TextStyle(color: Colors.white)),
        if (onRetry != null)
          TextButton(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
      ],
    );
  }
}
