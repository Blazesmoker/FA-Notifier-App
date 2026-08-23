import 'dart:math' as math;
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import 'package:fanotifier/features/image_tools/domain/image_optimizer_models.dart';

class ImageCropEditor extends StatefulWidget {
  const ImageCropEditor({
    super.key,
    required this.bytes,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.aspectRatio,
    required this.outputWidth,
    required this.outputHeight,
    required this.value,
    required this.onChanged,
    required this.onInteractionChanged,
  });

  final Uint8List bytes;
  final int sourceWidth;
  final int sourceHeight;
  final double aspectRatio;
  final int outputWidth;
  final int outputHeight;
  final ImageCropRegion value;
  final ValueChanged<ImageCropRegion> onChanged;
  final ValueChanged<bool> onInteractionChanged;

  @override
  State<ImageCropEditor> createState() => _ImageCropEditorState();
}

class _ImageCropEditorState extends State<ImageCropEditor> {
  late ImageCropRegion _value;
  Rect _frameRect = Rect.zero;
  Offset _gestureAnchorSource = Offset.zero;
  double _gestureStartZoom = 1;
  int _pointerCount = 0;
  bool _scaleActive = false;

  @override
  void initState() {
    super.initState();
    _value = widget.value;
  }

  @override
  void didUpdateWidget(ImageCropEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_scaleActive && oldWidget.value != widget.value) {
      _value = widget.value;
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_pointerCount == 0) widget.onInteractionChanged(true);
    _pointerCount++;
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (_pointerCount > 0) _pointerCount--;
    if (_pointerCount == 0 && !_scaleActive) {
      widget.onInteractionChanged(false);
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _pointerCount = 0;
    _scaleActive = false;
    widget.onInteractionChanged(false);
  }

  void _handleScaleStart(ScaleStartDetails details) {
    if (_frameRect.isEmpty) return;
    _scaleActive = true;
    _gestureStartZoom = _value.zoom;
    final geometry = _cropGeometry(_value.zoom);
    final renderScale = _frameRect.width / geometry.width;
    final center = Offset(
      _value.centerX * widget.sourceWidth,
      _value.centerY * widget.sourceHeight,
    );
    _gestureAnchorSource = center +
        (details.localFocalPoint - _frameRect.center) / renderScale;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (!_scaleActive || _frameRect.isEmpty) return;
    final zoom =
        (_gestureStartZoom * details.scale).clamp(1.0, 6.0).toDouble();
    final geometry = _cropGeometry(zoom);
    final renderScale = _frameRect.width / geometry.width;
    var center = _gestureAnchorSource -
        (details.localFocalPoint - _frameRect.center) / renderScale;
    center = Offset(
      center.dx
          .clamp(
            geometry.width / 2,
            widget.sourceWidth - geometry.width / 2,
          )
          .toDouble(),
      center.dy
          .clamp(
            geometry.height / 2,
            widget.sourceHeight - geometry.height / 2,
          )
          .toDouble(),
    );
    setState(() {
      _value = ImageCropRegion(
        centerX: center.dx / widget.sourceWidth,
        centerY: center.dy / widget.sourceHeight,
        zoom: zoom,
      );
    });
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    if (!_scaleActive) return;
    _scaleActive = false;
    widget.onChanged(_value);
    widget.onInteractionChanged(false);
  }

  Size _cropGeometry(double zoom) {
    final sourceRatio = widget.sourceWidth / widget.sourceHeight;
    final baseWidth = sourceRatio > widget.aspectRatio
        ? widget.sourceHeight * widget.aspectRatio
        : widget.sourceWidth.toDouble();
    final baseHeight = sourceRatio > widget.aspectRatio
        ? widget.sourceHeight.toDouble()
        : widget.sourceWidth / widget.aspectRatio;
    return Size(baseWidth / zoom, baseHeight / zoom);
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF4A4A4A)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Position your banner',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    '${widget.outputWidth}×${widget.outputHeight}',
                    style: const TextStyle(
                      color: Color(0xFFE09321),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 240,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final frameWidth =
                      math.max(1.0, constraints.maxWidth - 24).toDouble();
                  final frameHeight = frameWidth / widget.aspectRatio;
                  final frame = Rect.fromCenter(
                    center: Offset(
                      constraints.maxWidth / 2,
                      constraints.maxHeight / 2,
                    ),
                    width: frameWidth,
                    height: frameHeight,
                  );
                  _frameRect = frame;
                  final geometry = _cropGeometry(_value.zoom);
                  final renderScale = frame.width / geometry.width;
                  final renderedWidth = widget.sourceWidth * renderScale;
                  final renderedHeight = widget.sourceHeight * renderScale;
                  final imageLeft = frame.center.dx -
                      _value.centerX * widget.sourceWidth * renderScale;
                  final imageTop = frame.center.dy -
                      _value.centerY * widget.sourceHeight * renderScale;
                  final landscape = widget.sourceWidth >= widget.sourceHeight;
                  final cacheWidth = landscape
                      ? math.min(widget.sourceWidth, 2000).toInt()
                      : null;
                  final cacheHeight = landscape
                      ? null
                      : math.min(widget.sourceHeight, 2000).toInt();
                  return Listener(
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
                        children: [
                          const ColoredBox(color: Colors.black),
                          Positioned(
                            left: imageLeft,
                            top: imageTop,
                            width: renderedWidth,
                            height: renderedHeight,
                            child: RepaintBoundary(
                              child: Image.memory(
                                widget.bytes,
                                fit: BoxFit.fill,
                                filterQuality: FilterQuality.low,
                                gaplessPlayback: true,
                                cacheWidth: cacheWidth,
                                cacheHeight: cacheHeight,
                              ),
                            ),
                          ),
                          CustomPaint(
                            painter: _CropFramePainter(frame),
                          ),
                          const Positioned(
                            left: 12,
                            right: 12,
                            bottom: 12,
                            child: Center(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Color(0xCC202020),
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(20),
                                  ),
                                ),
                                child: Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 7,
                                  ),
                                  child: Text(
                                    'Drag to position · Pinch to zoom',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
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
            ),
          ],
        ),
      ),
    );
  }
}

class _CropFramePainter extends CustomPainter {
  const _CropFramePainter(this.frame);

  final Rect frame;

  @override
  void paint(Canvas canvas, Size size) {
    final dimPaint = Paint()..color = const Color(0x99000000);
    canvas.drawRect(Rect.fromLTRB(0, 0, size.width, frame.top), dimPaint);
    canvas.drawRect(
      Rect.fromLTRB(0, frame.bottom, size.width, size.height),
      dimPaint,
    );
    canvas.drawRect(
      Rect.fromLTRB(0, frame.top, frame.left, frame.bottom),
      dimPaint,
    );
    canvas.drawRect(
      Rect.fromLTRB(frame.right, frame.top, size.width, frame.bottom),
      dimPaint,
    );
    final framePaint = Paint()
      ..color = const Color(0xFFE09321)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    _drawDashedLine(canvas, frame.topLeft, frame.topRight, framePaint);
    _drawDashedLine(canvas, frame.topRight, frame.bottomRight, framePaint);
    _drawDashedLine(canvas, frame.bottomRight, frame.bottomLeft, framePaint);
    _drawDashedLine(canvas, frame.bottomLeft, frame.topLeft, framePaint);
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
  bool shouldRepaint(_CropFramePainter oldDelegate) {
    return oldDelegate.frame != frame;
  }
}
