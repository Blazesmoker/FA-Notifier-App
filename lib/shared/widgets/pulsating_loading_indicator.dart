import 'package:material_ui/material_ui.dart';

class PulsatingLoadingIndicator extends StatefulWidget {
  final double size;


  final String assetPath;

  const PulsatingLoadingIndicator({
    super.key,
    this.size = 50.0,
    required this.assetPath,
  });

  @override
  State<PulsatingLoadingIndicator> createState() =>
      _PulsatingLoadingIndicatorState();
}

class _PulsatingLoadingIndicatorState extends State<PulsatingLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1250),
    );

    // First beat: quick scale up and down, a short pause,
    // then second beat: scale up and down, and a longer pause.
    _animation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.1)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 100,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.1, end: 1.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 100,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(1.0),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.1)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 100,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.1, end: 1.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 100,
      ),
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
