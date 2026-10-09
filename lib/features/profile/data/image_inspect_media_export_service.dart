import 'package:fanotifier/features/profile/data/avatar_image_service.dart';
import 'package:fanotifier/features/profile/domain/avatar_image_data.dart';
import 'package:fanotifier/features/profile/domain/profile_media_export_repository.dart';
import 'package:fanotifier/shared/platform/image_export_service.dart';
import 'package:fanotifier/core/media/domain/media_bytes_repository.dart';

class ImageInspectMediaExportService implements ProfileMediaExportRepository {
  const ImageInspectMediaExportService({
    required this._mediaBytesRepository,
    this._imageExportService = const ImageExportService(),
  });

  final ImageExportService _imageExportService;
  final MediaBytesRepository _mediaBytesRepository;

  @override
  Future<bool> requestImageExportPermission() {
    return _imageExportService.requestImageExportPermission();
  }

  @override
  Future<AvatarImageData> fetchImageData(String imageUrl) {
    return fetchAvatarImageData(
      imageUrl,
      mediaBytesRepository: _mediaBytesRepository,
    );
  }

  @override
  Future<bool> saveImageToGallery(AvatarImageData imageData) {
    final fileName =
        'avatar_${DateTime.now().millisecondsSinceEpoch}${imageData.extension}';
    return _imageExportService.saveImageToGallery(
      imageData.bytes,
      fileName: fileName,
      skipIfExists: false,
      androidRelativePath: 'Pictures/YourAppName/images',
    );
  }

  @override
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
