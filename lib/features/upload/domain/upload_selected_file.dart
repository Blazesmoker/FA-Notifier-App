import 'dart:convert';
import 'dart:typed_data';

class UploadSelectedFile {
  const UploadSelectedFile({
    required this.fileName,
    required this.base64Data,
    required this.extension,
  });

  final String fileName;
  final String base64Data;
  final String extension;

  Uint8List get bytes => base64Decode(base64Data);

  String get mimeType => switch (extension.toLowerCase()) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'gif' => 'image/gif',
        _ => 'application/octet-stream',
      };

  factory UploadSelectedFile.fromBytes({
    required String fileName,
    required Uint8List bytes,
    required String extension,
  }) {
    return UploadSelectedFile(
      fileName: fileName,
      base64Data: base64Encode(bytes),
      extension: extension,
    );
  }
}
