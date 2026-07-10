import 'dart:io';
import 'dart:typed_data';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:share_plus/share_plus.dart';

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
    required int quality,
    required String fileName,
    required String androidRelativePath,
    required bool skipIfExists,
  }) async {
    final result = await SaverGallery.saveImage(
      bytes,
      quality: quality,
      fileName: fileName,
      skipIfExists: skipIfExists,
      androidRelativePath: androidRelativePath,
    );
    return result.isSuccess;
  }

  Future<void> shareImage(
    Uint8List bytes, {
    required String fileName,
    required bool recursiveCreate,
  }) async {
    final tempDir = Directory.systemTemp;
    final tempFile =
        await File('${tempDir.path}/$fileName').create(recursive: recursiveCreate);
    await tempFile.writeAsBytes(bytes);

    await SharePlus.instance.share(
      ShareParams(files: [XFile(tempFile.path)]),
    );
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
