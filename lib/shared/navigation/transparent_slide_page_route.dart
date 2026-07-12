import 'package:flutter/material.dart';

class TransparentSlidePageRoute<T> extends PageRoute<T> {
  TransparentSlidePageRoute({
    required this.builder,
    super.settings,
    super.requestFocus,
    this.allowSnapshotting = true,
    this.fullscreenDialog = false,
    this.maintainState = true,
    this.routeTransitionDuration = const Duration(milliseconds: 280),
    this.routeReverseTransitionDuration = const Duration(milliseconds: 280),
  });

  final WidgetBuilder builder;
  final bool allowSnapshotting;
  @override
  final bool fullscreenDialog;
  @override
  final bool maintainState;
  final Duration routeTransitionDuration;
  final Duration routeReverseTransitionDuration;

  @override
  bool get opaque => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  Duration get transitionDuration => routeTransitionDuration;

  @override
  Duration get reverseTransitionDuration => routeReverseTransitionDuration;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return builder(context);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return SlideTransition(
      position: animation.drive(
        Tween<Offset>(
          begin: const Offset(1.0, 0.0),
          end: Offset.zero,
        ).chain(
          CurveTween(curve: Curves.easeOutCubic),
        ),
      ),
      child: child,
    );
  }
}
