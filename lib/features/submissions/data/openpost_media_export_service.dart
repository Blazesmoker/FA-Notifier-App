import 'dart:typed_data';

import 'package:FANotifier/shared/fa/fa_default_image_loader.dart';
import 'package:FANotifier/shared/platform/image_export_service.dart';

class OpenPostMediaExportService {
  const OpenPostMediaExportService({
    ImageExportService imageExportService = const ImageExportService(),
  }) : _imageExportService = imageExportService;

  final ImageExportService _imageExportService;

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
