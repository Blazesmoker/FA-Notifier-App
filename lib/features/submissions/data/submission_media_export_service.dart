import 'dart:typed_data';

import 'package:fanotifier/features/submissions/data/submission_image_service.dart';
import 'package:fanotifier/features/submissions/domain/submission_media_export_result.dart';
import 'package:fanotifier/shared/fa/fa_default_image_loader.dart';
import 'package:fanotifier/shared/platform/image_export_service.dart';

class SubmissionMediaExportService {
  const SubmissionMediaExportService({
    this._imageExportService = const ImageExportService(),
  });

  final ImageExportService _imageExportService;

  Future<SubmissionMediaExportResult> exportToGallery(String imageUrl) async {
    if (!await requestImageExportPermission()) {
      return const SubmissionMediaExportResult(
        SubmissionMediaExportStatus.permissionDenied,
      );
    }
    final bytes =
        await const SubmissionImageService().fetchImageBytes(imageUrl) ??
            await loadDefaultImageBytes();
    final saved = await saveImageToGallery(bytes);
    return SubmissionMediaExportResult(
      saved
          ? SubmissionMediaExportStatus.success
          : SubmissionMediaExportStatus.saveFailed,
    );
  }

  Future<SubmissionMediaExportResult> shareFromUrl(String imageUrl) async {
    if (!await requestImageExportPermission()) {
      return const SubmissionMediaExportResult(
        SubmissionMediaExportStatus.permissionDenied,
      );
    }
    final bytes =
        await const SubmissionImageService().fetchImageBytes(imageUrl) ??
            await loadDefaultImageBytes();
    await shareImage(bytes);
    return const SubmissionMediaExportResult(
      SubmissionMediaExportStatus.success,
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
