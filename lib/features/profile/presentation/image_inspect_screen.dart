import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:FANotifier/shared/widgets/fa_network_image.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:share_plus/share_plus.dart';

import 'package:FANotifier/features/profile/data/avatar_image_service.dart';
import 'package:FANotifier/shared/widgets/PulsatingLoadingIndicator.dart';

class ImageInspectScreen extends StatefulWidget {
  final String imageUrl;

  const ImageInspectScreen({Key? key, required this.imageUrl}) : super(key: key);

  static Route<void> route({required String imageUrl}) {
    return PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.transparent,
      pageBuilder: (context, animation, secondaryAnimation) {
        return FadeTransition(
          opacity: animation,
          child: ImageInspectScreen(imageUrl: imageUrl),
        );
      },
    );
  }

  @override
  State<ImageInspectScreen> createState() => _ImageInspectScreenState();
}

class _ImageInspectScreenState extends State<ImageInspectScreen> {
  final TransformationController _transformationController =
      TransformationController();
  Offset? _tapDownPosition;
  Offset _dragOffset = Offset.zero;
  double _verticalSwipeDistance = 0;
  bool _canDismissWithSwipe = false;
  bool _isDraggingToDismiss = false;
  bool _chromeVisible = true;

  static const double _dismissDistance = 250;
  static const double _dismissVelocity = 900;
  static const double _fadeDistance = 360;
  static const double _tapSlop = 12;

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    _transformationController.dispose();
    super.dispose();
  }

  void _toggleChrome() {
    setState(() {
      _chromeVisible = !_chromeVisible;
    });

    if (_chromeVisible) {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

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

      final imageData = await fetchAvatarImageData(widget.imageUrl);
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

      final imageData = await fetchAvatarImageData(widget.imageUrl);
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
    final dragProgress =
        (_dragOffset.dy.abs() / _fadeDistance).clamp(0.0, 1.0).toDouble();
    final backgroundOpacity = 1.0 - dragProgress;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: AnimatedOpacity(
          opacity: _chromeVisible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 160),
          child: IgnorePointer(
            ignoring: !_chromeVisible,
            child: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
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
          ),
        ),
      ),
      body: Listener(
        onPointerDown: (event) {
          _tapDownPosition = event.position;
        },
        onPointerUp: (event) {
          final tapDownPosition = _tapDownPosition;
          _tapDownPosition = null;
          if (tapDownPosition == null) {
            return;
          }
          if ((event.position - tapDownPosition).distance <= _tapSlop) {
            _toggleChrome();
          }
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: Colors.black.withOpacity(backgroundOpacity),
                ),
              ),
            ),
            InteractiveViewer(
              transformationController: _transformationController,
              minScale: 0.5,
              maxScale: 10.0,
              onInteractionStart: (_) {
                _verticalSwipeDistance = 0;
                _canDismissWithSwipe =
                    _transformationController.value.getMaxScaleOnAxis() <=
                        1.05;
              },
              onInteractionUpdate: (details) {
                if (!_canDismissWithSwipe || details.pointerCount != 1) {
                  return;
                }
                setState(() {
                  _verticalSwipeDistance += details.focalPointDelta.dy;
                  _dragOffset = Offset(0, _verticalSwipeDistance);
                  _isDraggingToDismiss = true;
                });
              },
              onInteractionEnd: (details) {
                final verticalVelocity =
                    details.velocity.pixelsPerSecond.dy.abs();
                final shouldDismiss =
                    _canDismissWithSwipe &&
                    (_verticalSwipeDistance.abs() >= _dismissDistance ||
                        verticalVelocity >= _dismissVelocity);
                _verticalSwipeDistance = 0;
                _canDismissWithSwipe = false;

                if (shouldDismiss) {
                  Navigator.of(context).maybePop();
                  return;
                }

                setState(() {
                  _dragOffset = Offset.zero;
                  _isDraggingToDismiss = false;
                });
              },
              child: AnimatedContainer(
                duration: _isDraggingToDismiss
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                transform: Matrix4.translationValues(
                  _dragOffset.dx,
                  _dragOffset.dy,
                  0,
                ),
                child: SizedBox.expand(
                  child: Container(
                    alignment: Alignment.center,
                    child: FaNetworkImage(
                      widget.imageUrl,
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
            ),
          ],
        ),
      ),
    );
  }
}
