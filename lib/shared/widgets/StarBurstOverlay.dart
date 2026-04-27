import 'package:flutter/cupertino.dart';

import 'package:FANotifier/shared/widgets/StarBurstAnimation.dart';

class StarBurstOverlay extends StatefulWidget {
  final Offset origin;
  final VoidCallback onCompleted;

  const StarBurstOverlay({
    super.key,
    required this.origin,
    required this.onCompleted,
  });

  @override
  State<StarBurstOverlay> createState() => _StarBurstOverlayState();
}

class _StarBurstOverlayState extends State<StarBurstOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    )..forward().whenComplete(widget.onCompleted);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: widget.origin.dx,
            top: widget.origin.dy,
            child: StarBurstAnimation(
              origins: [Offset.zero],
              onCompleted: () {},
            ),
          ),
        ],
      ),
    );
  }
}