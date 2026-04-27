// lib/widgets/heart_animation.dart

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

/// A reusable widget that shows an animated heart or broken-heart
/// when [isFavorite] changes.
///
/// 3-second debounce by default; if the user toggles again
/// within that time, we cancel and restart the timer. After the user
/// leaves the state unchanged for the full debounce period, we call
/// [onDebounceComplete] with the final "favorite" value.
///
/// Additionally, if this widget is disposed (e.g. user navigates away),
/// and the debounce timer is still active, we call [onDebounceComplete]
/// right in dispose() to ensure the final toggle doesn't get lost.
class HeartAnimationWidget extends StatefulWidget {
  final bool isFavorite;

  /// Called after user leaves `isFavorite` unchanged for [debounceDuration],
  /// or if the widget disposes while there's still an active timer.
  final ValueChanged<bool>? onDebounceComplete;

  final Widget child;

  /// The container size in which the big heart will appear, so we
  /// can size the big heart to about 50% of the smaller dimension.
  final double containerWidth;
  final double containerHeight;

  /// The quick fade/scale animation duration for the big heart.
  final Duration animationDuration;

  /// How long we wait for the user to stop toggling before finalizing.
  final Duration debounceDuration;

  const HeartAnimationWidget({
    Key? key,
    required this.isFavorite,
    required this.child,
    required this.containerWidth,
    required this.containerHeight,
    this.onDebounceComplete,
    this.animationDuration = const Duration(milliseconds: 300),
    this.debounceDuration = const Duration(seconds: 3),
  }) : super(key: key);

  @override
  State<HeartAnimationWidget> createState() => _HeartAnimationWidgetState();
}

class _HeartAnimationWidgetState extends State<HeartAnimationWidget>
    with SingleTickerProviderStateMixin {
  late bool _localFav;
  bool _showBigHeart = false;
  bool _showBigBrokenHeart = false;
  bool _showSmallHeart = false;
  bool _showSmallBrokenHeart = false;

  late AnimationController _controller;
  late Animation<double> _scaleAnim;
  late Animation<double> _opacityAnim;

  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _localFav = widget.isFavorite;
    _showSmallHeart = _localFav; // If we start favored, show the small heart.

    _controller = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );

    final curved = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.4).animate(curved);
    _opacityAnim = Tween<double>(begin: 0.0, end: 1.0).animate(curved);
  }

  @override
  void didUpdateWidget(covariant HeartAnimationWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.isFavorite != widget.isFavorite) {
      _triggerAnimation(widget.isFavorite);
      _resetDebounceTimer();
    }
  }

  @override
  void dispose() {
    // If the user leaves before the timer fires, we finalize the last known state:
    if (_debounceTimer?.isActive ?? false) {
      _debounceTimer!.cancel();
      widget.onDebounceComplete?.call(_localFav);
    }
    _controller.dispose();
    super.dispose();
  }

  /// Cancel any existing timer, start a new 3s countdown.
  void _resetDebounceTimer() {
    _debounceTimer?.cancel();
    if (widget.onDebounceComplete != null) {
      _debounceTimer = Timer(widget.debounceDuration, () {
        widget.onDebounceComplete?.call(_localFav);
      });
    }
  }

  /// Run the pop animation (heart or broken heart).
  void _triggerAnimation(bool newFav) {
    setState(() {
      _localFav = newFav;
      _showBigHeart = false;
      _showBigBrokenHeart = false;
      _showSmallBrokenHeart = false;

      if (newFav) {
        // Fav -> show big heart & small heart
        _showBigHeart = true;
        _showSmallHeart = true;
      } else {
        // Unfav -> show big broken heart & small broken heart
        _showBigBrokenHeart = true;
        _showSmallBrokenHeart = true;
        _showSmallHeart = false;
      }

      _controller.reset();
      _controller.forward().whenCompleteOrCancel(() {
        if (!mounted) return;
        setState(() {
          _showBigHeart = false;
          _showBigBrokenHeart = false;
          // If it's currently unfaved, hide the broken heart icons
          if (!newFav) {
            _showSmallBrokenHeart = false;
          }
        });
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final minDim = min(widget.containerWidth, widget.containerHeight);
    final bigHeartSize = minDim * 0.5;

    return Stack(
      children: [
        widget.child,
        // Big heart or broken heart in the center
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (_, __) {
              final scale = _scaleAnim.value;
              final opacity = _opacityAnim.value;

              Widget icon = const SizedBox.shrink();
              if (_showBigHeart) {
                icon = Icon(Icons.favorite, color: Colors.redAccent, size: bigHeartSize);
              } else if (_showBigBrokenHeart) {
                icon = Icon(Icons.heart_broken, color: Colors.redAccent, size: bigHeartSize);
              }

              return Center(
                child: Transform.scale(
                  scale: scale,
                  child: Opacity(
                    opacity: opacity,
                    child: icon,
                  ),
                ),
              );
            },
          ),
        ),

        // Small heart
        Positioned(
          top: 8,
          right: 8,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: _showSmallHeart ? 1.0 : 0.0,
            child: const Icon(Icons.favorite, color: Colors.redAccent, size: 24),
          ),
        ),

        // Small broken heart
        Positioned(
          top: 8,
          right: 8,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: _showSmallBrokenHeart ? 1.0 : 0.0,
            child: const Icon(Icons.heart_broken, color: Colors.redAccent, size: 24),
          ),
        ),
      ],
    );
  }
}
