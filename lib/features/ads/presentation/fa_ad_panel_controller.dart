import 'package:flutter/widgets.dart';

import 'package:fanotifier/core/logging/fa_ads_logging.dart';
import 'package:fanotifier/features/ads/domain/fa_ad_models.dart';
import 'package:fanotifier/features/ads/domain/fa_ads_repository.dart';
import 'package:fanotifier/features/ads/presentation/fa_ad_section_controller.dart';
import 'package:fanotifier/features/ads/presentation/fa_ad_viewport.dart';

class FaAdPanelController extends ChangeNotifier {
  FaAdPanelController({
    required this._repository,
    required Set<FaAdPlacement> placements,
  }) : placements = Set.unmodifiable(placements);

  final FaAdsRepository _repository;
  final Set<FaAdPlacement> placements;
  final ValueNotifier<bool> active = ValueNotifier(false);
  final Map<FaAdPlacement, FaAdGeometryReader> _geometry = {};
  final Map<FaAdSlotController, VoidCallback> _sizeListeners = {};
  FaAdSectionController? _section;
  static int _nextSection = 0;
  bool _scheduled = false;
  bool _disposed = false;

  FaAdSectionController? get section => _section;

  void synchronize({
    required FaAdPageMetadata? page,
    required double viewportWidth,
    required bool sfwEnabled,
    bool renew = false,
  }) {
    if (_disposed) return;
    if (page != null && page.sfwEnabled != sfwEnabled) {
      FaAdsLog.event(FaAdsLogCategory.config, 'panel_mode_mismatch_rejected',
          checks: {'modeMatchesPage': false, 'adsAllowed': false});
    }
    final layout = page?.sfwEnabled == sfwEnabled
        ? page?.layoutFor(viewportWidth, placements: placements)
        : null;
    if (page == null || layout == null) {
      clear();
      return;
    }
    final current = _section;
    if (current != null && _sameConfiguration(current, page, layout)) {
      if (renew) {
        refresh();
      } else {
        FaAdsLog.event(FaAdsLogCategory.config, 'panel_configuration_retained',
            section: current.sectionNumber,
            delivery: current.deliveryGeneration,
            checks: {'deliveryRetained': true, 'countingRequest': false});
      }
      return;
    }
    _releaseSection();
    final section = FaAdSectionController(
      sectionNumber: -(++_nextSection),
      page: page,
      layout: layout,
      repository: _repository,
    );
    _section = section;
    for (final slot in section.slots) {
      var width = slot.effectiveSize.width;
      var height = slot.effectiveSize.height;
      void sizeChanged() {
        if (_disposed || !identical(_section, section)) return;
        final size = slot.effectiveSize;
        if (size.width == width && size.height == height) return;
        width = size.width;
        height = size.height;
        notifyListeners();
        scheduleVisibility();
      }
      _sizeListeners[slot] = sizeChanged;
      slot.state.addListener(sizeChanged);
    }
    notifyListeners();
    scheduleVisibility();
  }

  bool _sameConfiguration(
    FaAdSectionController section, FaAdPageMetadata page, FaAdLayout layout,
  ) {
    if (section.page.documentUri != page.documentUri ||
        section.page.deliveryUri != page.deliveryUri ||
        section.page.sfwEnabled != page.sfwEnabled ||
        section.layout.slots.length != layout.slots.length ||
        section.layout.fetchOnlyZones.length != layout.fetchOnlyZones.length) {
      return false;
    }
    for (var index = 0; index < layout.slots.length; index++) {
      final before = section.layout.slots[index];
      final after = layout.slots[index];
      if (before.placement != after.placement || before.zoneId != after.zoneId ||
          before.size.width != after.size.width ||
          before.size.height != after.size.height) {
        return false;
      }
    }
    for (var index = 0; index < layout.fetchOnlyZones.length; index++) {
      if (section.layout.fetchOnlyZones[index] != layout.fetchOnlyZones[index]) {
        return false;
      }
    }
    return true;
  }

  void setActive(bool value) {
    if (_disposed || active.value == value) return;
    _section?.setActive(false);
    active.value = value;
    FaAdsLog.event(FaAdsLogCategory.lifecycle,
        value ? 'panel_visible' : 'panel_hidden');
    scheduleVisibility();
  }

  void refresh() {
    if (_disposed || _section == null) return;
    final section = _section!;
    section.setActive(false);
    section.refresh();
    FaAdsLog.event(FaAdsLogCategory.lifecycle, 'panel_refreshed',
        section: section.sectionNumber,
        delivery: section.deliveryGeneration,
        checks: {'freshGeometryBeforeActivation': true});
    scheduleVisibility();
  }

  void registerGeometry(
    FaAdSectionController section,
    FaAdPlacement placement,
    FaAdGeometryReader reader,
    bool attached,
  ) {
    if (_disposed || !identical(_section, section)) return;
    if (attached) {
      _geometry[placement] = reader;
    } else if (identical(_geometry[placement], reader)) {
      _geometry.remove(placement);
    }
    scheduleVisibility();
  }

  void scheduleVisibility() {
    if (_disposed || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (_disposed) return;
      final section = _section;
      if (section == null) return;
      var measured = false;
      for (final slot in section.slots) {
        final geometry = active.value
            ? _geometry[slot.definition.placement]?.call()
            : null;
        measured = measured || geometry != null;
        section.setSlotVisibility(slot.definition.placement,
            geometry?.isIntersecting ?? false,
            geometry?.intersectionRatio ?? 0);
      }
      section.setActive(active.value && measured);
      section.activateVisibleSlots();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _releaseSection() {
    for (final entry in _sizeListeners.entries) {
      entry.key.state.removeListener(entry.value);
    }
    _sizeListeners.clear();
    _geometry.clear();
    _section?.dispose();
    _section = null;
  }

  void clear() {
    if (_disposed || _section == null) return;
    _releaseSection();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _releaseSection();
    active.dispose();
    super.dispose();
  }
}
