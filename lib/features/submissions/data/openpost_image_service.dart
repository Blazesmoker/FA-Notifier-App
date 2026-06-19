import 'dart:typed_data';

import 'package:FANotifier/shared/fa/fa_http.dart';
import 'package:FANotifier/shared/fa/fa_media_auth.dart';

class OpenPostImageService {
  const OpenPostImageService();

  Future<Uint8List?> fetchImageBytes(String imageUrl) async {
    final response = await FAHttp.getMedia(
      Uri.parse(imageUrl),
      headers: await FaMediaAuth.headersForUrl(imageUrl) ??
          {'User-Agent': FAHttp.userAgent},
    );
    if (response.statusCode != 200) {
      return null;
    }
    return response.bodyBytes;
  }
}
