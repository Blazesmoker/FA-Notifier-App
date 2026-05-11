import 'dart:typed_data';

class AvatarImageData {
  const AvatarImageData({
    required this.bytes,
    required this.extension,
  });

  final Uint8List bytes;
  final String extension;
}
