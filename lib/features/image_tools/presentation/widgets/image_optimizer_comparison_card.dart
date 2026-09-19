import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fanotifier/features/image_tools/presentation/widgets/image_optimizer_controls.dart';
import 'package:fanotifier/features/image_tools/presentation/widgets/image_optimizer_styles.dart';

class ImageComparisonCard extends StatefulWidget {
  const ImageComparisonCard({
    super.key,
    required this.originalBytes,
    required this.changedBytes,
    required this.onOpenOriginal,
    required this.onOpenChanged,
    required this.onZoomChanged,
    required this.onInteractionChanged,
  });

  final Uint8List originalBytes;
  final Uint8List changedBytes;
  final VoidCallback onOpenOriginal;
  final VoidCallback onOpenChanged;
  final ValueChanged<bool> onZoomChanged;
  final ValueChanged<bool> onInteractionChanged;

  @override
  State<ImageComparisonCard> createState() => _ImageComparisonCardState();
}

class _ImageComparisonCardState extends State<ImageComparisonCard> {
  final ValueNotifier<double> _comparisonListenable = ValueNotifier(0.5);
  final TransformationController _previewTransformationController =
      TransformationController();
  Offset _previewDoubleTapPosition = Offset.zero;
  bool _zoomed = false;
  int _activePreviewPointers = 0;

  @override
  void initState() {
    super.initState();
    _previewTransformationController.addListener(
      _handlePreviewTransformationChanged,
    );
  }

  @override
  void dispose() {
    _comparisonListenable.dispose();
    _previewTransformationController.removeListener(
      _handlePreviewTransformationChanged,
    );
    _previewTransformationController.dispose();
    super.dispose();
  }

  void _handlePreviewTransformationChanged() {
    final zoomed =
        _previewTransformationController.value.getMaxScaleOnAxis() > 1.05;
    if (_zoomed == zoomed) return;
    _zoomed = zoomed;
    widget.onZoomChanged(zoomed);
    if (zoomed && _activePreviewPointers > 0) {
      widget.onInteractionChanged(true);
    } else if (!zoomed) {
      widget.onInteractionChanged(false);
    }
  }

  void _handlePreviewPointerDown(PointerDownEvent event) {
    _activePreviewPointers++;
    if (_zoomed) widget.onInteractionChanged(true);
  }

  void _handlePreviewPointerEnd(PointerEvent event) {
    if (_activePreviewPointers > 0) _activePreviewPointers--;
    if (_activePreviewPointers == 0) widget.onInteractionChanged(false);
  }

  void _togglePreviewZoom() {
    final currentScale =
        _previewTransformationController.value.getMaxScaleOnAxis();
    if (currentScale > 1.05) {
      _previewTransformationController.value = Matrix4.identity();
      return;
    }
    const scale = 2.5;
    _previewTransformationController.value = Matrix4.identity()
      ..translateByDouble(
        -_previewDoubleTapPosition.dx * (scale - 1),
        -_previewDoubleTapPosition.dy * (scale - 1),
        0,
        1,
      )
      ..scaleByDouble(scale, scale, scale, 1);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: surface,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF4A4A4A)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Listener(
            onPointerDown: _handlePreviewPointerDown,
            onPointerUp: _handlePreviewPointerEnd,
            onPointerCancel: _handlePreviewPointerEnd,
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final cacheWidth = (constraints.maxWidth *
                        MediaQuery.of(context).devicePixelRatio)
                    .ceil()
                    .clamp(1, 1600)
                    .toInt();
                final changedImage = ColoredBox(
                  color: Colors.black,
                  child: Image.memory(
                    widget.changedBytes,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.low,
                    gaplessPlayback: true,
                    cacheWidth: cacheWidth,
                  ),
                );
                final originalImage = ColoredBox(
                  color: Colors.black,
                  child: Image.memory(
                    widget.originalBytes,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.low,
                    gaplessPlayback: true,
                    cacheWidth: cacheWidth,
                  ),
                );
                final originalLayer = IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _previewTransformationController,
                    child: SizedBox(
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      child: originalImage,
                    ),
                    builder: (context, child) => Transform(
                      transform: _previewTransformationController.value,
                      child: child,
                    ),
                  ),
                );
                  return Stack(
                  fit: StackFit.expand,
                  children: [
                    GestureDetector(
                      onDoubleTapDown: (details) {
                        _previewDoubleTapPosition = details.localPosition;
                      },
                      onDoubleTap: _togglePreviewZoom,
                      child: InteractiveViewer(
                        transformationController:
                            _previewTransformationController,
                        minScale: 1,
                        maxScale: 4,
                        child: SizedBox(
                          width: constraints.maxWidth,
                          height: constraints.maxHeight,
                          child: changedImage,
                        ),
                      ),
                    ),
                    IgnorePointer(
                      child: ValueListenableBuilder<double>(
                        valueListenable: _comparisonListenable,
                        builder: (context, comparison, child) {
                          final dividerLeft =
                              (constraints.maxWidth * comparison - 0.75)
                                  .clamp(0.0, constraints.maxWidth - 1.5)
                                  .toDouble();
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRect(
                                clipper: _FractionClipper(comparison),
                                child: originalLayer,
                              ),
                              Positioned(
                                left: dividerLeft,
                                top: 0,
                                bottom: 0,
                                child: const SizedBox(
                                  width: 1.5,
                                  child: ColoredBox(color: orange),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                );
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 7, 10, 10),
            child: Row(
              children: [
                _PreviewLabel(
                  text: 'Original',
                  onTap: widget.onOpenOriginal,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: comparisonSliderHorizontalPadding,
                    ),
                    child: ValueListenableBuilder<double>(
                      valueListenable: _comparisonListenable,
                      builder: (context, comparison, child) {
                        return SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: orange,
                            inactiveTrackColor: const Color(0xFF505050),
                            thumbColor: orange,
                            overlayColor: orange.withValues(alpha: 0.16),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: sliderOverlayRadius,
                            ),
                            trackShape:
                                const FullWidthRoundedSliderTrackShape(),
                          ),
                          child: Semantics(
                            label:
                                'Drag to compare the original and changed image',
                            child: Slider(
                              value: comparison,
                              onChanged: (value) {
                                _comparisonListenable.value = value;
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                _PreviewLabel(
                  text: 'Changed',
                  onTap: widget.onOpenChanged,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewLabel extends StatelessWidget {
  const _PreviewLabel({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: orange,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _FractionClipper extends CustomClipper<Rect> {
  const _FractionClipper(this.fraction);

  final double fraction;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(_FractionClipper oldClipper) => oldClipper.fraction != fraction;
}
