import 'dart:math';

import 'package:material_ui/material_ui.dart';

class StarBurstAnimation extends StatefulWidget {
  final List<Offset> origins;
  final VoidCallback onCompleted;

  const StarBurstAnimation({
    super.key,
    required this.origins,
    required this.onCompleted,
  });

  @override
  State<StarBurstAnimation> createState() => _StarBurstAnimationState();
}

class _StarBurstAnimationState extends State<StarBurstAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<Animation<Offset>> _starAnimations;
  late List<Color> _starColors;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    );

    final random = Random();
    _starAnimations = [];
    _starColors = [];

    for (final _ in widget.origins) {
      for (int i = 0; i < 9; i++) {
        final angle = 2 * pi * i / 9;
        final radius = random.nextDouble() * 20 + 40;

        // Randomly assign color with 50% chance
        final color = random.nextBool()
            ? const Color(0xFFE09321)
            : Colors.amberAccent;

        _starAnimations.add(
          Tween<Offset>(
            begin: Offset.zero,
            end: Offset(
              cos(angle) * radius,
              sin(angle) * radius,
            ),
          ).animate(
            CurvedAnimation(
              parent: _controller,
              curve: Curves.easeOut,
            ),
          ),
        );

        _starColors.add(color);
      }
    }

    _controller.forward().whenComplete(widget.onCompleted);
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.none,
        children: widget.origins.expand((origin) {
          return List.generate(9, (index) {
            final animationIndex = widget.origins.indexOf(origin) * 9 + index;
            final animation = _starAnimations[animationIndex];
            final color = _starColors[animationIndex];

            return AnimatedBuilder(
              animation: _controller,
              builder: (_, _) {
                final offset = animation.value;
                final scale = 1.0 - _controller.value;
                final opacity = 1.0 - _controller.value;

                return Positioned(
                  left: origin.dx + offset.dx - 22,
                  top: origin.dy + offset.dy - 22,
                  child: Transform.scale(
                    scale: scale,
                    child: Opacity(
                      opacity: opacity,
                      child: Icon(
                        Icons.star,
                        color: color,
                        size: 15,
                      ),
                    ),
                  ),
                );
              },
            );
          });
        }).toList(),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
