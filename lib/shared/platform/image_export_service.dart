import 'dart:io';
import 'dart:typed_data';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:share_plus/share_plus.dart';

import 'package:fanotifier/core/logging/app_logging.dart';

class ImageExportService {
  const ImageExportService();

  Future<bool> requestImageExportPermission() async {
    if (Platform.isAndroid) {
      return _requestAndroidPermission();
    }
    if (Platform.isIOS) {
      return (await Permission.photosAddOnly.request()).isGranted;
    }
    return false;
  }

  Future<bool> saveImageToGallery(
    Uint8List bytes, {
    required String fileName,
    required String androidRelativePath,
    required bool skipIfExists,
  }) async {
    final originalFileName = _imageFileName(bytes, fileName);
    final tempDir = await Directory.systemTemp.createTemp(
      'fanotifier_image_export_',
    );
    try {
      final tempFile = File('${tempDir.path}/$originalFileName');
      await tempFile.writeAsBytes(bytes);
      final result = await SaverGallery.saveFiles(
        [
          SaveFileData(
            filePath: tempFile.path,
            fileName: originalFileName,
            albumPath: androidRelativePath,
          ),
        ],
        skipIfExists: skipIfExists,
      );
      return result.isSuccess;
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } on FileSystemException {
        kDebugPrint('[ImageExport] Temporary export cleanup failed.');
      }
    }
  }

  Future<void> shareImage(
    Uint8List bytes, {
    required String fileName,
    required bool recursiveCreate,
  }) async {
    final tempDir = Directory.systemTemp;
    final originalFileName = _imageFileName(bytes, fileName);
    final tempFile = await File(
      '${tempDir.path}/$originalFileName',
    ).create(recursive: recursiveCreate);
    await tempFile.writeAsBytes(bytes);

    await SharePlus.instance.share(
      ShareParams(files: [XFile(tempFile.path)]),
    );
  }

  String _imageFileName(Uint8List bytes, String fileName) {
    final extension = _imageExtension(bytes);
    if (extension == null) {
      return fileName;
    }
    final extensionIndex = fileName.lastIndexOf('.');
    final name = extensionIndex > 0
        ? fileName.substring(0, extensionIndex)
        : fileName;
    return '$name.$extension';
  }

  String? _imageExtension(Uint8List bytes) {
    const signatures = <String, List<int>>{
      'jpg': [0xff, 0xd8, 0xff],
      'png': [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
      'gif': [0x47, 0x49, 0x46, 0x38],
      'bmp': [0x42, 0x4d],
      'tiff': [0x49, 0x49, 0x2a, 0x00],
    };
    for (final signature in signatures.entries) {
      if (_matchesHeader(bytes, signature.value)) {
        return signature.key;
      }
    }
    if (_matchesHeader(bytes, const [0x4d, 0x4d, 0x00, 0x2a])) {
      return 'tiff';
    }
    if (_matchesHeader(bytes, const [0x52, 0x49, 0x46, 0x46]) &&
        _matchesHeader(bytes, const [0x57, 0x45, 0x42, 0x50], offset: 8)) {
      return 'webp';
    }
    return null;
  }

  bool _matchesHeader(
    Uint8List bytes,
    List<int> signature, {
    int offset = 0,
  }) {
    if (bytes.length < offset + signature.length) {
      return false;
    }
    for (var index = 0; index < signature.length; index++) {
      if (bytes[offset + index] != signature[index]) {
        return false;
      }
    }
    return true;
  }

  Future<bool> _requestAndroidPermission() async {
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final sdkInt = androidInfo.version.sdkInt;

    if (sdkInt >= 33) {
      final status = await Permission.photos.request();
      return status.isGranted;
    }

    final status = await Permission.storage.request();
    return status.isGranted;
  }
}
