import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart' as glass;

const _barHeight = 56.0;
const _navIconSize = 24.0;
const _selectedColor = Color(0xFFE09321);

class HomeBottomNavigationBar extends StatefulWidget {
  const HomeBottomNavigationBar({
    required this.items,
    required this.currentIndex,
    required this.onSelected,
    super.key,
  });

  final List<BottomNavigationBarItem> items;
  final int currentIndex;
  final ValueChanged<int> onSelected;

  @override
  State<HomeBottomNavigationBar> createState() =>
      _HomeBottomNavigationBarState();
}

class _HomeBottomNavigationBarState extends State<HomeBottomNavigationBar>
    with SingleTickerProviderStateMixin {
  late final _NavMotion _motion;
  late final Animation<double> _lensOpacity;
  final ValueNotifier<bool> _lensVisible = ValueNotifier(false);
  final ValueNotifier<bool> _distortionEnabled = ValueNotifier(false);
  Timer? _holdTimer;
  int? _pointer;
  int? _pressedIndex;
  Offset? _pressPosition;
  Offset? _lastPosition;
  bool _holding = false;

  @override
  void initState() {
    super.initState();
    _motion = _NavMotion(this, widget.items.length, widget.currentIndex);
    _lensOpacity = Animation<double>.fromValueListenable(_motion);
    _motion.addListener(_updateLensVisibility);
  }

  void _updateLensVisibility() {
    _lensVisible.value = _motion.visibility > 0.002;
  }

  @override
  void didUpdateWidget(covariant HomeBottomNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      _clearGesture();
      _motion.select(widget.currentIndex);
    }
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _motion.dispose();
    _lensVisible.dispose();
    _distortionEnabled.dispose();
    super.dispose();
  }

  double _logicalX(double x) =>
      Directionality.of(context) == TextDirection.rtl ? _motion.width - x : x;

  void _onDown(PointerDownEvent event) {
    if (_pointer != null || event.buttons != kPrimaryButton) return;
    final x = _logicalX(event.localPosition.dx);
    var edge = 0.0;
    var index = widget.items.length - 1;
    for (var item = 0; item < widget.items.length; item++) {
      edge += _motion.itemWidth(item);
      if (x <= edge) {
        index = item;
        break;
      }
    }
    _pointer = event.pointer;
    _pressedIndex = index;
    _pressPosition = event.localPosition;
    _lastPosition = event.localPosition;
    _holdTimer = Timer(const Duration(milliseconds: 220), _startHold);
  }

  void _startHold() {
    if (_pointer == null || _holding) return;
    _holdTimer?.cancel();
    _holding = true;
    _distortionEnabled.value = true;
    _followPointer();
  }

  void _followPointer() {
    _motion.follow(
      _logicalX(_lastPosition!.dx),
      _lastPosition!.dy - _pressPosition!.dy,
    );
  }

  void _onMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    _lastPosition = event.localPosition;
    if (!_holding &&
        (event.localPosition - _pressPosition!).distance > kTouchSlop) {
      _startHold();
    } else if (_holding) {
      _followPointer();
    }
  }

  void _clearGesture() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _pointer = null;
    _pressedIndex = null;
    _pressPosition = null;
    _lastPosition = null;
    _holding = false;
    _distortionEnabled.value = false;
  }

  void _cancel() {
    _clearGesture();
    _motion.select(widget.currentIndex);
  }

  void _onUp(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    final offset = event.localPosition;
    if (!_holding &&
        (offset.dx < 0 ||
            offset.dx > _motion.width ||
            offset.dy < 0 ||
            offset.dy > _barHeight)) {
      _cancel();
      return;
    }
    final index = _holding ? _motion.nearestBubbleTab() : _pressedIndex!;
    final shouldSelect = !_holding || index != widget.currentIndex;
    final tapTransition = !_holding;
    _clearGesture();
    _motion.select(index, tapTransition: tapTransition);
    if (shouldSelect) widget.onSelected(index);
  }

  List<Widget> _buildItems() => [
        for (final item in widget.items) ...[
          Center(
            child: IconTheme(
              data: const IconThemeData(color: Colors.grey, size: _navIconSize),
              child: item.icon,
            ),
          ),
          Center(
            child: IconTheme(
              data: const IconThemeData(color: _selectedColor, size: _navIconSize),
              child: item.activeIcon,
            ),
          ),
          Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                item.label ?? '',
                maxLines: 1,
                style: const TextStyle(fontSize: 14, color: _selectedColor),
              ),
            ),
          ),
        ],
      ];

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return RepaintBoundary(
      child: ColoredBox(
        color: widget.items.first.backgroundColor ??
            Theme.of(context).scaffoldBackgroundColor,
        child: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              _motion.configure(constraints.maxWidth, reduceMotion);
              return Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _onDown,
                onPointerMove: _onMove,
                onPointerUp: _onUp,
                onPointerCancel: (event) {
                  if (event.pointer == _pointer) _cancel();
                },
                child: SizedBox(
                  height: _barHeight,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: ExcludeSemantics(
                          child: Flow(
                            clipBehavior: Clip.none,
                            delegate: _NavItemsFlow(
                              _motion,
                              rtl,
                              constraints.maxWidth,
                            ),
                            children: _buildItems(),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: ExcludeSemantics(
                            child: ValueListenableBuilder<bool>(
                              valueListenable: _lensVisible,
                              child: CustomSingleChildLayout(
                                delegate: _GlassLensLayout(_motion, rtl),
                                child: FadeTransition(
                                  opacity: _lensOpacity,

                                  child: ValueListenableBuilder<bool>(
                                    valueListenable: _distortionEnabled,
                                    builder: (context, distortionEnabled, child) =>
                                        glass.LiquidGlassLens(
                                      style: glass.LiquidGlassStyle(
                                        shape: glass.LiquidGlassShape.continuousRoundedRectangle(
                                        cornerRadius: 24,

                                        borderWidth: 0.5,

                                        lightColor: Color(0x807A7A7A),

                                        lightIntensity: 0.8,

                                        lightDirection: 30,

                                        borderType: glass.OpticalBorder(
                                          lightSpread: 0.50,

                                          ambientIntensity: 0.25,

                                          borderSolidity: 0.0,

                                          // 0.0 is useful here because you want a neutral greyish rim.
                                          borderSaturation: 0.0,
                                        ),
                                      ),

                                      appearance: glass.LiquidGlassAppearance(
                                        color: Colors.transparent,

                                        enableInnerRadiusTransparent: true,
                                      ),

                                      refraction: glass.LiquidGlassRefraction(
                                        // 0.01 is intentionally extremely subtle.
                                        distortion: distortionEnabled ? 0.03 : 0.0,

                                        distortionWidth: 8,

                                        magnification: 1,

                                        // 0.001 is extremely subtle.
                                        chromaticAberration:
                                            distortionEnabled ? 0.002 : 0.0,
                                      ),
                                    ),
                                    ),
                                  ),
                                ),
                              ),
                              builder: (context, visible, child) =>
                                  visible ? child! : const SizedBox.shrink(),
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: Row(
                          children: List.generate(
                            widget.items.length,
                            (index) => Expanded(
                              flex: index == widget.currentIndex ? 1500 : 1000,
                              child: Semantics(
                                label: widget.items[index].label,
                                button: true,
                                selected: index == widget.currentIndex,
                                onTap: () {
                                  _clearGesture();
                                  _motion.select(index, tapTransition: true);
                                  widget.onSelected(index);
                                },
                                child: const SizedBox.expand(),
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
      ),
    );
  }
}

class _NavMotion extends ChangeNotifier implements ValueListenable<double> {
  _NavMotion(TickerProvider vsync, this.count, this._selectedIndex) {
    _ticker = vsync.createTicker(_tick);
  }

  final int count;
  @override
  double get value => visibility.clamp(0.0, 1.0).toDouble();
  late final Ticker _ticker;
  int _selectedIndex;
  Duration? _lastTick;
  double width = 0;
  bool reduceMotion = false;
  double x = 0;
  double y = 0;
  double velocityX = 0;
  double velocityY = 0;
  double visibility = 0;
  double stretch = 0;
  double _movingSize = 0;
  double _movingSizeVelocity = 0;
  double _verticalStretch = 0;
  double _verticalStretchVelocity = 0;
  double _targetVerticalStretch = 0;
  double _targetX = 0;
  double _targetY = 0;
  double _targetVisibility = 0;
  bool _fadeAfterSettling = false;
  List<double>? _tapFrom;
  double _tapProgress = 1;

  double get unit => width / (count + 0.5);
  double get position {
    if (width <= 0) return _selectedIndex.toDouble();
    if (count <= 1) return 0;
    if (count == 2) {
      return ((x - centerAt(0)) / (centerAt(1) - centerAt(0)))
          .clamp(0.0, 1.0)
          .toDouble();
    }
    final secondCenter = centerAt(1);
    if (x <= secondCenter) {
      return ((x - centerAt(0)) / (secondCenter - centerAt(0)))
          .clamp(0.0, (count - 1).toDouble())
          .toDouble();
    }
    final lastInteriorCenter = centerAt(count - 2);
    if (x >= lastInteriorCenter) {
      final lastCenter = centerAt(count - 1);
      final edgePosition = count - 2 +
          (x - lastInteriorCenter) / (lastCenter - lastInteriorCenter);
      return edgePosition
          .clamp(0.0, (count - 1).toDouble())
          .toDouble();
    }
    return (x / unit - 0.75)
        .clamp(0.0, (count - 1).toDouble())
        .toDouble();
  }

  double activation(int index) {
    final from = _tapFrom;
    if (from != null) {
      final progress = Curves.easeOutCubic.transform(_tapProgress);
      final target = index == _selectedIndex ? 1.0 : 0.0;
      return from[index] + (target - from[index]) * progress;
    }
    return (1 - (index - position).abs()).clamp(0.0, 1.0).toDouble();
  }

  double itemWidth(int index) => unit * (1 + 0.5 * activation(index));

  double _edgeCenter(
    int index,
    double center,
    double ownWidth,
    double neighborWidth,
  ) {
    final neighborDistance = (ownWidth + neighborWidth) / 2;
    if (index == 0) {
      final neighborLeft = center + neighborDistance - _navIconSize / 2;
      return neighborLeft / 2;
    }
    final neighborRight = center - neighborDistance + _navIconSize / 2;
    return (neighborRight + width) / 2;
  }

  double centerAt(int index) {
    if (count <= 1) return width / 2;
    final center = unit * (index + 0.75);
    if (index == 0 || index == count - 1) {
      return _edgeCenter(index, center, unit * 1.5, unit);
    }
    return center;
  }

  double displayCenter(int index, double center, double activation) {
    if (count <= 1) return center;
    if (index == 0 || index == count - 1) {
      final neighbor = index == 0 ? 1 : count - 2;
      final target = _edgeCenter(
        index,
        center,
        itemWidth(index),
        itemWidth(neighbor),
      );
      return center + (target - center) * activation;
    }
    return center;
  }

  void configure(double nextWidth, bool nextReduceMotion) {
    if (nextWidth != width) {
      final previousWidth = width;
      width = nextWidth;
      if (previousWidth > 0) {
        final ratio = width / previousWidth;
        x *= ratio;
        _targetX *= ratio;
        velocityX *= ratio;
        if (!_ticker.isActive) {
          x = _targetX = centerAt(_selectedIndex);
        } else if (_targetVisibility == 0 || _fadeAfterSettling) {
          _targetX = centerAt(_selectedIndex);
        }
      } else {
        x = _targetX = centerAt(_selectedIndex);
      }
    }
    reduceMotion = nextReduceMotion;
    if (reduceMotion) {
      _snap();
      _stop();
    }
  }

  void select(int index, {bool tapTransition = false}) {
    if (_tapFrom != null && index == _selectedIndex) return;
    final from = tapTransition ? List<double>.generate(count, activation) : null;
    _tapFrom = null;
    _tapProgress = 1;
    _selectedIndex = index;
    _targetX = centerAt(index);
    _targetY = 0;
    _targetVerticalStretch = 0;
    _fadeAfterSettling = !tapTransition &&
        (_targetVisibility > 0 || _fadeAfterSettling);
    _targetVisibility = _fadeAfterSettling ? 1 : 0;
    if (tapTransition) {
      _snap();
      _tapFrom = from;
      _tapProgress = 0;
      _wake();
      return;
    }
    _wake();
  }

  void follow(double targetX, double targetY) {
    _tapFrom = null;
    _tapProgress = 1;
    _fadeAfterSettling = false;
    final edgeInset = math.min(width, unit * 1.5 + 8) / 2;
    _targetX = targetX.clamp(edgeInset, width - edgeInset).toDouble();
    _targetY = (targetY * 0.18).clamp(-8.0, 8.0).toDouble();
    _targetVerticalStretch = (targetY.abs() * 0.08).clamp(0.0, 6.0).toDouble();
    _targetVisibility = 1;
    _wake();
  }

  void _wake() {
    if (reduceMotion) {
      _snap();
      _stop();
      notifyListeners();
    } else if (!_ticker.isActive) {
      _lastTick = null;
      _ticker.start();
    }
  }

  void _snap() {
    _tapFrom = null;
    _tapProgress = 1;
    if (_fadeAfterSettling) {
      _fadeAfterSettling = false;
      _targetVisibility = 0;
    }
    x = _targetX;
    y = _targetY;
    visibility = _targetVisibility;
    velocityX = velocityY = stretch = 0;
    _movingSize = _movingSizeVelocity = _verticalStretchVelocity = 0;
    _verticalStretch = reduceMotion ? 0 : _targetVerticalStretch;
  }

  void _stop() {
    _ticker.stop();
    _lastTick = null;
  }

  void _tick(Duration elapsed) {
    final previous = _lastTick;
    _lastTick = elapsed;
    if (previous == null) return;
    var remaining = ((elapsed - previous).inMicroseconds / 1000000)
        .clamp(0.0, 0.05)
        .toDouble();
    while (remaining > 0) {
      final dt = math.min(remaining, 1 / 120);
      if (_tapFrom != null) {
        _tapProgress = (_tapProgress + dt / 0.2).clamp(0.0, 1.0).toDouble();
        if (_tapProgress >= 1) _tapFrom = null;
      }
      velocityX += (420 * (_targetX - x) - 24 * velocityX) * dt;
      velocityY += (420 * (_targetY - y) - 24 * velocityY) * dt;
      x += velocityX * dt;
      y += velocityY * dt;
      final alpha = 1 - math.exp(-dt / 0.045);
      visibility += (_targetVisibility - visibility) * alpha;
      final targetStretch =
          (velocityX.abs() / 160).clamp(0.0, 8.0).toDouble();
      stretch += (targetStretch - stretch) * alpha;
      final movingTarget = ((velocityX.abs() + velocityY.abs() * 4) / 550)
          .clamp(0.0, 1.0)
          .toDouble();
      _movingSizeVelocity +=
          (360 * (movingTarget - _movingSize) - 22 * _movingSizeVelocity) * dt;
      _movingSize += _movingSizeVelocity * dt;
      _verticalStretchVelocity +=
          (320 * (_targetVerticalStretch - _verticalStretch) -
                  22 * _verticalStretchVelocity) * dt;
      _verticalStretch += _verticalStretchVelocity * dt;
      remaining -= dt;
    }
    final motionSettled = (x - _targetX).abs() < 0.02 &&
        (y - _targetY).abs() < 0.02 &&
        velocityX.abs() < 0.1 &&
        velocityY.abs() < 0.1 &&
        stretch < 0.02 &&
        _movingSize.abs() < 0.002 &&
        _movingSizeVelocity.abs() < 0.02 &&
        (_verticalStretch - _targetVerticalStretch).abs() < 0.02 &&
        _verticalStretchVelocity.abs() < 0.1;
    if (motionSettled && _fadeAfterSettling) {
      x = _targetX;
      y = _targetY;
      velocityX = velocityY = stretch = 0;
      _fadeAfterSettling = false;
      _targetVisibility = 0;
    }
    if (motionSettled && _tapFrom == null &&
        (visibility - _targetVisibility).abs() < 0.002) {
      _snap();
      _stop();
    }
    notifyListeners();
  }

  Rect get bubbleRect {
    final p = position;
    final lower = p.floor();
    final upper = p.ceil();
    final itemSpan = itemWidth(lower) +
        (itemWidth(upper) - itemWidth(lower)) * (p - lower);
    final movingSize = _movingSize.clamp(0.0, 1.0).toDouble();
    final verticalStretch = _verticalStretch.clamp(0.0, 7.0).toDouble();
    final desiredBubbleWidth = (itemSpan +
            4 +
            4 * (1 - movingSize) +
            stretch * 0.35)
        .clamp(0.0, width)
        .toDouble();
    final bubbleWidth = desiredBubbleWidth;
    final left = (x - bubbleWidth / 2)
        .clamp(0.0, width - bubbleWidth)
        .toDouble();
    final bubbleHeight = 58 + 2 * (1 - movingSize) + verticalStretch;
    final top = 28 + y.clamp(-8.0, 8.0).toDouble() - bubbleHeight / 2;
    return Rect.fromLTWH(
      left,
      top,
      bubbleWidth,
      bubbleHeight,
    );
  }

  int nearestBubbleTab() {
    final center = bubbleRect.center.dx;
    var left = 0.0;
    var nearest = 0;
    var distance = double.infinity;
    for (var index = 0; index < count; index++) {
      final item = itemWidth(index);
      final itemCenter = displayCenter(
        index,
        left + item / 2,
        activation(index),
      );
      final nextDistance = (itemCenter - center).abs();
      if (nextDistance < distance) {
        nearest = index;
        distance = nextDistance;
      }
      left += item;
    }
    return nearest;
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}

class _NavItemsFlow extends FlowDelegate {
  _NavItemsFlow(this.motion, this.rtl, this.width)
      : reduceMotion = motion.reduceMotion,
        super(repaint: motion);

  final _NavMotion motion;
  final bool rtl;
  final double width;
  final bool reduceMotion;

  @override
  Size getSize(BoxConstraints constraints) => Size(width, _barHeight);

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) =>
      i % 3 == 2
          ? BoxConstraints.tightFor(
              width: math.max(0.0, width / (motion.count + 0.5) * 1.5 - 12),
              height: 18,
            )
          : const BoxConstraints.tightFor(width: 48, height: 40);

  @override
  void paintChildren(FlowPaintingContext context) {
    var left = 0.0;
    for (var index = 0; index < motion.count; index++) {
      final activation = motion.activation(index);
      final itemWidth = motion.itemWidth(index);
      final logicalCenter = motion.displayCenter(
        index,
        left + itemWidth / 2,
        activation,
      );
      final center = rtl ? width - logicalCenter : logicalCenter;
      final vertical = motion.y.clamp(-8.0, 8.0).toDouble() *
          activation *
          motion.visibility;
      final iconTransform = Matrix4.translationValues(
        center - 24,
        8 - 8 * activation + vertical,
        0,
      );
      context.paintChild(index * 3,
          transform: iconTransform, opacity: 1 - activation);
      context.paintChild(index * 3 + 1,
          transform: iconTransform, opacity: activation);
      final labelSize = context.getChildSize(index * 3 + 2)!;
      final scale = labelSize.width <= 0
          ? 1.0
          : ((itemWidth - 12) / labelSize.width).clamp(0.0, 1.0).toDouble();
      final labelTransform = Matrix4.diagonal3Values(scale, scale, 1)
        ..setTranslationRaw(
          center - labelSize.width * scale / 2,
          34 + 5 * (1 - activation) + vertical + (18 - 18 * scale) / 2,
          0,
        );
      context.paintChild(index * 3 + 2,
          transform: labelTransform, opacity: activation);
      left += itemWidth;
    }
  }

  @override
  bool shouldRelayout(covariant _NavItemsFlow oldDelegate) =>
      width != oldDelegate.width || motion.count != oldDelegate.motion.count;

  @override
  bool shouldRepaint(covariant _NavItemsFlow oldDelegate) =>
      motion != oldDelegate.motion ||
      rtl != oldDelegate.rtl ||
      width != oldDelegate.width ||
      reduceMotion != oldDelegate.reduceMotion;
}

class _GlassLensLayout extends SingleChildLayoutDelegate {
  _GlassLensLayout(this.motion, this.rtl) : super(relayout: motion);

  final _NavMotion motion;
  final bool rtl;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.tight(motion.bubbleRect.size);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final rect = motion.bubbleRect;
    return Offset(rtl ? size.width - rect.right : rect.left, rect.top);
  }

  @override
  bool shouldRelayout(covariant _GlassLensLayout oldDelegate) =>
      motion != oldDelegate.motion || rtl != oldDelegate.rtl;
}
