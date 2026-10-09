import 'dart:typed_data';

enum FaAdPlacement {
  headerMiddle('header_middle'),
  footerLeft('footer_left'),
  footerRight('footer_right'),
  footerRightTop('footer_right_top'),
  footerRightBottom('footer_right_bottom');

  const FaAdPlacement(this.websiteId);

  final String websiteId;
}

class FaAdSize {
  const FaAdSize(this.width, this.height);

  final num width;
  final num height;
}

class FaAdSlot {
  const FaAdSlot({
    required this.placement,
    required this.zoneId,
    required this.size,
  });

  final FaAdPlacement placement;
  final int zoneId;
  final FaAdSize size;
}

class FaAdLayout {
  const FaAdLayout({
    required this.minimumWidth,
    required this.maximumWidth,
    required this.slots,
    required this.fetchOnlyZones,
  });

  final double minimumWidth;
  final double maximumWidth;
  final List<FaAdSlot> slots;
  final List<int> fetchOnlyZones;

  bool fits(double width) => width >= minimumWidth && width <= maximumWidth;

  List<int> get zones => {
        for (final slot in slots) slot.zoneId,
        ...fetchOnlyZones,
      }.toList(growable: false);
}

class FaAdPageContext {
  const FaAdPageContext({
    required this.documentUri,
    required this.sfwEnabled,
  });

  final Uri documentUri;
  final bool sfwEnabled;
}

class FaAdPageMetadata extends FaAdPageContext {
  const FaAdPageMetadata({
    required super.documentUri,
    required this.deliveryUri,
    required super.sfwEnabled,
    required this.layouts,
  });

  final Uri deliveryUri;
  final List<FaAdLayout> layouts;

  FaAdLayout? layoutFor(double width, {Set<FaAdPlacement>? placements}) {
    for (final layout in layouts) {
      if (!layout.fits(width)) continue;
      if (placements == null) return layout;
      final slots = layout.slots
          .where((slot) => placements.contains(slot.placement))
          .toList(growable: false);
      if (slots.isEmpty) return null;
      return FaAdLayout(
        minimumWidth: layout.minimumWidth,
        maximumWidth: layout.maximumWidth,
        slots: List.unmodifiable(slots),
        fetchOnlyZones: layout.fetchOnlyZones,
      );
    }
    return null;
  }
}

class FaAdCreative {
  const FaAdCreative({
    required this.imageUri,
    required this.clickUri,
    required this.impressionUri,
    this.declaredWidth,
    this.declaredHeight,
  });

  final Uri imageUri;
  final Uri clickUri;
  final Uri impressionUri;
  final int? declaredWidth;
  final int? declaredHeight;

  FaAdSize? get declaredSize {
    final width = declaredWidth;
    final height = declaredHeight;
    return width == null || height == null ? null : FaAdSize(width, height);
  }

  FaAdSize resolveSize(FaAdSize intrinsicSize) {
    final declared = declaredSize;
    if (declared != null) return declared;
    final width = declaredWidth;
    final height = declaredHeight;
    if (width != null) {
      return FaAdSize(width, intrinsicSize.height * width / intrinsicSize.width);
    }
    if (height != null) {
      return FaAdSize(intrinsicSize.width * height / intrinsicSize.height, height);
    }
    return intrinsicSize;
  }
}

class FaAdImage {
  const FaAdImage({required this.bytes, this.intrinsicSize});

  final Uint8List bytes;
  final FaAdSize? intrinsicSize;
}

class FaAdDelivery {
  const FaAdDelivery(this.creatives);

  final Map<int, FaAdCreative> creatives;
}

enum FaAdFailureReason { cancelled, network, http, invalidResponse, unavailable }

class FaAdFailure implements Exception {
  const FaAdFailure(this.reason);

  final FaAdFailureReason reason;

  @override
  String toString() => 'Ad request ${reason.name}';
}

class FaAdCancellation {
  bool _cancelled = false;
  final Set<void Function()> _listeners = {};

  bool get isCancelled => _cancelled;

  void Function() onCancel(void Function() listener) {
    if (_cancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
    return () => _listeners.remove(listener);
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in _listeners.toList(growable: false)) {
      listener();
    }
    _listeners.clear();
  }
}
