import 'package:FANotifier/features/profile/domain/avatar_image_data.dart';

abstract interface class ProfileMediaExportRepository {
  Future<bool> requestImageExportPermission();

  Future<AvatarImageData> fetchImageData(String imageUrl);

  Future<bool> saveImageToGallery(AvatarImageData imageData);

  Future<void> shareImage(AvatarImageData imageData);
}
