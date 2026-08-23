import 'dart:math' as math;
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import 'package:fanotifier/features/image_tools/domain/image_optimizer_models.dart';

class FreeformImageCropEditor extends StatefulWidget {
  const FreeformImageCropEditor({
    super.key,
    required this.bytes,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.value,
    required this.onChanged,
    required this.onInteractionChanged,
  });

  final Uint8List bytes;
  final int sourceWidth;
  final int sourceHeight;
  final ImageCropRegion value;
  final ValueChanged<ImageCropRegion> onChanged;
  final ValueChanged<bool> onInteractionChanged;

  @override
  State<FreeformImageCropEditor> createState() =>
      _FreeformImageCropEditorState();
}

enum _CropDragTarget {
  move,
  top,
  right,
  bottom,
  left,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

class _FreeformImageCropEditorState extends State<FreeformImageCropEditor> {
  static const _minimumCropSize = 0.06;
  static const _handleHitRadius = 8.0;
  static const _edgeHitSize = 30.0;
  static const _horizontalImagePadding = 16.0;
  static const _verticalImagePadding = 8.0;
  static const _dragIconReservedHeight = 16.0;

  late Rect _selection;
  Rect _baseImageRect = Rect.zero;
  Rect _dragIconHitRect = Rect.zero;
  Rect _startSelection = Rect.zero;
  Offset _startPosition = Offset.zero;
  _CropDragTarget? _dragTarget;
  double _viewScale = 1;
  Offset _viewOffset = Offset.zero;
  bool _viewGesture = false;
  bool _selectionChanged = false;
  double _viewGestureStartScale = 1;
  double _gestureScaleAtViewStart = 1;
  Offset _viewAnchor = Offset.zero;
  int _activePointers = 0;
  bool _gestureActive = false;

  @override
  void initState() {
    super.initState();
    _selection = _selectionFrom(widget.value);
  }

  @override
  void didUpdateWidget(FreeformImageCropEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_dragTarget == null && oldWidget.value != widget.value) {
      _selection = _selectionFrom(widget.value);
    }
  }

  Rect _selectionFrom(ImageCropRegion value) {
    if (!value.hasFreeformBounds) return const Rect.fromLTWH(0, 0, 1, 1);
    return Rect.fromLTRB(
      value.left!.clamp(0.0, 1.0).toDouble(),
      value.top!.clamp(0.0, 1.0).toDouble(),
      value.right!.clamp(0.0, 1.0).toDouble(),
      value.bottom!.clamp(0.0, 1.0).toDouble(),
    );
  }

  Offset get _viewportCenter => _baseImageRect.center;

  Rect get _displayImageRect => Rect.fromCenter(
        center: _viewportCenter + _viewOffset,
        width: _baseImageRect.width * _viewScale,
        height: _baseImageRect.height * _viewScale,
      );

  Rect get _screenSelection {
    final imageRect = _displayImageRect;
    return Rect.fromLTRB(
      imageRect.left + _selection.left * imageRect.width,
      imageRect.top + _selection.top * imageRect.height,
      imageRect.left + _selection.right * imageRect.width,
      imageRect.top + _selection.bottom * imageRect.height,
    );
  }

  String get _cropResolution {
    final width = math.max(1, (widget.sourceWidth * _selection.width).round());
    final height = math.max(1, (widget.sourceHeight * _selection.height).round());
    return '$width×$height';
  }

  bool get _selectionCanMove =>
      _selection.width < 0.9999 || _selection.height < 0.9999;

  void _handlePointerDown(PointerDownEvent event) {
    if (_activePointers == 0) widget.onInteractionChanged(true);
    _activePointers++;
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (_activePointers > 0) _activePointers--;
    if (_activePointers == 0 && !_gestureActive) {
      widget.onInteractionChanged(false);
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _activePointers = 0;
    if (!_gestureActive) widget.onInteractionChanged(false);
  }

  void _handleScaleStart(ScaleStartDetails details) {
    if (_baseImageRect.isEmpty) return;
    _gestureActive = true;
    final crop = _screenSelection;
    final position = details.localFocalPoint;
    _dragTarget = _targetAt(position, crop);
    _startPosition = position;
    _startSelection = _selection;
    _viewGesture = false;
    _selectionChanged = false;
  }

  _CropDragTarget _targetAt(Offset position, Rect crop) {
    if (_dragIconHitRect.contains(position)) {
      return _CropDragTarget.move;
    }
    final targets = <(_CropDragTarget, Offset)>[
      (_CropDragTarget.topLeft, crop.topLeft),
      (_CropDragTarget.topRight, crop.topRight),
      (_CropDragTarget.bottomLeft, crop.bottomLeft),
      (_CropDragTarget.bottomRight, crop.bottomRight),
    ];
    for (final target in targets) {
      if ((position - target.$2).distance <= _handleHitRadius) {
        return target.$1;
      }
    }
    if ((position.dy - crop.top).abs() <= _edgeHitSize &&
        position.dx >= crop.left - _edgeHitSize &&
        position.dx <= crop.right + _edgeHitSize) {
      return _CropDragTarget.top;
    }
    if ((position.dx - crop.right).abs() <= _edgeHitSize &&
        position.dy >= crop.top - _edgeHitSize &&
        position.dy <= crop.bottom + _edgeHitSize) {
      return _CropDragTarget.right;
    }
    if ((position.dy - crop.bottom).abs() <= _edgeHitSize &&
        position.dx >= crop.left - _edgeHitSize &&
        position.dx <= crop.right + _edgeHitSize) {
      return _CropDragTarget.bottom;
    }
    if ((position.dx - crop.left).abs() <= _edgeHitSize &&
        position.dy >= crop.top - _edgeHitSize &&
        position.dy <= crop.bottom + _edgeHitSize) {
      return _CropDragTarget.left;
    }
    return _CropDragTarget.move;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount > 1) {
      _updateViewTransform(details);
      return;
    }
    if (_viewGesture) return;
    final target = _dragTarget;
    final imageRect = _displayImageRect;
    if (target == null || imageRect.isEmpty) return;
    final delta = details.localFocalPoint - _startPosition;
    final normalized = Offset(
      delta.dx / imageRect.width,
      delta.dy / imageRect.height,
    );
    setState(() {
      _selection = switch (target) {
        _CropDragTarget.move => _moveSelection(normalized),
        _CropDragTarget.top => Rect.fromLTRB(
            _startSelection.left,
            (_startSelection.top + normalized.dy)
                .clamp(0.0, _startSelection.bottom - _minimumCropSize)
                .toDouble(),
            _startSelection.right,
            _startSelection.bottom,
          ),
        _CropDragTarget.right => Rect.fromLTRB(
            _startSelection.left,
            _startSelection.top,
            (_startSelection.right + normalized.dx)
                .clamp(_startSelection.left + _minimumCropSize, 1.0)
                .toDouble(),
            _startSelection.bottom,
          ),
        _CropDragTarget.bottom => Rect.fromLTRB(
            _startSelection.left,
            _startSelection.top,
            _startSelection.right,
            (_startSelection.bottom + normalized.dy)
                .clamp(_startSelection.top + _minimumCropSize, 1.0)
                .toDouble(),
          ),
        _CropDragTarget.left => Rect.fromLTRB(
            (_startSelection.left + normalized.dx)
                .clamp(0.0, _startSelection.right - _minimumCropSize)
                .toDouble(),
            _startSelection.top,
            _startSelection.right,
            _startSelection.bottom,
          ),
        _CropDragTarget.topLeft => Rect.fromLTRB(
            (_startSelection.left + normalized.dx)
                .clamp(0.0, _startSelection.right - _minimumCropSize)
                .toDouble(),
            (_startSelection.top + normalized.dy)
                .clamp(0.0, _startSelection.bottom - _minimumCropSize)
                .toDouble(),
            _startSelection.right,
            _startSelection.bottom,
          ),
        _CropDragTarget.topRight => Rect.fromLTRB(
            _startSelection.left,
            (_startSelection.top + normalized.dy)
                .clamp(0.0, _startSelection.bottom - _minimumCropSize)
                .toDouble(),
            (_startSelection.right + normalized.dx)
                .clamp(_startSelection.left + _minimumCropSize, 1.0)
                .toDouble(),
            _startSelection.bottom,
          ),
        _CropDragTarget.bottomLeft => Rect.fromLTRB(
            (_startSelection.left + normalized.dx)
                .clamp(0.0, _startSelection.right - _minimumCropSize)
                .toDouble(),
            _startSelection.top,
            _startSelection.right,
            (_startSelection.bottom + normalized.dy)
                .clamp(_startSelection.top + _minimumCropSize, 1.0)
                .toDouble(),
          ),
        _CropDragTarget.bottomRight => Rect.fromLTRB(
            _startSelection.left,
            _startSelection.top,
            (_startSelection.right + normalized.dx)
                .clamp(_startSelection.left + _minimumCropSize, 1.0)
                .toDouble(),
            (_startSelection.bottom + normalized.dy)
                .clamp(_startSelection.top + _minimumCropSize, 1.0)
                .toDouble(),
          ),
      };
      _selectionChanged = _selection != _startSelection;
    });
  }

  void _updateViewTransform(ScaleUpdateDetails details) {
    if (!_viewGesture) {
      _viewGesture = true;
      _dragTarget = null;
      _viewGestureStartScale = _viewScale;
      _gestureScaleAtViewStart = details.scale;
      _viewAnchor =
          (details.localFocalPoint - _viewportCenter - _viewOffset) /
              _viewScale;
    }
    final gestureScale = _gestureScaleAtViewStart == 0
        ? 1.0
        : details.scale / _gestureScaleAtViewStart;
    final scale = (_viewGestureStartScale * gestureScale)
        .clamp(1.0, 5.0)
        .toDouble();
    var offset = details.localFocalPoint -
        _viewportCenter -
        _viewAnchor * scale;
    if (scale <= 1.001) {
      offset = Offset.zero;
    } else {
      final maxX = _baseImageRect.width * (scale - 1) / 2;
      final maxY = _baseImageRect.height * (scale - 1) / 2;
      offset = Offset(
        offset.dx.clamp(-maxX, maxX).toDouble(),
        offset.dy.clamp(-maxY, maxY).toDouble(),
      );
    }
    setState(() {
      _viewScale = scale;
      _viewOffset = offset;
    });
  }

  Rect _moveSelection(Offset delta) {
    final left = (_startSelection.left + delta.dx)
        .clamp(0.0, 1.0 - _startSelection.width)
        .toDouble();
    final top = (_startSelection.top + delta.dy)
        .clamp(0.0, 1.0 - _startSelection.height)
        .toDouble();
    return Rect.fromLTWH(
      left,
      top,
      _startSelection.width,
      _startSelection.height,
    );
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    if (_dragTarget == null && !_viewGesture) return;
    _dragTarget = null;
    _viewGesture = false;
    _gestureActive = false;
    if (_selectionChanged) {
      widget.onChanged(ImageCropRegion(
        left: _selection.left,
        top: _selection.top,
        right: _selection.right,
        bottom: _selection.bottom,
      ));
    }
    widget.onInteractionChanged(false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _cropResolution,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFFE09321),
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        LayoutBuilder(
          builder: (context, editorConstraints) {
            const dragIconSize = 24.0;
            const dragIconGap = 4.0;
            final dragIconVisible = _selectionCanMove;
            final fullWidth = math.max(
              1.0,
              editorConstraints.maxWidth - _horizontalImagePadding * 2,
            ).toDouble();
            final fullWidthImageHeight =
                fullWidth * widget.sourceHeight / widget.sourceWidth;
            final imageAreaHeight = math.min(
              300.0,
              fullWidthImageHeight + _verticalImagePadding * 2,
            ).toDouble();
            final editorHeight =
                imageAreaHeight + _dragIconReservedHeight;
            return SizedBox(
              height: editorHeight,
              child: LayoutBuilder(
                builder: (context, constraints) {
                    final availableWidth = math.max(
                      1.0,
                      constraints.maxWidth - _horizontalImagePadding * 2,
                    ).toDouble();
                    final availableHeight = math.max(
                      1.0,
                      imageAreaHeight - _verticalImagePadding * 2,
                    ).toDouble();
                    final scale = math.min(
                      availableWidth / widget.sourceWidth,
                      availableHeight / widget.sourceHeight,
                    );
                    final size = Size(
                      widget.sourceWidth * scale,
                      widget.sourceHeight * scale,
                    );
                    _baseImageRect = Rect.fromLTWH(
                      (constraints.maxWidth - size.width) / 2,
                      _verticalImagePadding,
                      size.width,
                      size.height,
                    );
                    final imageRect = _displayImageRect;
                    final crop = _screenSelection;
                    final dragIconLeft =
                        (crop.center.dx - dragIconSize / 2)
                            .clamp(
                              _horizontalImagePadding,
                              constraints.maxWidth -
                                  _horizontalImagePadding -
                                  dragIconSize,
                            )
                            .toDouble();
                    final dragIconTop = crop.bottom + dragIconGap;
                    _dragIconHitRect = dragIconVisible
                        ? Rect.fromLTRB(
                            dragIconLeft - 12,
                            crop.bottom + 0.5,
                            dragIconLeft + dragIconSize + 12,
                            dragIconTop + dragIconSize + 8,
                          )
                        : Rect.zero;
                    return Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: _handlePointerDown,
                      onPointerUp: _handlePointerUp,
                      onPointerCancel: _handlePointerCancel,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onScaleStart: _handleScaleStart,
                        onScaleUpdate: _handleScaleUpdate,
                        onScaleEnd: _handleScaleEnd,
                        child: Stack(
                          fit: StackFit.expand,
                          clipBehavior: Clip.none,
                          children: [
                            Positioned(
                              left: 0,
                              right: 0,
                              top: 0,
                              height: imageAreaHeight,
                              child: ClipRect(
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Positioned.fromRect(
                                      rect: _baseImageRect,
                                      child: Transform.translate(
                                        offset: _viewOffset,
                                        child: Transform.scale(
                                          scale: _viewScale,
                                          child: RepaintBoundary(
                                            child: Image.memory(
                                              widget.bytes,
                                              fit: BoxFit.fill,
                                              filterQuality:
                                                  FilterQuality.medium,
                                              gaplessPlayback: true,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    CustomPaint(
                                      painter: _FreeformCropPainter(
                                        imageRect: imageRect,
                                        cropRect: crop,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Positioned(
                              left: 0,
                              right: 0,
                              top: 0,
                              height: imageAreaHeight,
                              child: IgnorePointer(
                                child: CustomPaint(
                                  painter: _FreeformCropHandlePainter(
                                    cropRect: crop,
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              left: dragIconLeft,
                              top: dragIconTop,
                              child: IgnorePointer(
                                child: AnimatedOpacity(
                                  opacity: dragIconVisible ? 1 : 0,
                                  duration: const Duration(milliseconds: 180),
                                  curve: Curves.easeInOutCubic,
                                  child: const Icon(
                                    Icons.open_with_rounded,
                                    color: Color(0xFFE09321),
                                    size: dragIconSize,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                },
              ),
            );
          },
        ),
      ],
    );
  }
}

class _FreeformCropPainter extends CustomPainter {
  const _FreeformCropPainter({
    required this.imageRect,
    required this.cropRect,
  });

  final Rect imageRect;
  final Rect cropRect;

  @override
  void paint(Canvas canvas, Size size) {
    final dimPaint = Paint()..color = const Color(0x99000000);
    canvas.drawRect(
      Rect.fromLTRB(
        imageRect.left,
        imageRect.top,
        imageRect.right,
        cropRect.top,
      ),
      dimPaint,
    );
    canvas.drawRect(
      Rect.fromLTRB(
        imageRect.left,
        cropRect.bottom,
        imageRect.right,
        imageRect.bottom,
      ),
      dimPaint,
    );
    canvas.drawRect(
      Rect.fromLTRB(
        imageRect.left,
        cropRect.top,
        cropRect.left,
        cropRect.bottom,
      ),
      dimPaint,
    );
    canvas.drawRect(
      Rect.fromLTRB(
        cropRect.right,
        cropRect.top,
        imageRect.right,
        cropRect.bottom,
      ),
      dimPaint,
    );
    final borderPaint = Paint()
      ..color = const Color(0xFFE09321)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    _drawDashedLine(canvas, cropRect.topLeft, cropRect.topRight, borderPaint);
    _drawDashedLine(canvas, cropRect.topRight, cropRect.bottomRight, borderPaint);
    _drawDashedLine(canvas, cropRect.bottomRight, cropRect.bottomLeft, borderPaint);
    _drawDashedLine(canvas, cropRect.bottomLeft, cropRect.topLeft, borderPaint);
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashLength = 9.0;
    const gapLength = 6.0;
    final vector = end - start;
    final distance = vector.distance;
    if (distance == 0) return;
    final direction = vector / distance;
    var offset = 0.0;
    while (offset < distance) {
      final dashEnd = math.min(offset + dashLength, distance).toDouble();
      canvas.drawLine(
        start + direction * offset,
        start + direction * dashEnd,
        paint,
      );
      offset += dashLength + gapLength;
    }
  }

  @override
  bool shouldRepaint(_FreeformCropPainter oldDelegate) {
    return oldDelegate.imageRect != imageRect || oldDelegate.cropRect != cropRect;
  }
}

class _FreeformCropHandlePainter extends CustomPainter {
  const _FreeformCropHandlePainter({required this.cropRect});

  final Rect cropRect;

  @override
  void paint(Canvas canvas, Size size) {
    final handlePaint = Paint()..color = const Color(0xFFE09321);
    for (final corner in [
      cropRect.topLeft,
      cropRect.topRight,
      cropRect.bottomLeft,
      cropRect.bottomRight,
    ]) {
      canvas.drawCircle(corner, 8, handlePaint);
    }
  }

  @override
  bool shouldRepaint(_FreeformCropHandlePainter oldDelegate) {
    return oldDelegate.cropRect != cropRect;
  }
}
