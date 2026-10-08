import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
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
    extends State<ProfileAnimatedMediaVisibility> with WidgetsBindingObserver {
  List<Listenable> _scrollListenables = [];
  Timer? _proactiveTimer;
  bool _isNearViewport = true;
  bool _visibilityCheckScheduled = false;
  bool _proactivelyResumed = false;
  bool _isResumed = true;

  bool get isActive => _isNearViewport;

  @override
  void initState() {
    super.initState();
    _isResumed = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final sources = <Listenable>{};
    final primary = PrimaryScrollController.maybeOf(context);
    if (primary != null) sources.add(primary);
    Scrollable.maybeOf(context);
    context.visitAncestorElements((element) {
      if (element is StatefulElement) {
        final state = element.state;
        if (state is ScrollableState &&
            axisDirectionToAxis(state.widget.axisDirection) == Axis.vertical) {
          sources.add(state.position);
        }
      }
      return true;
    });
    final nextListenables = sources.toList();
    if (!listEquals(_scrollListenables, nextListenables)) {
      for (final source in _scrollListenables) {
        source.removeListener(_scheduleVisibilityCheck);
      }
      _scrollListenables = nextListenables;
      for (final source in _scrollListenables) {
        source.addListener(_scheduleVisibilityCheck);
      }
    }
    _scheduleVisibilityCheck();
  }

  @override
  void didUpdateWidget(ProfileAnimatedMediaVisibility oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleVisibilityCheck();
  }

  @override
  void didChangeMetrics() {
    _scheduleVisibilityCheck();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    setState(() => _isResumed = state == AppLifecycleState.resumed);
    if (_isResumed) _scheduleVisibilityCheck();
  }

  @override
  void dispose() {
    _proactiveTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    for (final source in _scrollListenables) {
      source.removeListener(_scheduleVisibilityCheck);
    }
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
    WidgetsBinding.instance.ensureVisualUpdate();
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
    var viewport = Offset.zero & size;
    RenderObject? ancestor = renderObject.parent;
    while (ancestor != null) {
      final box = ancestor;
      if (ancestor is RenderAbstractViewport &&
          box is RenderBox &&
          box.attached &&
          box.hasSize) {
        viewport = viewport.intersect(
          box.localToGlobal(Offset.zero) & box.size,
        );
      }
      ancestor = ancestor.parent;
    }
    _setNearViewport(
      !viewport.isEmpty && bounds.overlaps(viewport.inflate(widget.lookAhead)),
    );
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
    _scheduleVisibilityCheck();
    final child = widget.manageTickerMode
        ? TickerMode(
            enabled: TickerMode.valuesOf(context).enabled &&
                _isNearViewport && _isResumed,
            child: widget.child,
          )
        : widget.child;
    return _ProfileMediaGeometryObserver(
      onGeometryChanged: _scheduleVisibilityCheck,
      child: child,
    );
  }
}

class _ProfileMediaGeometryObserver extends SingleChildRenderObjectWidget {
  const _ProfileMediaGeometryObserver({
    required this.onGeometryChanged,
    required super.child,
  });

  final VoidCallback onGeometryChanged;

  @override
  _ProfileMediaGeometryRenderObject createRenderObject(BuildContext context) {
    return _ProfileMediaGeometryRenderObject(onGeometryChanged);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _ProfileMediaGeometryRenderObject renderObject,
  ) {
    renderObject.onGeometryChanged = onGeometryChanged;
  }
}

class _ProfileMediaGeometryRenderObject extends RenderProxyBox {
  _ProfileMediaGeometryRenderObject(this.onGeometryChanged);

  VoidCallback onGeometryChanged;
  Rect? _lastBounds;

  @override
  void performLayout() {
    super.performLayout();
    _lastBounds = null;
    onGeometryChanged();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final bounds = localToGlobal(Offset.zero) & size;
    if (_lastBounds != bounds) {
      _lastBounds = bounds;
      onGeometryChanged();
    }
    super.paint(context, offset);
  }
}
