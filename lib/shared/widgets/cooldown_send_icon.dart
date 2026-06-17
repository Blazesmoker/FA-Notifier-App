import 'dart:math' as math;

import 'package:flutter/material.dart';

class CooldownSendIcon extends StatelessWidget {
  const CooldownSendIcon({
    super.key,
    required this.remainingSeconds,
    required this.totalSeconds,
  });

  final int remainingSeconds;
  final int totalSeconds;

  @override
  Widget build(BuildContext context) {
    final progress = totalSeconds <= 0
        ? 0.0
        : (remainingSeconds / totalSeconds).clamp(0.0, 1.0);
    final text = remainingSeconds > 99 ? '99+' : remainingSeconds.toString();

    return SizedBox(
      width: 28,
      height: 28,
      child: CustomPaint(
        painter: _CooldownRingPainter(progress: progress),
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
