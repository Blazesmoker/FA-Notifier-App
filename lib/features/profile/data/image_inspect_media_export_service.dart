import 'package:FANotifier/features/profile/data/avatar_image_service.dart';
import 'package:FANotifier/features/profile/domain/avatar_image_data.dart';
import 'package:FANotifier/shared/platform/image_export_service.dart';

class ImageInspectMediaExportService {
  const ImageInspectMediaExportService({
    ImageExportService imageExportService = const ImageExportService(),
  }) : _imageExportService = imageExportService;

  final ImageExportService _imageExportService;

  Future<bool> requestImageExportPermission() {
    return _imageExportService.requestImageExportPermission();
  }

  Future<AvatarImageData> fetchImageData(String imageUrl) {
    return fetchAvatarImageData(imageUrl);
  }

  Future<bool> saveImageToGallery(AvatarImageData imageData) {
    final fileName =
        'avatar_${DateTime.now().millisecondsSinceEpoch}${imageData.extension}';
    return _imageExportService.saveImageToGallery(
      imageData.bytes,
      quality: isJpegAvatarExtension(imageData.extension) ? 100 : 100,
      fileName: fileName,
      skipIfExists: false,
      androidRelativePath: 'Pictures/YourAppName/images',
    );
  }

  Future<void> shareImage(AvatarImageData imageData) {
    final fileName =
        'shared_image_${DateTime.now().millisecondsSinceEpoch}${imageData.extension}';
    return _imageExportService.shareImage(
      imageData.bytes,
      fileName: fileName,
      recursiveCreate: true,
    );
  }
}
