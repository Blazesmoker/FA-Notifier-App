// heart_animation_optimized.dart
import 'dart:math';
import 'package:flutter/material.dart';

/// A widget that shows:
/// - A small heart if [isFavorite] is true.
/// - On toggles unfav->fav -> big heart pop.
/// - On toggles fav->unfav -> big broken-heart pop.
/// - The big heart/broken-heart fades out after animation.
class HeartAnimationOptimized extends StatefulWidget {
  final bool isFavorite;
  final bool wasInitiallyFavorited;
  final Widget child;

  /// Container width/height to size the big heart animation
  final double containerWidth;
  final double containerHeight;

  /// Animation duration for the big heart
  final Duration animationDuration;

  /// Called when the user toggles the favorite state
  final ValueChanged<bool> onToggle;

  const HeartAnimationOptimized({
    Key? key,
    required this.isFavorite,
    required this.wasInitiallyFavorited,
    required this.child,
    required this.containerWidth,
    required this.containerHeight,
    this.animationDuration = const Duration(milliseconds: 300),
    required this.onToggle,
  }) : super(key: key);

  @override
  State<HeartAnimationOptimized> createState() => HeartAnimationOptimizedState();
}

class HeartAnimationOptimizedState extends State<HeartAnimationOptimized>
    with SingleTickerProviderStateMixin {
  /// Tracks the current favorite state inside this widget
  late bool _localFav;

  /// Animation controller for big hearts/broken hearts
  late AnimationController _controller;
  late Animation<double> _scaleAnim;
  late Animation<double> _opacityAnim;

  /// Display the big full heart icons
  bool _showBigHeart = false;

  /// Display the big broken heart icons
  bool _showBigBrokenHeart = false;

  /// Shows a small broken heart if toggling from favored->unfavored
  bool _showSmallBrokenHeart = false;

  /// Flag to track if initialization has been handled
  bool _hasInitialized = false;

  @override
  void initState() {
    super.initState();
    _localFav = widget.isFavorite;

    _controller = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );

    final curve = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.4).animate(curve);
    _opacityAnim = Tween<double>(begin: 0.0, end: 1.0).animate(curve);
  }

  @override
  void didUpdateWidget(covariant HeartAnimationOptimized oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isFavorite != widget.isFavorite) {
      if (!_hasInitialized) {
        if (widget.wasInitiallyFavorited && widget.isFavorite) {
          // Initially favorited and still favorited; skip animation
          setState(() {
            _localFav = widget.isFavorite;
            _hasInitialized = true;
          });
          return;
        } else if (!widget.wasInitiallyFavorited && widget.isFavorite) {
          // Initially unfavorited and now favorited; play animation
          setState(() {
            _showBigHeart = true;
            _showBigBrokenHeart = false;
            _showSmallBrokenHeart = false;
            _startAnimation(() {
              _showBigHeart = false;
            });
            _localFav = true;
            _hasInitialized = true;
          });
        } else if (widget.wasInitiallyFavorited && !widget.isFavorite) {
          // Initially favorited and now unfavorited; play broken heart animation
          setState(() {
            _showBigHeart = false;
            _showBigBrokenHeart = true;
            _showSmallBrokenHeart = true;
            _startAnimation(() {
              _showBigBrokenHeart = false;
              _showSmallBrokenHeart = false;
            });
            _localFav = false;
            _hasInitialized = true;
          });
        } else {
          // Initially unfavorited and still unfavorited; no animation
          setState(() {
            _localFav = widget.isFavorite;
            _hasInitialized = true;
          });
          return;
        }
      } else {
        if (!_localFav && widget.isFavorite) {
          // Toggled from unfav->fav
          setState(() {
            _showBigHeart = true;
            _showBigBrokenHeart = false;
            _showSmallBrokenHeart = false;
            _startAnimation(() {
              _showBigHeart = false;
            });
            _localFav = true;
          });
        } else if (_localFav && !widget.isFavorite) {
          // Toggled from fav->unfav
          setState(() {
            _showBigHeart = false;
            _showBigBrokenHeart = true;
            _showSmallBrokenHeart = true;
            _startAnimation(() {
              _showBigBrokenHeart = false;
              _showSmallBrokenHeart = false;
            });
            _localFav = false;
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _startAnimation(VoidCallback onComplete) {
    _controller.reset();
    _controller.forward().whenCompleteOrCancel(() {
      if (!mounted) return;
      setState(onComplete);
    });
  }

  /// Shows a small heart if it's currently favored
  bool get _shouldShowSmallHeart => _localFav;

  /// Shows a small broken heart if just toggled from fav->unfav
  bool get _shouldShowSmallBrokenHeart => _showSmallBrokenHeart;

  @override
  Widget build(BuildContext context) {
    final minDim = min(widget.containerWidth, widget.containerHeight);
    final bigHeartSize = minDim * 0.5;

    return Stack(
      children: [
        // Underlying child (the image)
        widget.child,

        // Big heart or big broken-heart
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (ctx, child) {
              final scale = _scaleAnim.value;
              final opacity = _opacityAnim.value;
              Widget icon = const SizedBox.shrink();
              if (_showBigHeart) {
                icon = Icon(
                  Icons.favorite,
                  color: Colors.redAccent,
                  size: bigHeartSize,
                );
              } else if (_showBigBrokenHeart) {
                icon = Icon(
                  Icons.heart_broken,
                  color: Colors.redAccent,
                  size: bigHeartSize,
                );
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

        // Small heart in the corner
        Positioned(
          top: 8,
          right: 8,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: _shouldShowSmallHeart ? 1.0 : 0.0,
            child: const Icon(
              Icons.favorite,
              color: Colors.redAccent,
              size: 24,
            ),
          ),
        ),

        // Small broken heart in the corner
        Positioned(
          top: 8,
          right: 8,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: _shouldShowSmallBrokenHeart ? 1.0 : 0.0,
            child: const Icon(
              Icons.heart_broken,
              color: Colors.redAccent,
              size: 24,
            ),
          ),
        ),
      ],
    );
  }
}
