import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:fanotifier/core/logging/fa_ads_logging.dart';
import 'package:fanotifier/features/ads/domain/fa_ad_models.dart';
import 'package:fanotifier/features/ads/domain/fa_ads_repository.dart';

enum FaAdSlotPhase { waiting, loading, ready, unavailable }

class FaAdSlotState {
  const FaAdSlotState({
    this.phase = FaAdSlotPhase.waiting,
    this.bytes,
    this.clickBusy = false,
  });

  final FaAdSlotPhase phase;
  final Uint8List? bytes;
  final bool clickBusy;
}

class FaAdSlotController {
  FaAdSlotController(this.definition) : effectiveSize = definition.size;

  final FaAdSlot definition;
  FaAdSize effectiveSize;
  FaAdSize? _pendingSize;
  bool hasResolvedSize = false;
  FaAdSize? _lastLoggedRenderSize;
  int? _lastLoggedLayoutGeneration;
  bool? _lastLoggedResolvedSize;
  final ValueNotifier<FaAdSlotState> state =
      ValueNotifier(const FaAdSlotState());
  final ValueNotifier<bool> inViewport = ValueNotifier(false);
  FaAdCreative? creative;
  bool get visible => inViewport.value;
  set visible(bool value) => inViewport.value = value;
  bool activated = false;
  bool committed = false;
  bool imageDecoded = false;

  void reset() {
    creative = null;
    _pendingSize = null;
    activated = visible;
    committed = false;
    imageDecoded = false;
    state.value = const FaAdSlotState();
  }

  void dispose() {
    state.dispose();
    inViewport.dispose();
  }
}

class FaAdSectionController {
  FaAdSectionController({
    required this.sectionNumber,
    required this.page,
    required this.layout,
    required this._repository,
    this.onSizeWillChange,
  }) {
    slots = [for (final slot in layout.slots) FaAdSlotController(slot)];
    FaAdsLog.event(FaAdsLogCategory.config, 'section_created',
        section: sectionNumber,
        counts: {'slots': slots.length, 'zones': layout.zones.length},
        checks: {'modeFromPage': true, 'subscriptionExemption': false});
  }

  final int sectionNumber;
  final FaAdPageMetadata page;
  final FaAdLayout layout;
  final void Function(FaAdPlacement placement)? onSizeWillChange;
  final FaAdsRepository _repository;
  late final List<FaAdSlotController> slots;
  FaAdCancellation _cancellation = FaAdCancellation();
  FaAdDelivery? _delivery;
  bool _active = false;
  bool _loading = false;
  bool _failed = false;
  bool _disposed = false;
  bool _clickBusy = false;
  int _generation = 1;

  int get deliveryGeneration => _generation;

  bool get _canStart => _active && !_disposed;

  void setActive(bool active) {
    if (_disposed || _active == active) return;
    _active = active;
    if (active) {
      for (final slot in slots) {
        final size = slot._pendingSize;
        if (size == null) continue;
        _applySize(slot, size);
        final state = slot.state.value;
        slot.state.value = FaAdSlotState(
          phase: state.phase, bytes: state.bytes, clickBusy: state.clickBusy,
        );
      }
      _processActivated();
    }
  }

  bool setSlotVisibility(FaAdPlacement placement, bool visible, double ratio) {
    if (_disposed) return false;
    final slot = slots.firstWhere((slot) => slot.definition.placement == placement);
    var changed = slot.visible != visible;
    if (changed) {
      FaAdsLog.event(FaAdsLogCategory.visibility, visible ? 'slot_entered' : 'slot_left',
          section: sectionNumber, delivery: _generation, slot: placement.name,
          counts: {'visiblePermille': (ratio * 1000).round()},
          checks: {'screenActive': _active});
    }
    slot.visible = visible;
    if (visible && _active && !slot.activated) {
      slot.activated = true;
      changed = true;
      FaAdsLog.event(FaAdsLogCategory.slot, 'activation_latched',
          section: sectionNumber, delivery: _generation, slot: placement.name,
          checks: {'geometricIntersection': true, 'durationGate': false});
    }
    return changed;
  }

  void activateVisibleSlots() {
    if (!_active || _disposed) return;
    for (final slot in slots) {
      if (slot.visible) slot.activated = true;
    }
    _processActivated();
  }

  void refresh() {
    if (_disposed) return;
    _cancellation.cancel();
    _cancellation = FaAdCancellation();
    _generation++;
    _delivery = null;
    _loading = false;
    _failed = false;
    _clickBusy = false;
    for (final slot in slots) {
      slot.reset();
      FaAdsLog.event(FaAdsLogCategory.slot, 'placeholder_size_retained',
          section: sectionNumber, delivery: _generation,
          slot: slot.definition.placement.name,
          counts: {'width': slot.effectiveSize.width, 'height': slot.effectiveSize.height},
          checks: {'fromPreviousCreative': slot.hasResolvedSize});
    }
    FaAdsLog.event(FaAdsLogCategory.lifecycle, 'section_delivery_invalidated',
        section: sectionNumber, delivery: _generation,
        checks: {'artworkRetained': true, 'scrollRetained': true});
    _processActivated();
  }

  void _processActivated() {
    if (!_canStart || _failed || !slots.any((slot) => slot.activated)) return;
    final delivery = _delivery;
    if (delivery == null) {
      if (!_loading) unawaited(_fetchDelivery());
      return;
    }
    for (final slot in slots) {
      if (!slot.activated || slot.committed) continue;
      final creative = delivery.creatives[slot.definition.zoneId];
      if (creative == null) {
        slot.committed = true;
        slot.state.value = const FaAdSlotState(phase: FaAdSlotPhase.unavailable);
        FaAdsLog.event(FaAdsLogCategory.slot, 'unfilled',
            section: sectionNumber, delivery: _generation,
            slot: slot.definition.placement.name, checks: {'beaconSent': false});
      } else {
        _commit(slot, creative);
      }
    }
  }

  Future<void> _fetchDelivery() async {
    _loading = true;
    final generation = _generation;
    final cancellation = _cancellation;
    FaAdsLog.event(FaAdsLogCategory.delivery, 'batch_requested',
        section: sectionNumber, delivery: generation,
        counts: {'zones': layout.zones.length}, checks: {'screenActive': _active});
    try {
      final delivery = await FaAdsLog.scoped(
        () => _repository.fetchDelivery(
          page: page, layout: layout, cancellation: cancellation,
          canStart: () => _canStart && generation == _generation,
        ),
        section: sectionNumber, delivery: generation,
      );
      if (_disposed || generation != _generation) return;
      _delivery = delivery;
      _loading = false;
      _processActivated();
    } catch (error) {
      if (_disposed || generation != _generation) return;
      _loading = false;
      if (error is FaAdFailure && error.reason == FaAdFailureReason.cancelled) {
        FaAdsLog.event(FaAdsLogCategory.delivery, 'batch_start_cancelled',
            section: sectionNumber, delivery: generation);
        if (_canStart) _processActivated();
        return;
      }
      _failed = true;
      for (final slot in slots) {
        slot.state.value = const FaAdSlotState(phase: FaAdSlotPhase.unavailable);
      }
      FaAdsLog.event(FaAdsLogCategory.delivery, 'batch_unavailable',
          section: sectionNumber, delivery: generation, checks: {'automaticRetry': false});
    }
  }

  void _commit(FaAdSlotController slot, FaAdCreative creative) {
    slot.committed = true;
    slot.creative = creative;
    final declaredSize = creative.declaredSize;
    if (declaredSize != null) _resolveSize(slot, creative, declaredSize);
    slot.state.value = const FaAdSlotState(phase: FaAdSlotPhase.loading);
    final generation = _generation;
    final cancellation = _cancellation;
    FaAdsLog.event(FaAdsLogCategory.impression, 'markup_committed',
        section: sectionNumber, delivery: generation,
        slot: slot.definition.placement.name,
        counts: {'zone': slot.definition.zoneId},
        checks: {'firstCommit': true, 'activationLatched': slot.activated,
          'screenActive': _active, 'waitForImageDecode': false});
    unawaited(_loadImage(slot, creative, generation, cancellation));
    unawaited(_sendImpression(slot, creative, generation, cancellation));
  }

  Future<void> _loadImage(
    FaAdSlotController slot, FaAdCreative creative,
    int generation, FaAdCancellation cancellation,
  ) async {
    try {
      final image = await FaAdsLog.scoped(
        () => _repository.fetchImage(
          creative: creative, page: page, cancellation: cancellation,
        ),
        section: sectionNumber, delivery: generation, slot: slot.definition.placement.name,
      );
      if (_disposed || generation != _generation) return;
      if (creative.declaredSize == null) {
        final intrinsicSize = image.intrinsicSize;
        if (intrinsicSize == null) {
          throw const FaAdFailure(FaAdFailureReason.invalidResponse);
        }
        _resolveSize(slot, creative, creative.resolveSize(intrinsicSize),
            intrinsicSize: intrinsicSize);
      }
      slot.state.value = FaAdSlotState(phase: FaAdSlotPhase.ready, bytes: image.bytes);
      FaAdsLog.event(FaAdsLogCategory.slot, 'image_bytes_ready',
          section: sectionNumber, delivery: generation, slot: slot.definition.placement.name);
    } catch (_) {
      if (_disposed || generation != _generation) return;
      slot.state.value = const FaAdSlotState(phase: FaAdSlotPhase.unavailable);
      FaAdsLog.event(FaAdsLogCategory.slot, 'image_unavailable',
          section: sectionNumber, delivery: generation, slot: slot.definition.placement.name);
    }
  }

  void _resolveSize(
    FaAdSlotController slot, FaAdCreative creative, FaAdSize size, {
    FaAdSize? intrinsicSize,
  }) {
    final previous = slot.effectiveSize;
    final changed = previous.width != size.width || previous.height != size.height;
    slot.hasResolvedSize = true;
    FaAdsLog.event(FaAdsLogCategory.config, 'creative_size_resolved',
        section: sectionNumber, delivery: _generation, slot: slot.definition.placement.name,
        counts: {'configuredWidth': slot.definition.size.width,
          'configuredHeight': slot.definition.size.height,
          'declaredWidth': creative.declaredWidth ?? 0,
          'declaredHeight': creative.declaredHeight ?? 0,
          if (intrinsicSize != null) 'intrinsicWidth': intrinsicSize.width,
          if (intrinsicSize != null) 'intrinsicHeight': intrinsicSize.height,
          'effectiveWidth': size.width, 'effectiveHeight': size.height},
        checks: {'fromDelivery': creative.declaredSize != null,
          'fromIntrinsic': creative.declaredSize == null,
          'singleDimensionDerived': (creative.declaredWidth == null) !=
              (creative.declaredHeight == null),
          'changed': changed, 'countingRequest': false});
    if (!changed) {
      slot._pendingSize = null;
      return;
    }
    if (!_active) {
      slot._pendingSize = size;
      FaAdsLog.event(FaAdsLogCategory.slot, 'slot_size_deferred',
          section: sectionNumber, delivery: _generation, slot: slot.definition.placement.name,
          counts: {'width': size.width, 'height': size.height},
          checks: {'screenActive': false, 'deliveryRetained': true,
            'hiddenRowSizeRetained': true});
      return;
    }
    _applySize(slot, size);
  }

  void _applySize(FaAdSlotController slot, FaAdSize size) {
    final previous = slot.effectiveSize;
    onSizeWillChange?.call(slot.definition.placement);
    slot.effectiveSize = size;
    slot._pendingSize = null;
    FaAdsLog.event(FaAdsLogCategory.slot, 'slot_size_changed',
        section: sectionNumber, delivery: _generation, slot: slot.definition.placement.name,
        counts: {'previousWidth': previous.width, 'previousHeight': previous.height,
          'width': size.width, 'height': size.height},
        checks: {'deliveryRetained': true, 'extraImpression': false});
  }

  void reportLayout(
    FaAdSlotController slot, double width, double height, double availableWidth,
  ) {
    if (!kDebugMode || _disposed) return;
    final previous = slot._lastLoggedRenderSize;
    if (slot._lastLoggedLayoutGeneration == _generation &&
        slot._lastLoggedResolvedSize == slot.hasResolvedSize &&
        previous?.width == width && previous?.height == height) {
      return;
    }
    slot._lastLoggedRenderSize = FaAdSize(width, height);
    slot._lastLoggedLayoutGeneration = _generation;
    slot._lastLoggedResolvedSize = slot.hasResolvedSize;
    FaAdsLog.event(FaAdsLogCategory.slot, 'banner_layout',
        section: sectionNumber, delivery: _generation, slot: slot.definition.placement.name,
        counts: {'effectiveWidth': slot.effectiveSize.width,
          'effectiveHeight': slot.effectiveSize.height,
          'renderedWidth': width, 'renderedHeight': height,
          'availableWidth': availableWidth,
          'scalePermille': (width / slot.effectiveSize.width * 1000).round()},
        checks: {'scaledDown': width < slot.effectiveSize.width,
          'hasKnownCreativeSize': slot.hasResolvedSize, 'countingRequest': false});
  }

  Future<void> _sendImpression(
    FaAdSlotController slot, FaAdCreative creative,
    int generation, FaAdCancellation cancellation,
  ) async {
    try {
      await FaAdsLog.scoped(
        () => _repository.registerImpression(
          creative: creative, page: page, cancellation: cancellation,
          canStart: () => _canStart && generation == _generation,
        ),
        section: sectionNumber, delivery: generation, slot: slot.definition.placement.name,
      );
      if (_disposed || generation != _generation) return;
      FaAdsLog.event(FaAdsLogCategory.impression, 'http_acknowledged',
          section: sectionNumber, delivery: generation, slot: slot.definition.placement.name,
          checks: {'serverCreditVerified': false});
    } catch (error) {
      if (_disposed || generation != _generation) return;
      FaAdsLog.event(FaAdsLogCategory.impression, 'not_confirmed',
          section: sectionNumber, delivery: generation, slot: slot.definition.placement.name,
          checks: {'cancelled': error is FaAdFailure &&
            error.reason == FaAdFailureReason.cancelled, 'willRetry': false});
    }
  }

  void imageDecoded(FaAdSlotController slot, Uint8List bytes) {
    if (_disposed || slot.imageDecoded || !slot.committed ||
        !identical(slot.state.value.bytes, bytes)) {
      return;
    }
    slot.imageDecoded = true;
    FaAdsLog.event(FaAdsLogCategory.slot, 'image_decoded',
        section: sectionNumber, delivery: _generation, slot: slot.definition.placement.name);
  }

  void imageDecodeFailed(FaAdSlotController slot, Uint8List bytes) {
    if (_disposed || slot.state.value.phase == FaAdSlotPhase.unavailable ||
        !identical(slot.state.value.bytes, bytes)) {
      return;
    }
    slot.imageDecoded = false;
    slot.state.value = const FaAdSlotState(phase: FaAdSlotPhase.unavailable);
    FaAdsLog.event(FaAdsLogCategory.slot, 'image_decode_failed',
        section: sectionNumber, delivery: _generation, slot: slot.definition.placement.name);
  }

  Future<Uri?> click(FaAdSlotController slot) async {
    final creative = slot.creative;
    if (!_canStart || _clickBusy || !slot.imageDecoded || creative == null) {
      FaAdsLog.event(FaAdsLogCategory.click, 'tap_ignored', section: sectionNumber,
          delivery: _generation, slot: slot.definition.placement.name,
          checks: {'busy': _clickBusy, 'screenActive': _active});
      return null;
    }
    _clickBusy = true;
    final generation = _generation;
    final bytes = slot.state.value.bytes;
    slot.state.value = FaAdSlotState(
      phase: FaAdSlotPhase.ready, bytes: bytes, clickBusy: true,
    );
    FaAdsLog.event(FaAdsLogCategory.click, 'real_tap',
        section: sectionNumber, delivery: generation, slot: slot.definition.placement.name,
        checks: {'signedUrlUnchanged': true, 'destinationPrefetched': false});
    try {
      final destination = await FaAdsLog.scoped(
        () => _repository.resolveClick(
          creative: creative, page: page, cancellation: _cancellation,
          canStart: () => _canStart && generation == _generation,
        ),
        section: sectionNumber, delivery: generation, slot: slot.definition.placement.name,
      );
      if (_disposed || generation != _generation || !_active) return null;
      return destination;
    } catch (_) {
      FaAdsLog.event(FaAdsLogCategory.click, 'destination_unconfirmed',
          section: sectionNumber, delivery: generation, slot: slot.definition.placement.name,
          checks: {'automaticRetry': false});
      return null;
    } finally {
      if (!_disposed && generation == _generation) {
        _clickBusy = false;
        if (slot.state.value.phase == FaAdSlotPhase.ready) {
          slot.state.value = FaAdSlotState(phase: FaAdSlotPhase.ready, bytes: bytes);
        }
      }
    }
  }

  void dispose() {
    _disposed = true;
    _cancellation.cancel();
    for (final slot in slots) {
      slot.dispose();
    }
  }
}
