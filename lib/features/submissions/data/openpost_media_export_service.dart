import 'dart:io';
import 'dart:typed_data';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:share_plus/share_plus.dart';

class OpenPostMediaExportService {
  const OpenPostMediaExportService();

  Future<bool> requestImageExportPermission() async {
    if (Platform.isAndroid) {
      return _requestAndroidPermission();
    }
    if (Platform.isIOS) {
      return (await Permission.photosAddOnly.request()).isGranted;
    }
    return false;
  }

  Future<Uint8List> loadDefaultImageBytes() async {
    final byteData = await rootBundle.load('assets/images/defaultpic.gif');
    return byteData.buffer.asUint8List();
  }

  Future<bool> saveImageToGallery(Uint8List bytes) async {
    final result = await SaverGallery.saveImage(
      bytes,
      quality: 80,
      fileName: 'image_${DateTime.now().millisecondsSinceEpoch}.jpg',
      skipIfExists: false,
      androidRelativePath: 'Pictures/YourAppName/images',
    );
    return result.isSuccess;
  }

  Future<void> shareImage(Uint8List bytes) async {
    final tempDir = Directory.systemTemp;
    final tempFile = await File(
      '${tempDir.path}/shared_image_${DateTime.now().millisecondsSinceEpoch}.jpg',
    ).create();
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
