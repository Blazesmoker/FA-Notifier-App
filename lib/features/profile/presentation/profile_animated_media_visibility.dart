import 'dart:async';

import 'package:material_ui/material_ui.dart';

class ProfileAnimatedMediaVisibility extends StatefulWidget {
  const ProfileAnimatedMediaVisibility({
    super.key,
    required this.child,
    this.onActiveChanged,
    this.lookAhead = 140.0,
    this.manageTickerMode = true,
  });

  final Widget child;
  final ValueChanged<bool>? onActiveChanged;
  final double lookAhead;
  final bool manageTickerMode;

  @override
  State<ProfileAnimatedMediaVisibility> createState() =>
      ProfileAnimatedMediaVisibilityState();
}

class ProfileAnimatedMediaVisibilityState
    extends State<ProfileAnimatedMediaVisibility> {
  Listenable? _scrollListenable;
  Timer? _proactiveTimer;
  bool _isNearViewport = true;
  bool _visibilityCheckScheduled = false;
  bool _proactivelyResumed = false;

  bool get isActive => _isNearViewport;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextListenable = PrimaryScrollController.maybeOf(context) ??
        Scrollable.maybeOf(context)?.position;
    if (!identical(_scrollListenable, nextListenable)) {
      _scrollListenable?.removeListener(_scheduleVisibilityCheck);
      _scrollListenable = nextListenable;
      _scrollListenable?.addListener(_scheduleVisibilityCheck);
    }
    _scheduleVisibilityCheck();
  }

  @override
  void didUpdateWidget(ProfileAnimatedMediaVisibility oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lookAhead != widget.lookAhead) {
      _scheduleVisibilityCheck();
    }
  }

  @override
  void dispose() {
    _proactiveTimer?.cancel();
    _scrollListenable?.removeListener(_scheduleVisibilityCheck);
    super.dispose();
  }

  void resumeProactively({
    Duration hold = const Duration(milliseconds: 450),
  }) {
    _proactiveTimer?.cancel();
    _proactivelyResumed = true;
    _setNearViewport(true);
    _proactiveTimer = Timer(hold, () {
      _proactivelyResumed = false;
      _scheduleVisibilityCheck();
    });
  }

  void _scheduleVisibilityCheck() {
    if (!mounted || _visibilityCheckScheduled) {
      return;
    }
    _visibilityCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibilityCheckScheduled = false;
      if (!mounted || _proactivelyResumed) {
        return;
      }
      _updateViewportVisibility();
    });
  }

  void _updateViewportVisibility() {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      return;
    }
    final topLeft = renderObject.localToGlobal(Offset.zero);
    final bottomRight = renderObject.localToGlobal(
      renderObject.size.bottomRight(Offset.zero),
    );
    final bounds = Rect.fromPoints(topLeft, bottomRight);
    final size = MediaQuery.sizeOf(context);
    final viewport = Rect.fromLTWH(
      -widget.lookAhead,
      -widget.lookAhead,
      size.width + (widget.lookAhead * 2),
      size.height + (widget.lookAhead * 2),
    );
    _setNearViewport(bounds.overlaps(viewport));
  }

  void _setNearViewport(bool value) {
    if (_isNearViewport == value) {
      return;
    }
    if (mounted) {
      setState(() {
        _isNearViewport = value;
      });
    } else {
      _isNearViewport = value;
    }
    widget.onActiveChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.manageTickerMode) {
      return widget.child;
    }
    return TickerMode(
      enabled: TickerMode.valuesOf(context).enabled && _isNearViewport,
      child: widget.child,
    );
  }
}
