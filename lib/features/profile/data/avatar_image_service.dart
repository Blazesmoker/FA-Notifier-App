import 'dart:typed_data';

import 'package:FANotifier/features/profile/domain/avatar_image_data.dart';
import 'package:FANotifier/shared/fa/fa_default_image_loader.dart';
import 'package:FANotifier/shared/fa/fa_http.dart';
import 'package:FANotifier/shared/fa/fa_media_auth.dart';

Future<AvatarImageData> fetchAvatarImageData(String imageUrl) async {
  final response = await FAHttp.getMedia(
    Uri.parse(imageUrl),
    headers: await FaMediaAuth.headersForUrl(imageUrl) ??
        {'User-Agent': FAHttp.userAgent},
  );
  final bytes = response.statusCode == 200
      ? response.bodyBytes
      : await loadDefaultAvatarImageBytes();
  final extension = avatarImageExtensionFromUrlOrContentType(
    imageUrl,
    response.headers['content-type'],
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
