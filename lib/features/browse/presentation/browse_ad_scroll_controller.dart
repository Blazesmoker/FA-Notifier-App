import 'package:flutter/widgets.dart';

import 'package:fanotifier/core/logging/fa_ads_logging.dart';
import 'package:fanotifier/features/ads/presentation/fa_ad_viewport.dart';

class BrowseAdScrollController extends ScrollController {
  BrowseAdScrollController() {
    addListener(_trackAnchorScroll);
  }

  _BrowseAdScrollAnchor? _resizeAnchor;
  int _anchorRevision = 0;

  void preserveResizeAnchor(FaAdGeometryReader reader) {
    if (_resizeAnchor != null || !hasClients || positions.length != 1 ||
        !position.hasPixels) {
      return;
    }
    final geometry = reader();
    if (geometry == null) return;
    _resizeAnchor = _BrowseAdScrollAnchor(
      reader, geometry.viewport,
      geometry.bounds.top - geometry.viewport.top, position.pixels,
    );
    final revision = ++_anchorRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (revision == _anchorRevision) clearResizeAnchor();
    });
  }

  void clearResizeAnchor() {
    _resizeAnchor = null;
    _anchorRevision++;
  }

  void _trackAnchorScroll() {
    final anchor = _resizeAnchor;
    if (anchor == null || !hasClients || positions.length != 1) return;
    final pixels = position.pixels;
    anchor.expectedTop -= pixels - anchor.previousPixels;
    anchor.previousPixels = pixels;
  }

  double _takeResizeCorrection(double pixels, double minimum, double maximum) {
    final anchor = _resizeAnchor;
    if (anchor == null) return 0.0;
    clearResizeAnchor();
    final geometry = anchor.reader();
    if (geometry == null || geometry.viewport != anchor.viewport ||
        pixels <= minimum + 0.5 || pixels > maximum + 0.5) {
      return 0.0;
    }
    final correction = geometry.bounds.top - geometry.viewport.top - anchor.expectedTop;
    if (!correction.isFinite || correction.abs() <= 0.5) return 0.0;
    final target = (pixels + correction).clamp(minimum, maximum).toDouble();
    final delta = target - pixels;
    if (delta.abs() <= 0.5) return 0.0;
    FaAdsLog.event(FaAdsLogCategory.perf, 'resize_scroll_anchor_corrected',
        counts: {'correctionPixels': delta},
        checks: {'layoutCorrection': true, 'gestureCancelled': false,
          'countingRequest': false});
    return delta;
  }

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics, ScrollContext context, ScrollPosition? oldPosition,
  ) => _BrowseAdScrollPosition(
        physics: physics, context: context, oldPosition: oldPosition,
        initialPixels: initialScrollOffset, keepScrollOffset: keepScrollOffset,
        debugLabel: debugLabel, takeResizeCorrection: _takeResizeCorrection,
      );

  @override
  void dispose() {
    clearResizeAnchor();
    removeListener(_trackAnchorScroll);
    super.dispose();
  }
}

class _BrowseAdScrollPosition extends ScrollPositionWithSingleContext {
  _BrowseAdScrollPosition({
    required super.physics,
    required super.context,
    required super.initialPixels,
    required super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
    required this.takeResizeCorrection,
  });

  final double Function(double pixels, double minimum, double maximum) takeResizeCorrection;

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    final correction = takeResizeCorrection(pixels, minScrollExtent, maxScrollExtent);
    if (correction != 0.0) {
      correctBy(correction);
      return false;
    }
    return super.applyContentDimensions(minScrollExtent, maxScrollExtent);
  }
}

class _BrowseAdScrollAnchor {
  _BrowseAdScrollAnchor(this.reader, this.viewport, this.expectedTop, this.previousPixels);

  final FaAdGeometryReader reader;
  final Rect viewport;
  double expectedTop;
  double previousPixels;
}
