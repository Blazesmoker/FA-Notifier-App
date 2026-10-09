import 'dart:typed_data';

import 'package:fanotifier/features/profile/domain/avatar_image_data.dart';
import 'package:fanotifier/shared/fa/fa_default_image_loader.dart';
import 'package:fanotifier/core/media/domain/media_bytes_repository.dart';

Future<AvatarImageData> fetchAvatarImageData(
  String imageUrl, {
  required MediaBytesRepository mediaBytesRepository,
}) async {
  final response = await mediaBytesRepository.load(
    imageUrl,
    purpose: MediaLoadPurpose.download,
  );
  final bytes = response.statusCode == 200
      ? response.bytes
      : await loadDefaultAvatarImageBytes();
  final extension = avatarImageExtensionFromUrlOrContentType(
    imageUrl,
    response.contentType,
  );

  return AvatarImageData(
    bytes: bytes,
    extension: extension,
  );
}

Future<Uint8List> loadDefaultAvatarImageBytes() async {
  return loadFaDefaultImageBytes();
}

String avatarImageExtensionFromUrlOrContentType(
  String url,
  String? contentType,
) {
  final path = Uri.parse(url).path.toLowerCase();
  for (final ext in ['.png', '.jpg', '.jpeg', '.gif', '.webp']) {
    if (path.endsWith(ext)) return ext;
  }
  switch ((contentType ?? '').toLowerCase()) {
    case 'image/png':
      return '.png';
    case 'image/jpeg':
      return '.jpg';
    case 'image/gif':
      return '.gif';
    case 'image/webp':
      return '.webp';
  }
  return '.jpg';
}

bool isJpegAvatarExtension(String ext) => ext == '.jpg' || ext == '.jpeg';
