import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:fanotifier/shared/widgets/fa_network_image.dart';
import 'package:provider/provider.dart';

import 'package:fanotifier/features/profile/domain/avatar_image_data.dart';
import 'package:fanotifier/features/profile/domain/profile_media_export_repository.dart';
import 'package:fanotifier/shared/widgets/pulsating_loading_indicator.dart';
import 'package:fanotifier/core/analytics/app_screen.dart';

class ImageInspectItem {
  const ImageInspectItem({
    required this.label,
    required this.imageUrl,
    this.imageData,
  });

  final String label;
  final String imageUrl;
  final AvatarImageData? imageData;
}

class ImageInspectScreen extends StatefulWidget {
  final String imageUrl;
  final AvatarImageData? imageData;
  final List<ImageInspectItem>? items;
  final int initialIndex;

  const ImageInspectScreen({
    super.key,
    required this.imageUrl,
    this.imageData,
    this.items,
    this.initialIndex = 0,
  });

  static Route<void> route({
    required String imageUrl,
    AvatarImageData? imageData,
  }) {
    return PageRouteBuilder<void>(
      settings: const AnalyticsRouteSettings(AppScreens.imageViewer),
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

  static Route<void> comparisonRoute({
    required AvatarImageData original,
    required AvatarImageData changed,
    int initialIndex = 0,
  }) {
    return PageRouteBuilder<void>(
      settings: const AnalyticsRouteSettings(AppScreens.imageViewer),
      opaque: false,
      barrierColor: Colors.transparent,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, animation, secondaryAnimation) {
        return FadeTransition(
          opacity: animation,
          child: ImageInspectScreen(
            imageUrl: '',
            initialIndex: initialIndex,
            items: [
              ImageInspectItem(
                label: 'Original',
                imageUrl: '',
                imageData: original,
              ),
              ImageInspectItem(
                label: 'Changed',
                imageUrl: '',
                imageData: changed,
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  State<ImageInspectScreen> createState() => _ImageInspectScreenState();
}

class _ImageInspectScreenState extends State<ImageInspectScreen>
    with TickerProviderStateMixin {
  final TransformationController _transformationController =
      TransformationController();
  late final ProfileMediaExportRepository _mediaExportRepository;
  late final AnimationController _doubleTapZoomAnimationController;
  late final AnimationController _pageSlideAnimationController;
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
  late final List<ImageInspectItem> _items;
  late int _currentIndex;
  final ValueNotifier<double> _pageOffsetListenable = ValueNotifier(0);
  double _pageViewportWidth = 0;
  double _pageAnimationStart = 0;
  double _pageAnimationEnd = 0;
  double _pageDragStartOffset = 0;
  int? _pageAnimationTargetIndex;
  Axis? _lockedDragAxis;

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
    _items = widget.items ??
        [
          ImageInspectItem(
            label: 'Image',
            imageUrl: widget.imageUrl,
            imageData: widget.imageData,
          ),
        ];
    _currentIndex = widget.initialIndex.clamp(0, _items.length - 1).toInt();
    _mediaExportRepository = context.read<ProfileMediaExportRepository>();
    _doubleTapZoomAnimationController = AnimationController(
      vsync: this,
      duration: _doubleTapZoomDuration,
    )..addListener(_updateDoubleTapZoomAnimation);
    _pageSlideAnimationController = AnimationController(
      vsync: this,
      duration: _settleDuration,
    )
      ..addListener(_updatePageSlideAnimation)
      ..addStatusListener(_handlePageSlideAnimationStatus);
  }

  ImageInspectItem get _currentItem => _items[_currentIndex];
  bool get _comparisonEnabled => _items.length > 1;

  @override
  void dispose() {
    _tapToggleTimer?.cancel();
    _doubleTapZoomAnimationController.dispose();
    _pageSlideAnimationController.dispose();
    _pageOffsetListenable.dispose();
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

      if (!context.mounted) return;
      if (!isPermissionGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo permission denied'), backgroundColor: Colors.red),
        );
        return;
      }

      final item = _currentItem;
      final imageData = item.imageData ??
          await _mediaExportRepository.fetchImageData(item.imageUrl);
      if (!context.mounted) return;
      final isSaved =
          await _mediaExportRepository.saveImageToGallery(imageData);

      if (!context.mounted) return;
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
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to download image: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _shareImage(BuildContext context) async {
    try {
      final isPermissionGranted =
          await _mediaExportRepository.requestImageExportPermission();

      if (!context.mounted) return;
      if (!isPermissionGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permission denied'), backgroundColor: Colors.red),
        );
        return;
      }

      final item = _currentItem;
      final imageData = item.imageData ??
          await _mediaExportRepository.fetchImageData(item.imageUrl);
      if (!context.mounted) return;
      await _mediaExportRepository.shareImage(imageData);
    } catch (e) {
      if (!context.mounted) return;
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
    if (_activePointerCount == 0) {
      _pageSlideAnimationController.stop();
      _pageAnimationTargetIndex = null;
      _pageDragStartOffset = _pageOffsetListenable.value;
      _lockedDragAxis = null;
    }
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
      _lockedDragAxis = null;
      _pageAnimationTargetIndex = null;
      _pageOffsetListenable.value = 0;
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
    if (_activePointerCount == 1) _tapDownPosition = event.position;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    final swipeStart = _tapDownPosition;
    if (_comparisonEnabled &&
        swipeStart != null &&
        _activePointerCount == 1 &&
        !_suppressDismissUntilPointersReleased &&
        _transformationController.value.getMaxScaleOnAxis() <= 1.05) {
      final drag = event.position - swipeStart;
      if (_lockedDragAxis == null &&
          math.max(drag.dx.abs(), drag.dy.abs()) >= _tapSlop) {
        if (drag.dx.abs() >= drag.dy.abs() * 0.9) {
          _lockedDragAxis = Axis.horizontal;
        } else if (drag.dy.abs() >= _tapSlop * 1.5 &&
            drag.dy.abs() > drag.dx.abs() * 1.4) {
          _lockedDragAxis = Axis.vertical;
        }
      }
      if (_lockedDragAxis == Axis.horizontal) {
        _canDismissWithSwipe = false;
        _verticalSwipeDistance = 0;
        _transformationController.value = Matrix4.identity();
        final atFirst = _currentIndex == 0 && drag.dx > 0;
        final atLast =
            _currentIndex == _items.length - 1 && drag.dx < 0;
        final resistance = atFirst || atLast ? 0.24 : 1.0;
        _pageOffsetListenable.value =
            _pageDragStartOffset + drag.dx * resistance;
      } else if (_lockedDragAxis == Axis.vertical) {
        _canDismissWithSwipe = true;
        if (_pageOffsetListenable.value != 0) {
          _pageOffsetListenable.value = 0;
        }
      }
    }
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
    final dragAxis = _lockedDragAxis;
    final pageOffset = _pageOffsetListenable.value;

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
    _lockedDragAxis = null;
    if (hadMultiplePointers) {
      _animatePageOffset(0);
      _setDoubleTapCandidate(null);
      return;
    }
    if (dragAxis == Axis.horizontal) {
      _transformationController.value = Matrix4.identity();
      _setDoubleTapCandidate(null);
      _clearPendingTapToggle();
      _settlePageDrag(pageOffset);
      return;
    }
    if (pageOffset != 0) {
      _animatePageOffset(0);
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
    _lockedDragAxis = null;
    _animatePageOffset(0);
    _setDoubleTapCandidate(null);
    if (_activePointerCount > 0) {
      _activePointerCount -= 1;
    }
    if (_activePointerCount == 0) {
      _hadMultiplePointers = false;
      _suppressDismissUntilPointersReleased = false;
    }
  }

  void _showItem(int index) {
    if (index < 0 || index >= _items.length || index == _currentIndex) return;
    _doubleTapZoomAnimationController.stop();
    _transformationController.value = Matrix4.identity();
    final width = _pageViewportWidth > 0
        ? _pageViewportWidth
        : MediaQuery.of(context).size.width;
    _animatePageOffset(
      index > _currentIndex ? -width : width,
      targetIndex: index,
    );
  }

  void _settlePageDrag(double offset) {
    final width = _pageViewportWidth > 0
        ? _pageViewportWidth
        : MediaQuery.of(context).size.width;
    final threshold = math.min(72.0, width * 0.18);
    if (offset <= -threshold && _currentIndex < _items.length - 1) {
      _animatePageOffset(-width, targetIndex: _currentIndex + 1);
      return;
    }
    if (offset >= threshold && _currentIndex > 0) {
      _animatePageOffset(width, targetIndex: _currentIndex - 1);
      return;
    }
    _animatePageOffset(0);
  }

  void _animatePageOffset(double target, {int? targetIndex}) {
    _pageSlideAnimationController.stop();
    _pageAnimationStart = _pageOffsetListenable.value;
    _pageAnimationEnd = target;
    _pageAnimationTargetIndex = targetIndex;
    if ((_pageAnimationStart - target).abs() < 0.5) {
      _handlePageSlideAnimationStatus(AnimationStatus.completed);
      return;
    }
    _pageSlideAnimationController.forward(from: 0);
  }

  void _updatePageSlideAnimation() {
    final progress = Curves.easeOutCubic.transform(
      _pageSlideAnimationController.value,
    );
    _pageOffsetListenable.value = _pageAnimationStart +
        (_pageAnimationEnd - _pageAnimationStart) * progress;
  }

  void _handlePageSlideAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    final targetIndex = _pageAnimationTargetIndex;
    _pageAnimationTargetIndex = null;
    if (targetIndex == null) {
      _pageOffsetListenable.value = 0;
      return;
    }
    _transformationController.value = Matrix4.identity();
    setState(() {
      _currentIndex = targetIndex;
      _dragOffset = Offset.zero;
      _verticalSwipeDistance = 0;
      _isDraggingToDismiss = false;
      _pageOffsetListenable.value = 0;
    });
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
      ..translateByDouble(
        -localPosition.dx * (_doubleTapScale - 1),
        -localPosition.dy * (_doubleTapScale - 1),
        0.0,
        1.0,
      )
      ..scaleByDouble(_doubleTapScale, _doubleTapScale, _doubleTapScale, 1.0);
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

  Widget _buildInspectableImage(ImageInspectItem item) {
    return Container(
      alignment: Alignment.center,
      child: item.imageData != null
          ? Image.memory(
              item.imageData!.bytes,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              gaplessPlayback: true,
            )
          : FaNetworkImage(
              item.imageUrl,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
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
    );
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
              centerTitle: true,
              titleSpacing: 0,
              title: _comparisonEnabled
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var index = 0; index < _items.length; index++) ...[
                          if (index > 0) const SizedBox(width: 8),
                          _InspectorChoiceButton(
                            label: _items[index].label,
                            selected: index == _currentIndex,
                            onTap: () => _showItem(index),
                          ),
                        ],
                      ],
                    )
                  : null,
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
                  color: Colors.black.withValues(alpha: backgroundOpacity),
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
                    (!_comparisonEnabled ||
                        _lockedDragAxis == Axis.vertical) &&
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
                if (_comparisonEnabled &&
                    _lockedDragAxis != Axis.vertical) {
                  if (_transformationController.value.getMaxScaleOnAxis() <=
                      1.05) {
                    _transformationController.value = Matrix4.identity();
                  }
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
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      _pageViewportWidth = constraints.maxWidth;
                      final currentImage = RepaintBoundary(
                        child: _buildInspectableImage(_currentItem),
                      );
                      final previousImage = _currentIndex > 0
                          ? RepaintBoundary(
                              child: _buildInspectableImage(
                                _items[_currentIndex - 1],
                              ),
                            )
                          : null;
                      final nextImage = _currentIndex < _items.length - 1
                          ? RepaintBoundary(
                              child: _buildInspectableImage(
                                _items[_currentIndex + 1],
                              ),
                            )
                          : null;
                      return ClipRect(
                        child: ValueListenableBuilder<double>(
                          valueListenable: _pageOffsetListenable,
                          builder: (context, pageOffset, child) {
                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                if (previousImage != null)
                                  Transform.translate(
                                    offset: Offset(
                                      pageOffset - constraints.maxWidth,
                                      0,
                                    ),
                                    child: previousImage,
                                  ),
                                Transform.translate(
                                  offset: Offset(pageOffset, 0),
                                  child: currentImage,
                                ),
                                if (nextImage != null)
                                  Transform.translate(
                                    offset: Offset(
                                      pageOffset + constraints.maxWidth,
                                      0,
                                    ),
                                    child: nextImage,
                                  ),
                              ],
                            );
                          },
                        ),
                      );
                    },
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

class _InspectorChoiceButton extends StatelessWidget {
  const _InspectorChoiceButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFE09321);
    return Material(
      color: selected ? orange : orange.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 36),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.black : Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
