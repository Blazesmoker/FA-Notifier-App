import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

class DashedLoadingIndicator extends StatefulWidget {
  const DashedLoadingIndicator({
    super.key,
    this.size = 22,
    this.color = const Color(0xFFE09321),
  });

  final double size;
  final Color color;

  @override
  State<DashedLoadingIndicator> createState() =>
      _DashedLoadingIndicatorState();
}

class _DashedLoadingIndicatorState extends State<DashedLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: RotationTransition(
        turns: _controller,
        child: CustomPaint(
          painter: _DashedLoadingPainter(color: widget.color),
        ),
      ),
    );
  }
}

class _DashedLoadingPainter extends CustomPainter {
  const _DashedLoadingPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const dashCount = 10;
    final strokeWidth = math.max(1.8, size.shortestSide * 0.1);
    final center = size.center(Offset.zero);
    final outerRadius = (size.shortestSide - strokeWidth) / 2;
    final innerRadius = outerRadius * 0.55;
    final step = math.pi * 2 / dashCount;
    for (var index = 0; index < dashCount; index++) {
      final opacity = 0.28 + (index + 1) / dashCount * 0.72;
      final angle = -math.pi / 2 + index * step;
      final direction = Offset(math.cos(angle), math.sin(angle));
      final paint = Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        center + direction * innerRadius,
        center + direction * outerRadius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLoadingPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
