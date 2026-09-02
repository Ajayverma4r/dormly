import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

/// Maximum allowed image size after compression (100 KB).
const int kMaxImageBytes = 102400;

class ImageCompressResult {
  final File? file;
  final String? errorMessage;

  const ImageCompressResult({this.file, this.errorMessage});

  bool get success => file != null;
}

/// Compresses [file] to JPEG, targeting under [kMaxImageBytes].
Future<ImageCompressResult> compressImage(File file) async {
  final dir = await getTemporaryDirectory();
  const qualities = [60, 50, 40, 30, 20, 15];

  for (final quality in qualities) {
    final outPath =
        '${dir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}_$quality.jpg';
    final result = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      outPath,
      quality: quality,
      minWidth: 800,
      minHeight: 800,
      format: CompressFormat.jpeg,
    );
    if (result == null) continue;

    final compressed = File(result.path);
    final size = await compressed.length();
    if (size <= kMaxImageBytes) {
      return ImageCompressResult(file: compressed);
    }
  }

  return const ImageCompressResult(
    errorMessage:
        'Please select a smaller or less complex image (max 100 KB).',
  );
}
