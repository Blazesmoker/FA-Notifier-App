import 'dart:typed_data';

import 'package:FANotifier/shared/fa/fa_http.dart';
import 'package:FANotifier/shared/fa/fa_media_auth.dart';
import 'package:FANotifier/shared/fa/network.dart';

class OpenPostImageService {
  const OpenPostImageService();

  Future<Uint8List?> fetchImageBytes(String imageUrl) async {
    final response = await httpClient.get(
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
