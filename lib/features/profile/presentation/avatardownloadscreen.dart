import 'dart:io';
import 'package:flutter/material.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:share_plus/share_plus.dart';

import 'package:FANotifier/features/profile/data/avatar_image_service.dart';
import 'package:FANotifier/shared/widgets/PulsatingLoadingIndicator.dart';

class AvatarDownloadScreen extends StatelessWidget {
  final String imageUrl;

  const AvatarDownloadScreen({Key? key, required this.imageUrl}) : super(key: key);


  Future<void> _downloadImage(BuildContext context) async {
    try {
      bool isPermissionGranted = false;

      if (Platform.isAndroid) {
        isPermissionGranted = await _requestPermissionAndroid();
      } else if (Platform.isIOS) {
        isPermissionGranted = await Permission.photosAddOnly.request().isGranted;
      }

      if (!isPermissionGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo permission denied'), backgroundColor: Colors.red),
        );
        return;
      }

      final imageData = await fetchAvatarImageData(imageUrl);
      final filename =
          "avatar_${DateTime.now().millisecondsSinceEpoch}${imageData.extension}";


      final result = await SaverGallery.saveImage(
        imageData.bytes,
        quality: isJpegAvatarExtension(imageData.extension) ? 100 : 100,
        fileName: filename,
        skipIfExists: false,
        androidRelativePath: "Pictures/YourAppName/images",
      );

      if (result.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image saved to gallery!'), backgroundColor: Colors.green),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save image to gallery.'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to download image: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _shareImage(BuildContext context) async {
    try {
      bool isPermissionGranted = false;

      if (Platform.isAndroid) {
        isPermissionGranted = await _requestPermissionAndroid();
      } else if (Platform.isIOS) {
        isPermissionGranted = await Permission.photosAddOnly.request().isGranted;
      }

      if (!isPermissionGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permission denied'), backgroundColor: Colors.red),
        );
        return;
      }

      final imageData = await fetchAvatarImageData(imageUrl);
      final ext = imageData.extension;
      final filename = 'shared_image_${DateTime.now().millisecondsSinceEpoch}$ext';

      final tempDir = Directory.systemTemp;
      final tempFile = await File('${tempDir.path}/$filename').create(recursive: true);
      await tempFile.writeAsBytes(imageData.bytes);

      await SharePlus.instance.share(
        ShareParams(files: [XFile(tempFile.path)]),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to share image: $e'), backgroundColor: Colors.red),
      );
    }
  }
  Future<bool> _requestPermissionAndroid() async {
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final sdkInt = androidInfo.version.sdkInt;

    if (sdkInt >= 33) {
      final status = await Permission.photos.request();
      return status.isGranted;
    } else {
      // Android 12 and below
      final status = await Permission.storage.request();
      return status.isGranted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'download') {
                _downloadImage(context);
              } else if (value == 'share') {
                _shareImage(context);
              }
            },
            offset: const Offset(0, 40),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'download',
                child: Text('Download'),
              ),
              PopupMenuItem(
                value: 'share',
                child: Text('Share image'),
              ),
            ],
            icon: const Icon(Icons.more_vert),
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 10.0,
          child: Container(
            color: Colors.black,
            alignment: Alignment.center,
            child: Image.network(
              imageUrl,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) {
                  return child;
                }
                return const Center(
                  child: PulsatingLoadingIndicator(
                    size: 108.0,
                    assetPath: 'assets/icons/fathemed.png',
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return Image.asset('assets/images/defaultpic.gif');
              },
            ),

          ),
        ),
      ),
    );
  }
}
