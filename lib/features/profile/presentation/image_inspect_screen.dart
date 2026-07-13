import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:FANotifier/shared/widgets/fa_network_image.dart';
import 'package:provider/provider.dart';

import 'package:FANotifier/features/profile/domain/avatar_image_data.dart';
import 'package:FANotifier/features/profile/domain/profile_media_export_repository.dart';
import 'package:FANotifier/shared/widgets/PulsatingLoadingIndicator.dart';

class ImageInspectScreen extends StatefulWidget {
  final String imageUrl;
  final AvatarImageData? imageData;

  const ImageInspectScreen({
    Key? key,
    required this.imageUrl,
    this.imageData,
  }) : super(key: key);

  static Route<void> route({
    required String imageUrl,
    AvatarImageData? imageData,
  }) {
    return PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.transparent,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, animation, secondaryAnimation) {
        return FadeTransition(
          opacity: animation,
          child: ImageInspectScreen(
            imageUrl: imageUrl,
            imageData: imageData,
          ),
        );
      },
    );
  }

  @override
  State<ImageInspectScreen> createState() => _ImageInspectScreenState();
}

class _ImageInspectScreenState extends State<ImageInspectScreen>
    with SingleTickerProviderStateMixin {
  final TransformationController _transformationController =
      TransformationController();
  late final ProfileMediaExportRepository _mediaExportRepository;
  late final AnimationController _doubleTapZoomAnimationController;
  Matrix4 _zoomAnimationStart = Matrix4.identity();
  Matrix4 _zoomAnimationEnd = Matrix4.identity();
  Offset? _tapDownPosition;
  Offset? _doubleTapCandidateDownPosition;
  Matrix4? _doubleTapCandidateStartTransform;
  Offset? _lastTapUpPosition;
  DateTime? _lastTapUpTime;
  Timer? _tapToggleTimer;
  Offset _dragOffset = Offset.zero;
  int _activePointerCount = 0;
  double _verticalSwipeDistance = 0;
  bool _canDismissWithSwipe = false;
  bool _hasMultiTouchInteraction = false;
  bool _hadMultiplePointers = false;
  bool _suppressDismissUntilPointersReleased = false;
  bool _isDraggingToDismiss = false;
  bool _isDismissing = false;
  bool _isDoubleTapCandidate = false;
  bool _chromeVisible = true;

  static const double _dismissDistance = 250;
  static const double _dismissVelocity = 900;
  static const double _fadeDistance = 360;
  static const double _tapSlop = 12;
  static const double _doubleTapSlop = 36;
  static const double _doubleTapScale = 4.0;
  static const Duration _doubleTapTimeout = Duration(milliseconds: 300);
  static const Duration _doubleTapZoomDuration = Duration(milliseconds: 240);
  static const Duration _settleDuration = Duration(milliseconds: 180);
  static const Duration _dismissAnimationDuration = Duration(milliseconds: 450);

  @override
  void initState() {
    super.initState();
    _mediaExportRepository = context.read<ProfileMediaExportRepository>();
    _doubleTapZoomAnimationController = AnimationController(
      vsync: this,
      duration: _doubleTapZoomDuration,
    )..addListener(_updateDoubleTapZoomAnimation);
  }

  @override
  void dispose() {
    _tapToggleTimer?.cancel();
    _doubleTapZoomAnimationController.dispose();
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
      final isPermissionGranted =
          await _mediaExportRepository.requestImageExportPermission();

      if (!isPermissionGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo permission denied'), backgroundColor: Colors.red),
        );
        return;
      }

      final imageData = widget.imageData ??
          await _mediaExportRepository.fetchImageData(widget.imageUrl);
      final isSaved =
          await _mediaExportRepository.saveImageToGallery(imageData);

      if (isSaved) {
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
      final isPermissionGranted =
          await _mediaExportRepository.requestImageExportPermission();

      if (!isPermissionGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permission denied'), backgroundColor: Colors.red),
        );
        return;
      }

      final imageData = widget.imageData ??
          await _mediaExportRepository.fetchImageData(widget.imageUrl);
      await _mediaExportRepository.shareImage(imageData);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to share image: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _clearPendingTapToggle() {
    _tapToggleTimer?.cancel();
    _tapToggleTimer = null;
    _lastTapUpPosition = null;
    _lastTapUpTime = null;
  }

  void _setDoubleTapCandidate(Offset? position) {
    final isCandidate = position != null;
    if (_isDoubleTapCandidate == isCandidate &&
        _doubleTapCandidateDownPosition == position) {
      return;
    }
    setState(() {
      _isDoubleTapCandidate = isCandidate;
      _doubleTapCandidateDownPosition = position;
      _doubleTapCandidateStartTransform =
          isCandidate ? _transformationController.value.clone() : null;
    });
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_isDismissing) {
      _tapDownPosition = null;
      _setDoubleTapCandidate(null);
      return;
    }
    _doubleTapZoomAnimationController.stop();
    final now = DateTime.now();
    final lastTapUpPosition = _lastTapUpPosition;
    final lastTapUpTime = _lastTapUpTime;
    final isDoubleTapCandidate =
        _activePointerCount == 0 &&
        lastTapUpPosition != null &&
        lastTapUpTime != null &&
        now.difference(lastTapUpTime) <= _doubleTapTimeout &&
        (event.position - lastTapUpPosition).distance <= _doubleTapSlop;
    if (isDoubleTapCandidate) {
      _setDoubleTapCandidate(event.position);
    } else {
      _setDoubleTapCandidate(null);
    }
    _activePointerCount += 1;
    if (_activePointerCount > 1) {
      _hadMultiplePointers = true;
      _suppressDismissUntilPointersReleased = true;
      _verticalSwipeDistance = 0;
      _canDismissWithSwipe = false;
      _setDoubleTapCandidate(null);
      if (_isDraggingToDismiss) {
        setState(() {
          _dragOffset = Offset.zero;
          _isDraggingToDismiss = false;
        });
      }
      _clearPendingTapToggle();
    }
    _tapDownPosition = event.position;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_isDoubleTapCandidate) {
      return;
    }
    final candidateDownPosition = _doubleTapCandidateDownPosition;
    if (candidateDownPosition == null) {
      _setDoubleTapCandidate(null);
      return;
    }
    if ((event.position - candidateDownPosition).distance > _tapSlop) {
      _setDoubleTapCandidate(null);
      return;
    }
    final startTransform = _doubleTapCandidateStartTransform;
    if (startTransform != null) {
      _transformationController.value = startTransform.clone();
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (_isDismissing) {
      _tapDownPosition = null;
      _setDoubleTapCandidate(null);
      return;
    }
    final hadMultiplePointers =
        _hadMultiplePointers || _activePointerCount > 1;
    if (_activePointerCount > 0) {
      _activePointerCount -= 1;
    }
    if (_activePointerCount == 0) {
      _hadMultiplePointers = false;
      _suppressDismissUntilPointersReleased = false;
    }

    final tapDownPosition = _tapDownPosition;
    _tapDownPosition = null;
    if (hadMultiplePointers) {
      _setDoubleTapCandidate(null);
      return;
    }
    if (tapDownPosition == null) {
      _setDoubleTapCandidate(null);
      return;
    }
    if ((event.position - tapDownPosition).distance > _tapSlop) {
      _setDoubleTapCandidate(null);
      return;
    }

    final now = DateTime.now();
    final lastTapUpPosition = _lastTapUpPosition;
    final lastTapUpTime = _lastTapUpTime;
    final doubleTapPosition = _doubleTapCandidateDownPosition ?? event.position;
    final isDoubleTap = lastTapUpPosition != null &&
        lastTapUpTime != null &&
        now.difference(lastTapUpTime) <= _doubleTapTimeout &&
        (doubleTapPosition - lastTapUpPosition).distance <= _doubleTapSlop;

    if (isDoubleTap) {
      final startTransform = _doubleTapCandidateStartTransform;
      if (startTransform != null) {
        _transformationController.value = startTransform.clone();
      }
      _setDoubleTapCandidate(null);
      _clearPendingTapToggle();
      _toggleZoomAt(doubleTapPosition);
      return;
    }

    _setDoubleTapCandidate(null);
    _tapToggleTimer?.cancel();
    _lastTapUpPosition = event.position;
    _lastTapUpTime = now;
    _tapToggleTimer = Timer(_doubleTapTimeout, () {
      if (!mounted) {
        return;
      }
      _tapToggleTimer = null;
      _lastTapUpPosition = null;
      _lastTapUpTime = null;
      _toggleChrome();
    });
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _tapDownPosition = null;
    _setDoubleTapCandidate(null);
    if (_activePointerCount > 0) {
      _activePointerCount -= 1;
    }
    if (_activePointerCount == 0) {
      _hadMultiplePointers = false;
      _suppressDismissUntilPointersReleased = false;
    }
  }

  void _toggleZoomAt(Offset globalPosition) {
    if (_isDismissing) {
      return;
    }

    final currentScale =
        _transformationController.value.getMaxScaleOnAxis();
    if (currentScale > 1.05) {
      _animateDoubleTapZoomTo(Matrix4.identity());
      return;
    }

    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox) {
      return;
    }

    final localPosition = renderObject.globalToLocal(globalPosition);
    final zoom = Matrix4.identity()
      ..translate(
        -localPosition.dx * (_doubleTapScale - 1),
        -localPosition.dy * (_doubleTapScale - 1),
      )
      ..scale(_doubleTapScale);
    _animateDoubleTapZoomTo(zoom);
  }

  void _animateDoubleTapZoomTo(Matrix4 target) {
    _doubleTapZoomAnimationController.stop();
    _zoomAnimationStart = _transformationController.value.clone();
    _zoomAnimationEnd = target;
    _doubleTapZoomAnimationController.forward(from: 0.0);
  }

  void _updateDoubleTapZoomAnimation() {
    final progress = Curves.easeInOutCubic.transform(
      _doubleTapZoomAnimationController.value,
    );
    final values = List<double>.generate(
      16,
      (index) =>
          _zoomAnimationStart.storage[index] +
          (_zoomAnimationEnd.storage[index] -
                  _zoomAnimationStart.storage[index]) *
              progress,
    );
    _transformationController.value = Matrix4.fromList(values);
  }

  Future<void> _dismissWithSwipe() async {
    if (_isDismissing) {
      return;
    }

    final direction = _dragOffset.dy < 0 ? -1.0 : 1.0;
    final screenHeight = MediaQuery.of(context).size.height;
    setState(() {
      _dragOffset = Offset(0, direction * (screenHeight + 200));
      _isDraggingToDismiss = false;
      _isDismissing = true;
    });

    await Future<void>.delayed(_dismissAnimationDuration);

    if (mounted) {
      await Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dragProgress =
        (_dragOffset.dy.abs() / _fadeDistance).clamp(0.0, 1.0).toDouble();
    final backgroundOpacity = 1.0 - dragProgress;

    final content = Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: AnimatedOpacity(
          opacity: _chromeVisible && !_isDismissing ? 1.0 : 0.0,
          duration:
              _isDismissing ? Duration.zero : const Duration(milliseconds: 160),
          child: IgnorePointer(
            ignoring: !_chromeVisible || _isDismissing,
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
        onPointerDown: _handlePointerDown,
        onPointerMove: _handlePointerMove,
        onPointerUp: _handlePointerUp,
        onPointerCancel: _handlePointerCancel,
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
              panEnabled: !_isDoubleTapCandidate,
              scaleEnabled: !_isDoubleTapCandidate,
              onInteractionStart: (details) {
                if (_isDismissing) {
                  return;
                }
                if (_isDoubleTapCandidate) {
                  _verticalSwipeDistance = 0;
                  _canDismissWithSwipe = false;
                  return;
                }
                _verticalSwipeDistance = 0;
                _hasMultiTouchInteraction = details.pointerCount != 1;
                _canDismissWithSwipe =
                    !_hasMultiTouchInteraction &&
                    !_suppressDismissUntilPointersReleased &&
                    _transformationController.value.getMaxScaleOnAxis() <=
                        1.05;
              },
              onInteractionUpdate: (details) {
                if (_isDismissing) {
                  return;
                }
                if (_isDoubleTapCandidate) {
                  final startTransform = _doubleTapCandidateStartTransform;
                  if (startTransform != null) {
                    _transformationController.value = startTransform.clone();
                  }
                  return;
                }
                if (details.pointerCount != 1) {
                  _hasMultiTouchInteraction = true;
                  _canDismissWithSwipe = false;
                  return;
                }
                if (!_canDismissWithSwipe) {
                  return;
                }
                setState(() {
                  _verticalSwipeDistance += details.focalPointDelta.dy;
                  _dragOffset = Offset(0, _verticalSwipeDistance);
                  _isDraggingToDismiss = true;
                });
              },
              onInteractionEnd: (details) {
                if (_isDismissing) {
                  return;
                }
                if (_isDoubleTapCandidate) {
                  return;
                }
                final verticalVelocity =
                    details.velocity.pixelsPerSecond.dy.abs();
                final shouldDismiss =
                    _canDismissWithSwipe &&
                    !_hasMultiTouchInteraction &&
                    !_suppressDismissUntilPointersReleased &&
                    _isDraggingToDismiss &&
                    (_verticalSwipeDistance.abs() >= _dismissDistance ||
                        verticalVelocity >= _dismissVelocity);
                _verticalSwipeDistance = 0;
                _canDismissWithSwipe = false;
                _hasMultiTouchInteraction = false;

                if (shouldDismiss) {
                  unawaited(_dismissWithSwipe());
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
                    : _isDismissing
                        ? _dismissAnimationDuration
                        : _settleDuration,
                curve: _isDismissing
                    ? Curves.easeInOutCubic
                    : Curves.easeOutCubic,
                transform: Matrix4.translationValues(
                  _dragOffset.dx,
                  _dragOffset.dy,
                  0,
                ),
                child: SizedBox.expand(
                  child: Container(
                    alignment: Alignment.center,
                    child: widget.imageData != null
                        ? Image.memory(
                            widget.imageData!.bytes,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                            gaplessPlayback: true,
                          )
                        : FaNetworkImage(
                            widget.imageUrl,
                            fit: BoxFit.contain,
                            loadingBuilder:
                                (context, child, loadingProgress) {
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
                              return Image.asset(
                                'assets/images/defaultpic.gif',
                              );
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

    if (!Platform.isAndroid) {
      return content;
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarContrastEnforced: false,
        systemStatusBarContrastEnforced: false,
      ),
      child: content,
    );
  }
}
