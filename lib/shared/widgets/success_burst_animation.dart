import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

class SuccessBurstAnimation extends StatefulWidget {
  const SuccessBurstAnimation({super.key});

  static const Duration animationDuration = Duration(milliseconds: 650);
  static const Duration displayDuration = Duration(milliseconds: 1050);

  @override
  State<SuccessBurstAnimation> createState() => _SuccessBurstAnimationState();
}

class _SuccessBurstAnimationState extends State<SuccessBurstAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: SuccessBurstAnimation.animationDuration,
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final iconProgress =
            (_controller.value / 0.48).clamp(0.0, 1.0).toDouble();
        final iconScale = Curves.elasticOut.transform(iconProgress);
        final iconOpacity = Curves.easeOut.transform(iconProgress);
        return Stack(
          clipBehavior: Clip.none,
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            CustomPaint(
              painter: _SuccessBurstPainter(
                progress: _controller.value,
              ),
            ),
            OverflowBox(
              alignment: Alignment.center,
              minWidth: 20,
              maxWidth: 20,
              minHeight: 20,
              maxHeight: 20,
              child: Opacity(
                opacity: iconOpacity,
                child: Transform.scale(
                  scale: iconScale,
                  child: const Icon(
                    Icons.check_circle,
                    color: Color(0xFF65C466),
                    size: 20,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SuccessBurstPainter extends CustomPainter {
  const _SuccessBurstPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final burstProgress =
        ((progress - 0.08) / 0.78).clamp(0.0, 1.0).toDouble();
    if (burstProgress <= 0 || burstProgress >= 1) return;
    final travel = Curves.easeOutCubic.transform(burstProgress);
    final opacity = (1 - burstProgress).clamp(0.0, 1.0).toDouble();
    final center = size.center(Offset.zero);
    const colors = [Color(0xFF65C466), Color(0xFF9BEA93)];

    for (var index = 0; index < 8; index++) {
      final angle = -math.pi / 2 + index * math.pi / 4;
      final distance = 5 + travel * (index.isEven ? 19 : 16);
      final particleCenter = center +
          Offset(
            math.cos(angle) * distance,
            math.sin(angle) * distance,
          );
      final paint = Paint()
        ..color = colors[index % colors.length].withValues(alpha: opacity);
      canvas.drawCircle(
        particleCenter,
        1.9 - burstProgress * 0.7,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SuccessBurstPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
