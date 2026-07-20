import 'dart:typed_data';

import 'package:fanotifier/features/submissions/data/openpost_image_service.dart';
import 'package:fanotifier/features/submissions/domain/openpost_media_export_result.dart';
import 'package:fanotifier/shared/fa/fa_default_image_loader.dart';
import 'package:fanotifier/shared/platform/image_export_service.dart';

class OpenPostMediaExportService {
  const OpenPostMediaExportService({
    ImageExportService imageExportService = const ImageExportService(),
  }) : _imageExportService = imageExportService;

  final ImageExportService _imageExportService;

  Future<OpenPostMediaExportResult> exportToGallery(String imageUrl) async {
    if (!await requestImageExportPermission()) {
      return const OpenPostMediaExportResult(
        OpenPostMediaExportStatus.permissionDenied,
      );
    }
    final bytes =
        await const OpenPostImageService().fetchImageBytes(imageUrl) ??
            await loadDefaultImageBytes();
    final saved = await saveImageToGallery(bytes);
    return OpenPostMediaExportResult(
      saved
          ? OpenPostMediaExportStatus.success
          : OpenPostMediaExportStatus.saveFailed,
    );
  }

  Future<OpenPostMediaExportResult> shareFromUrl(String imageUrl) async {
    if (!await requestImageExportPermission()) {
      return const OpenPostMediaExportResult(
        OpenPostMediaExportStatus.permissionDenied,
      );
    }
    final bytes =
        await const OpenPostImageService().fetchImageBytes(imageUrl) ??
            await loadDefaultImageBytes();
    await shareImage(bytes);
    return const OpenPostMediaExportResult(
      OpenPostMediaExportStatus.success,
    );
  }

  Future<bool> requestImageExportPermission() {
    return _imageExportService.requestImageExportPermission();
  }

  Future<Uint8List> loadDefaultImageBytes() {
    return loadFaDefaultImageBytes();
  }

  Future<bool> saveImageToGallery(Uint8List bytes) {
    return _imageExportService.saveImageToGallery(
      bytes,
      quality: 80,
      fileName: 'image_${DateTime.now().millisecondsSinceEpoch}.jpg',
      skipIfExists: false,
      androidRelativePath: 'Pictures/YourAppName/images',
    );
  }

  Future<void> shareImage(Uint8List bytes) {
    return _imageExportService.shareImage(
      bytes,
      fileName: 'shared_image_${DateTime.now().millisecondsSinceEpoch}.jpg',
      recursiveCreate: false,
    );
  }
}
