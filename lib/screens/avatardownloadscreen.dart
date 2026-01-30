import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';

import '../widgets/PulsatingLoadingIndicator.dart';
import '../services/fa_http.dart';

class AvatarDownloadScreen extends StatelessWidget {
  final String imageUrl;

  const AvatarDownloadScreen({Key? key, required this.imageUrl}) : super(key: key);


  String _extFromUrlOrContentType(String url, String? contentType) {
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

  bool _isJpegExt(String ext) => ext == '.jpg' || ext == '.jpeg';


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

      final response = await http.get(
        Uri.parse(imageUrl),
        headers: {'User-Agent': FAHttp.userAgent},
      );
      final bytes = response.statusCode == 200 ? response.bodyBytes : await _loadDefaultImageBytes();
      final ext = _extFromUrlOrContentType(imageUrl, response.headers['content-type']);
      final filename = "avatar_${DateTime.now().millisecondsSinceEpoch}$ext";


      final result = await SaverGallery.saveImage(
        bytes,
        quality: _isJpegExt(ext) ? 100 : 100,
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

      final response = await http.get(
        Uri.parse(imageUrl),
        headers: {'User-Agent': FAHttp.userAgent},
      );
      final bytes = response.statusCode == 200 ? response.bodyBytes : await _loadDefaultImageBytes();
      final ext = _extFromUrlOrContentType(imageUrl, response.headers['content-type']);
      final filename = 'shared_image_${DateTime.now().millisecondsSinceEpoch}$ext';

      final tempDir = Directory.systemTemp;
      final tempFile = await File('${tempDir.path}/$filename').create(recursive: true);
      await tempFile.writeAsBytes(bytes);

      await Share.shareXFiles([XFile(tempFile.path)], text: '');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to share image: $e'), backgroundColor: Colors.red),
      );
    }
  }
  Future<Uint8List> _loadDefaultImageBytes() async {
    final byteData = await rootBundle.load('assets/images/defaultpic.gif');
    return byteData.buffer.asUint8List();
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
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.contain,
              placeholder: (context, url) => const Center(
                child: PulsatingLoadingIndicator(
                  size: 108.0,
                  assetPath: 'assets/icons/fathemed.png',
                ),
              ),
              errorWidget: (context, url, error) =>
                  Image.asset('assets/images/defaultpic.gif'),
            ),
          ),
        ),
      ),
    );
  }
}
