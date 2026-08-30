import 'dart:math' as math;

import 'package:fanotifier/shared/widgets/dashed_loading_indicator.dart';
import 'package:material_ui/material_ui.dart';

enum NotificationRemovalButtonPhase {
  idle,
  processing,
  success,
}

class NotificationRemovalButtonContent extends StatelessWidget {
  const NotificationRemovalButtonContent({
    super.key,
    required this.phase,
  });

  final NotificationRemovalButtonPhase phase;

  @override
  Widget build(BuildContext context) {
    return NotificationActionButtonContent(
      phase: phase,
      idleChild: const Text('Remove Selected'),
    );
  }
}

class NotificationActionButtonContent extends StatelessWidget {
  const NotificationActionButtonContent({
    super.key,
    required this.phase,
    required this.idleChild,
  });

  final NotificationRemovalButtonPhase phase;
  final Widget idleChild;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.center,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Opacity(
            opacity: phase == NotificationRemovalButtonPhase.idle ? 1 : 0,
            child: idleChild,
          ),
          if (phase == NotificationRemovalButtonPhase.processing)
            const Positioned.fill(
              child: OverflowBox(
                alignment: Alignment.center,
                minWidth: 17,
                maxWidth: 17,
                minHeight: 17,
                maxHeight: 17,
                child: DashedLoadingIndicator(size: 17),
              ),
            ),
          if (phase == NotificationRemovalButtonPhase.success)
            const Positioned.fill(
              child: _NotificationRemovalSuccessAnimation(),
            ),
        ],
      ),
    );
  }
}

class _NotificationRemovalSuccessAnimation extends StatefulWidget {
  const _NotificationRemovalSuccessAnimation();

  @override
  State<_NotificationRemovalSuccessAnimation> createState() =>
      _NotificationRemovalSuccessAnimationState();
}

class _NotificationRemovalSuccessAnimationState
    extends State<_NotificationRemovalSuccessAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
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
              painter: _NotificationRemovalBurstPainter(
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

class _NotificationRemovalBurstPainter extends CustomPainter {
  const _NotificationRemovalBurstPainter({required this.progress});

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
  bool shouldRepaint(covariant _NotificationRemovalBurstPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
