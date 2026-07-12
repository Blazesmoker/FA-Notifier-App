import 'dart:typed_data';
import 'dart:ui' as ui;

class ProfileAvatarTransparencyDetector {
  const ProfileAvatarTransparencyDetector();

  Future<bool> hasTransparentEdge(ui.Image image) async {
    final ByteData? bytes =
        await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bytes == null || image.width <= 0 || image.height <= 0) {
      return false;
    }

    bool isTransparentAt(int x, int y) {
      final int alphaIndex = ((y * image.width + x) * 4) + 3;
      return bytes.getUint8(alphaIndex) < 255;
    }

    for (int x = 0; x < image.width; x++) {
      if (isTransparentAt(x, 0) || isTransparentAt(x, image.height - 1)) {
        return true;
      }
    }
    for (int y = 0; y < image.height; y++) {
      if (isTransparentAt(0, y) || isTransparentAt(image.width - 1, y)) {
        return true;
      }
    }
    return false;
  }
}
