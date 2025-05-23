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

class AvatarDownloadScreen extends StatelessWidget {
  final String imageUrl;

  const AvatarDownloadScreen({Key? key, required this.imageUrl}) : super(key: key);



  Future<void> _downloadImage(BuildContext context) async {
    try {
      bool isPermissionGranted = false;

      if (Platform.isAndroid) {
        isPermissionGranted = await _requestPermissionAndroid();
      } else if (Platform.isIOS) {
        if (await Permission.photosAddOnly.request().isGranted) {
          isPermissionGranted = true;
        }
      }

      if (isPermissionGranted) {
        Uint8List bytes;


        final response = await http.get(Uri.parse(imageUrl));
        if (response.statusCode == 200) {
          bytes = response.bodyBytes;
        } else {

          bytes = await _loadDefaultImageBytes();
        }


        final result = await SaverGallery.saveImage(
          bytes,
          quality: 80,
          fileName: "avatar_${DateTime.now().millisecondsSinceEpoch}.jpg",
          skipIfExists: false,
          androidRelativePath: "Pictures/YourAppName/images",
        );

        if (result.isSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Image saved to gallery!'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to save image to gallery.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Photo permission denied'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to download image: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _shareImage(BuildContext context) async {
    try {
      bool isPermissionGranted = false;

      if (Platform.isAndroid) {
        isPermissionGranted = await _requestPermissionAndroid();
      } else if (Platform.isIOS) {
        if (await Permission.photosAddOnly.request().isGranted) {
          isPermissionGranted = true;
        }
      }

      if (!isPermissionGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Permission denied'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      Uint8List bytes;


      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode == 200) {
        bytes = response.bodyBytes;
      } else {
        bytes = await _loadDefaultImageBytes();
      }


      final tempDir = Directory.systemTemp;
      final tempFile = await File('${tempDir.path}/shared_image_${DateTime.now().millisecondsSinceEpoch}.jpg').create();
      await tempFile.writeAsBytes(bytes);


      await Share.shareXFiles([XFile(tempFile.path)], text: '');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to share image: $e'),
          backgroundColor: Colors.red,
        ),
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
      // Android 13+ (API level 33+)
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

            offset: Offset(0, 40),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'download',
                child: Text('Download'),
              ),
              PopupMenuItem(
                value: 'share',
                child: Text('Share image'),
              ),
            ],
            icon: Icon(Icons.more_vert),
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
              placeholder: (context, url) => Center(child: PulsatingLoadingIndicator(size: 108.0, assetPath: 'assets/icons/fathemed.png')),
              errorWidget: (context, url, error) => Image.asset('assets/images/defaultpic.gif'),
            ),
          ),
        ),
      ),
    );
  }
}
