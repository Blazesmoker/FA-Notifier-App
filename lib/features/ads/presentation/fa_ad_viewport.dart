import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

typedef FaAdGeometryReader = FaAdViewportGeometry? Function({
  FaAdViewportMetrics? metrics,
});

class FaAdViewportMetrics {
  const FaAdViewportMetrics({required this.bounds, required this.atStart});

  final Rect bounds;
  final bool atStart;
}

FaAdViewportMetrics? readFaAdViewportMetrics(
  GlobalKey viewportKey, ScrollController scrollController,
) {
  if (!scrollController.hasClients) return null;
  final viewport = viewportKey.currentContext?.findRenderObject();
  if (viewport is! RenderBox || !viewport.attached || !viewport.hasSize) {
    return null;
  }
  final position = scrollController.position;
  return FaAdViewportMetrics(
    bounds: viewport.localToGlobal(Offset.zero) & viewport.size,
    atStart: (position.pixels - position.minScrollExtent).abs() <= 0.5,
  );
}

class FaAdViewportGeometry {
  const FaAdViewportGeometry({
    required this.bounds,
    required this.viewport,
    required this.atStart,
    required this.isIntersecting,
    required this.intersectionRatio,
  });

  final Rect bounds;
  final Rect viewport;
  final bool atStart;
  final bool isIntersecting;
  final double intersectionRatio;
}

class FaAdViewport extends StatefulWidget {
  const FaAdViewport({
    required this.viewportKey,
    required this.scrollController,
    required this.active,
    required this.onVisibility,
    required this.child,
    this.onGeometryReader,
    this.onLayoutChanged,
    this.geometryPadding = EdgeInsets.zero,
    this.visibilityManagedExternally = false,
    super.key,
  });

  final GlobalKey viewportKey;
  final ScrollController scrollController;
  final ValueListenable<bool> active;
  final void Function(bool visible, double ratio) onVisibility;
  final Widget child;
  final void Function(FaAdGeometryReader reader, bool attached)? onGeometryReader;
  final VoidCallback? onLayoutChanged;
  final EdgeInsets geometryPadding;
  final bool visibilityManagedExternally;

  @override
  State<FaAdViewport> createState() => _FaAdViewportState();
}

class _FaAdViewportState extends State<FaAdViewport> {
  final GlobalKey _boundsKey = GlobalKey();
  late final FaAdGeometryReader _geometryReader = _readGeometry;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    if (!widget.visibilityManagedExternally) {
      widget.scrollController.addListener(_schedule);
      widget.active.addListener(_schedule);
    }
    widget.onGeometryReader?.call(_geometryReader, true);
    _schedule();
  }

  @override
  void didUpdateWidget(covariant FaAdViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    final managementChanged = oldWidget.visibilityManagedExternally !=
        widget.visibilityManagedExternally;
    if (managementChanged || oldWidget.scrollController != widget.scrollController) {
      if (!oldWidget.visibilityManagedExternally) {
        oldWidget.scrollController.removeListener(_schedule);
      }
      if (!widget.visibilityManagedExternally) {
        widget.scrollController.addListener(_schedule);
      }
    }
    if (managementChanged || oldWidget.active != widget.active) {
      if (!oldWidget.visibilityManagedExternally) {
        oldWidget.active.removeListener(_schedule);
      }
      if (!widget.visibilityManagedExternally) {
        widget.active.addListener(_schedule);
      }
    }
    oldWidget.onGeometryReader?.call(_geometryReader, false);
    widget.onGeometryReader?.call(_geometryReader, true);
    _schedule();
  }

  FaAdViewportGeometry? _readGeometry({FaAdViewportMetrics? metrics}) {
    if (!mounted || !widget.active.value || !widget.scrollController.hasClients) {
      return null;
    }
    final target = _boundsKey.currentContext?.findRenderObject();
    if (target is! RenderBox || !target.attached || !target.hasSize) {
      return null;
    }
    final viewMetrics = metrics ??
        readFaAdViewportMetrics(widget.viewportKey, widget.scrollController);
    if (viewMetrics == null) return null;
    final bounds = target.localToGlobal(Offset.zero) & target.size;
    final view = viewMetrics.bounds;
    final padding = widget.geometryPadding;
    final intersection = bounds.intersect(view);
    final visible = bounds.width > 0 && bounds.height > 0 &&
        intersection.width >= 0 && intersection.height >= 0;
    final ratio = visible
        ? (intersection.width * intersection.height / (bounds.width * bounds.height))
            .clamp(0.0, 1.0).toDouble()
        : 0.0;
    return FaAdViewportGeometry(
      bounds: Rect.fromLTRB(
        bounds.left - padding.left, bounds.top - padding.top,
        bounds.right + padding.right, bounds.bottom + padding.bottom,
      ),
      viewport: view,
      atStart: viewMetrics.atStart,
      isIntersecting: visible,
      intersectionRatio: ratio,
    );
  }

  void _schedule() {
    if (widget.visibilityManagedExternally || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted || widget.visibilityManagedExternally) return;
      final geometry = _readGeometry();
      if (geometry == null) return;
      widget.onVisibility(geometry.isIntersecting, geometry.intersectionRatio);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    if (!widget.visibilityManagedExternally) {
      widget.scrollController.removeListener(_schedule);
      widget.active.removeListener(_schedule);
    }
    widget.onGeometryReader?.call(_geometryReader, false);
    widget.onVisibility(false, 0);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<SizeChangedLayoutNotification>(
        onNotification: (_) {
          widget.onLayoutChanged?.call();
          _schedule();
          return false;
        },
        child: SizeChangedLayoutNotifier(
          child: SizedBox(key: _boundsKey, child: widget.child),
        ),
      );
}
