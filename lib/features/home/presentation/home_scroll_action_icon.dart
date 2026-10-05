import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fanotifier/shared/widgets/scroll_return_controller.dart';

class HomeScrollActionFeedback {
  const HomeScrollActionFeedback(this.id, this.direction);

  final int id;
  final ScrollReturnDirection direction;
}

class HomeScrollActionIcon extends StatefulWidget {
  const HomeScrollActionIcon({
    required this.icon,
    required this.feedback,
    required this.active,
    this.badge,
    this.size = 24.0,
    super.key,
  });

  final Widget icon;
  final ValueListenable<HomeScrollActionFeedback?> feedback;
  final bool active;
  final Widget? badge;
  final double size;

  @override
  State<HomeScrollActionIcon> createState() => _HomeScrollActionIconState();
}

class _HomeScrollActionIconState extends State<HomeScrollActionIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;
  ScrollReturnDirection _direction = ScrollReturnDirection.up;
  int? _lastFeedback;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
      animationBehavior: AnimationBehavior.preserve,
    );
    _lastFeedback = widget.feedback.value?.id;
    widget.feedback.addListener(_onFeedback);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
  }

  void _onFeedback() {
    final feedback = widget.feedback.value;
    if (feedback == null || feedback.id == _lastFeedback) return;
    _lastFeedback = feedback.id;
    if (!widget.active) return;
    _direction = feedback.direction;
    _animation.forward(from: 0.0);
  }

  @override
  void didUpdateWidget(covariant HomeScrollActionIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.feedback != widget.feedback) {
      oldWidget.feedback.removeListener(_onFeedback);
      widget.feedback.addListener(_onFeedback);
      _lastFeedback = widget.feedback.value?.id;
    }
    if (!widget.active) _animation.reset();
  }

  @override
  void dispose() {
    widget.feedback.removeListener(_onFeedback);
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final normalIcon = widget.badge == null
        ? widget.icon
        : Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              widget.icon,
              Positioned.fill(child: widget.badge!),
            ],
          );
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _animation,
          child: normalIcon,
          builder: (context, child) {
            final t = _animation.value;
            final opacity = !_animation.isAnimating
                ? 0.0
                : _reduceMotion
                    ? (t < 0.85 ? 1.0 : 0.0)
                    : t < 0.2
                        ? Curves.easeOut.transform(t / 0.2)
                        : t > 0.75
                            ? 1.0 - Curves.easeIn.transform((t - 0.75) / 0.25)
                            : 1.0;
            final pulse = _reduceMotion
                ? 0.0
                : math.sin(math.pi * ((t - 0.2) / 0.55).clamp(0.0, 1.0));
            return Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                Opacity(opacity: 1.0 - opacity, child: child),
                Opacity(
                  opacity: opacity,
                  child: Transform.translate(
                    offset: Offset(
                      0.0,
                      (_direction == ScrollReturnDirection.up ? -4.0 : 4.0) * pulse,
                    ),
                    child: Transform.scale(
                      scale: 1.0 + 0.08 * pulse,
                      child: Icon(
                        _direction == ScrollReturnDirection.up
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: widget.size,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
