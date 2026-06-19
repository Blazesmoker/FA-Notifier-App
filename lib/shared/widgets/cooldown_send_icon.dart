import 'dart:math' as math;

import 'package:flutter/material.dart';

class CooldownSendIcon extends StatefulWidget {
  const CooldownSendIcon({
    super.key,
    required this.remainingSeconds,
    required this.totalSeconds,
  });

  final int remainingSeconds;
  final int totalSeconds;

  @override
  State<CooldownSendIcon> createState() => _CooldownSendIconState();
}

class _CooldownSendIconState extends State<CooldownSendIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _progressAnimation;

  double get _targetProgress => widget.totalSeconds <= 0
      ? 0.0
      : (widget.remainingSeconds / widget.totalSeconds).clamp(0.0, 1.0);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _progressAnimation = AlwaysStoppedAnimation<double>(_targetProgress);
  }

  @override
  void didUpdateWidget(CooldownSendIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    final begin = _progressAnimation.value;
    final target = _targetProgress;
    _controller.stop();
    _controller.reset();
    if (target >= begin) {
      _progressAnimation = AlwaysStoppedAnimation<double>(target);
      return;
    }
    _controller.duration = const Duration(seconds: 1);
    _progressAnimation = Tween<double>(
      begin: begin,
      end: target,
    ).animate(_controller);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.remainingSeconds > 99
        ? '99+'
        : widget.remainingSeconds.toString();

    return SizedBox(
      width: 28,
      height: 28,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _CooldownRingPainter(progress: _progressAnimation.value),
            child: child,
          );
        },
        child: Center(
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFFE09321),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _CooldownRingPainter extends CustomPainter {
  const _CooldownRingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final paint = Paint()
      ..color = const Color(0xFFE09321)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final rect = Offset.zero & size;
    final elapsed = 1 - progress;
    final start = -math.pi / 2 + (2 * math.pi * elapsed);
    final sweep = 2 * math.pi * progress;
    canvas.drawArc(rect.deflate(1), start, sweep, false, paint);
  }

  @override
  bool shouldRepaint(_CooldownRingPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
