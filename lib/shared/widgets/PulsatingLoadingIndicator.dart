import 'package:flutter/material.dart';

class PulsatingLoadingIndicator extends StatefulWidget {
  /// The size of the icon.
  final double size;


  final String assetPath;

  const PulsatingLoadingIndicator({
    Key? key,
    this.size = 50.0,
    required this.assetPath,
  }) : super(key: key);

  @override
  _PulsatingLoadingIndicatorState createState() =>
      _PulsatingLoadingIndicatorState();
}

class _PulsatingLoadingIndicatorState extends State<PulsatingLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    // Define the total duration for one heartbeat cycle.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1250),
    );

    // Create a TweenSequence that simulates a double-beat:
    // First beat: quick scale up and down, a short pause,
    // then second beat: scale up and down, and a longer pause.
    _animation = TweenSequence<double>([
      // First beat: scale up (100ms)
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.1)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 100,
      ),
      // First beat: scale down (100ms)
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.1, end: 1.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 100,
      ),
      // Short pause (50ms)
      TweenSequenceItem(
        tween: ConstantTween<double>(1.0),
        weight: 50,
      ),
      // Second beat: scale up (100ms)
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.1)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 100,
      ),
      // Second beat: scale down (100ms)
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.1, end: 1.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 100,
      ),
      // Longer pause until next cycle (550ms)
      TweenSequenceItem(
        tween: ConstantTween<double>(1.0),
        weight: 550,
      ),
    ]).animate(_controller);

    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _animation,
      child: Image.asset(
        widget.assetPath,
        width: widget.size,
        height: widget.size,
      ),
    );
  }
}
