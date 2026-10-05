import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:fanotifier/core/logging/fa_ads_logging.dart';
import 'package:fanotifier/features/ads/domain/fa_ad_models.dart';
import 'package:fanotifier/features/ads/domain/fa_ads_repository.dart';
import 'package:fanotifier/features/ads/presentation/fa_ad_section_controller.dart';
import 'package:fanotifier/features/ads/presentation/fa_ad_viewport.dart';
import 'package:fanotifier/features/browse/domain/browse_page_data.dart';
import 'package:fanotifier/features/browse/presentation/browse_ad_scroll_controller.dart';

enum BrowseAdRowKind { artwork, headerAd, footerAd, divider }

enum _BrowsePageQualification { content, shortPage, listTop }

class BrowseAdsController {
  BrowseAdsController(this._repository, this._scrollController);

  static const Duration _minimumPageStay = Duration(seconds: 2);
  static const double _geometryTolerance = 0.5;

  final FaAdsRepository _repository;
  final BrowseAdScrollController _scrollController;
  final Map<int, FaAdSectionController> _sections = {};
  final Map<int, BrowseGridSection> _pages = {};
  final Map<String, _BrowseAdRowProbe> _rows = {};
  final Set<int> _seen = {};
  final Set<int> _retainedPages = {};
  Timer? _stayTimer;
  _BrowsePageStay? _stay;
  Rect? _lastViewport;
  double? _layoutWidth;
  int? _firstPage;
  int? _visitPage;
  int? _visitFromPage;
  int? _confirmedPage;
  int? _programmaticScroll;
  int _nextProgrammaticScroll = 0;
  int _nextVisit = 0;
  int _scheduleRevision = 0;
  int _resumeRevision = 0;
  bool _active = false;
  bool _disposed = false;
  bool _scheduled = false;
  bool _resuming = false;
  bool _artworkReturn = false;
  bool _visitNeedsRefresh = false;
  _BrowseReturnAnchor? _returnAnchor;

  FaAdSectionController? section(int page) => _sections[page];

  void synchronize(List<BrowseGridSection> pages, double width) {
    if (_disposed) return;
    if (_layoutWidth != null && _layoutWidth != width) {
      _scrollController.clearResizeAnchor();
      _cancelStay('layout_changed');
    }
    _layoutWidth = width;
    _firstPage = pages.isEmpty ? null : pages.first.pageNumber;
    final retained = pages.map((page) => page.pageNumber).toSet();
    for (final id in _pages.keys.toList(growable: false)) {
      if (!retained.contains(id)) _forgetPage(id);
    }
    for (final page in pages) {
      final previousPage = _pages[page.pageNumber];
      if (previousPage != null && !identical(previousPage, page)) {
        _forgetPage(page.pageNumber);
      }
      _pages[page.pageNumber] = page;
      final metadata = page.ads;
      final layout = metadata?.layoutFor(width);
      final previous = _sections[page.pageNumber];
      if (metadata == null || layout == null) {
        if (previous != null && _stay?.page == page.pageNumber) {
          _cancelStay('layout_changed');
        }
        _sections.remove(page.pageNumber)?.dispose();
        continue;
      }
      if (previous != null && identical(previous.page, metadata) &&
          identical(previous.layout, layout)) {
        continue;
      }
      if (_stay?.page == page.pageNumber) _cancelStay('layout_changed');
      previous?.dispose();
      _sections[page.pageNumber] = FaAdSectionController(
        sectionNumber: page.pageNumber,
        page: metadata, layout: layout, repository: _repository,
        onSizeWillChange: (_) => _prepareAdResize(),
      )..setActive(_active && !_resuming);
    }
  }

  void _forgetPage(int page) {
    if (_returnAnchor?.page.pageNumber == page) _returnAnchor = null;
    if (_stay?.page == page) _cancelStay('content_changed');
    _sections.remove(page)?.dispose();
    _pages.remove(page);
    _rows.removeWhere((_, row) => row.page.pageNumber == page);
    _seen.remove(page);
    _retainedPages.remove(page);
    if (_confirmedPage == page) _confirmedPage = null;
    if (_visitPage == page) {
      _visitPage = null;
      _visitFromPage = null;
      _visitNeedsRefresh = false;
    }
  }

  void setActive(bool active) {
    if (_disposed || _active == active) return;
    _active = active;
    final revision = ++_resumeRevision;
    FaAdsLog.event(FaAdsLogCategory.lifecycle, active ? 'browse_visible' : 'browse_hidden');
    if (!active) {
      _scrollController.clearResizeAnchor();
      _cancelStay('browse_hidden');
      for (final section in _sections.values) {
        section.setActive(false);
      }
      return;
    }
    _resuming = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || !_active || revision != _resumeRevision) return;
      _resuming = false;
      _scheduleVisibility();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void artworkReturned() {
    _cancelStay('artwork_return');
    _artworkReturn = true;
    FaAdsLog.event(FaAdsLogCategory.lifecycle, 'artwork_return_refresh_pending',
        checks: {'onlyVisibleSections': true});
  }

  void adInteractionStarted(int page) {
    final pendingRenewal = _stay?.renew ?? false;
    _cancelStay('ad_tap');
    _retainedPages.add(page);
    if (_visitPage != null) _retainedPages.add(_visitPage!);
    _visitNeedsRefresh = false;
    FaAdsLog.event(FaAdsLogCategory.lifecycle, 'ad_tap_retained_visit',
        section: page,
        checks: {'pendingRenewalCancelled': pendingRenewal, 'deliveryRetained': true});
  }

  void adReturned() {
    _cancelStay('ad_return');
    _artworkReturn = false;
    if (_visitPage != null) _retainedPages.add(_visitPage!);
    _visitNeedsRefresh = false;
    FaAdsLog.event(FaAdsLogCategory.lifecycle, 'ad_return_retained',
        checks: {'deliveryRetained': true, 'repeatImpression': false});
  }

  int beginScrollToTop() => beginNavigationScroll(returning: false);

  void endScrollToTop(int token) => endNavigationScroll(token, returning: false);

  int beginNavigationScroll({required bool returning}) {
    final token = ++_nextProgrammaticScroll;
    if (_disposed) return token;
    final reason = returning ? 'scroll_to_return' : 'scroll_to_top';
    _cancelStay(reason);
    _programmaticScroll = token;
    _scrollController.clearResizeAnchor();
    FaAdsLog.event(FaAdsLogCategory.lifecycle, '${reason}_started',
        checks: {'automaticRenewalPaused': true});
    return token;
  }

  void endNavigationScroll(int token, {required bool returning}) {
    if (_disposed || _programmaticScroll != token) return;
    _programmaticScroll = null;
    FaAdsLog.event(FaAdsLogCategory.lifecycle,
        returning ? 'scroll_to_return_finished' : 'scroll_to_top_finished',
        checks: {'freshStayRequired': true});
    _scheduleVisibility();
  }

  void captureReturnPosition() {
    _returnAnchor = null;
    MapEntry<String, _BrowseAdRowProbe>? selected;
    FaAdViewportGeometry? selectedGeometry;
    for (final entry in _rows.entries) {
      final geometry = entry.value.reader();
      if (geometry == null) continue;
      final intersection = geometry.bounds.intersect(geometry.viewport);
      if (intersection.width <= 0 || intersection.height <= 0) continue;
      final artwork = entry.value.kind == BrowseAdRowKind.artwork;
      final selectedArtwork = selected?.value.kind == BrowseAdRowKind.artwork;
      if (selected == null || (artwork && !selectedArtwork) ||
          (artwork == selectedArtwork &&
              geometry.bounds.top < selectedGeometry!.bounds.top)) {
        selected = entry;
        selectedGeometry = geometry;
      }
    }
    if (selected == null || selectedGeometry == null) return;
    final row = selected.value;
    final width = selectedGeometry.viewport.width;
    _returnAnchor = _BrowseReturnAnchor(
      selected.key, row.page, row.kind, row.placement, width,
      selectedGeometry.bounds.top - selectedGeometry.viewport.top,
      _adHeightBefore(row.page.pageNumber, row.kind, row.placement, width),
    );
    FaAdsLog.event(FaAdsLogCategory.perf, 'scroll_return_anchor_saved',
        section: row.page.pageNumber,
        checks: {'artworkAnchor': row.kind == BrowseAdRowKind.artwork});
  }

  double resolveReturnOffset(double savedOffset) {
    final anchor = _returnAnchor;
    if (anchor == null || !_scrollController.hasClients ||
        !identical(_pages[anchor.page.pageNumber], anchor.page)) {
      return savedOffset;
    }
    final geometry = _rows[anchor.key]?.reader();
    if (geometry != null) {
      return _scrollController.position.pixels + geometry.bounds.top -
          geometry.viewport.top - anchor.viewportOffset;
    }
    final currentHeight = _adHeightBefore(
      anchor.page.pageNumber, anchor.kind, anchor.placement,
      _layoutWidth ?? anchor.width,
    );
    return savedOffset + currentHeight - anchor.adHeight;
  }

  double _adHeightBefore(
    int page, BrowseAdRowKind kind, FaAdPlacement? placement, double width,
  ) {
    var height = 0.0;
    final availableWidth = math.max(0.0, width - 16.0);
    for (final entry in _sections.entries) {
      if (entry.key > page) continue;
      final slots = entry.value.slots;
      final ordered = [
        ...slots.where((slot) => slot.definition.placement == FaAdPlacement.headerMiddle),
        ...slots.where((slot) => slot.definition.placement != FaAdPlacement.headerMiddle),
      ];
      for (final slot in ordered) {
        final currentPlacement = slot.definition.placement;
        if (entry.key == page) {
          if (currentPlacement == placement) break;
          if (kind == BrowseAdRowKind.artwork &&
              currentPlacement != FaAdPlacement.headerMiddle) {
            break;
          }
        }
        final size = slot.effectiveSize;
        height += size.height * math.min(size.width.toDouble(), availableWidth) /
            size.width;
      }
    }
    return height;
  }

  void viewportChanged() => _scheduleVisibility();

  void scrollChanged() {
    final stay = _stay;
    if (stay != null) stay.scrollUpdates++;
    _scheduleVisibility();
  }

  void layoutChanged() {
    if (_disposed) return;
    _cancelStay('layout_changed');
    _scheduleVisibility();
  }

  void _prepareAdResize() {
    if (_disposed) return;
    if (_active && !_resuming && _programmaticScroll == null) {
      _BrowseAdRowProbe? anchor;
      double? top;
      for (final row in _rows.values) {
        final geometry = row.reader();
        if (geometry == null) continue;
        final intersection = geometry.bounds.intersect(geometry.viewport);
        if (intersection.width <= 0 || intersection.height <= 0) continue;
        if (top == null || geometry.bounds.top < top) {
          anchor = row;
          top = geometry.bounds.top;
        }
      }
      if (anchor != null) _scrollController.preserveResizeAnchor(anchor.reader);
    }
    layoutChanged();
  }

  void registerViewportRow({
    required BrowseGridSection page,
    required String key,
    required BrowseAdRowKind kind,
    required int? artworkIndex,
    required FaAdPlacement? placement,
    required FaAdGeometryReader reader,
    required bool attached,
  }) {
    if (_disposed || !identical(_pages[page.pageNumber], page)) return;
    if (attached) {
      _rows[key] = _BrowseAdRowProbe(page, kind, artworkIndex, placement, reader);
    } else if (identical(_rows[key]?.reader, reader)) {
      _rows.remove(key);
    }
    _scheduleVisibility();
  }

  void _scheduleVisibility() {
    if (_scheduled || _disposed) return;
    _scheduled = true;
    final revision = _scheduleRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduleMicrotask(() {
        if (_disposed || revision != _scheduleRevision) return;
        _scheduled = false;
        _reconcileVisibility();
      });
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _reconcileVisibility() {
    if (_disposed || !_active || _resuming) return;
    final measured = <_BrowseMeasuredRow>[];
    for (final row in _rows.values) {
      final geometry = row.reader();
      if (geometry == null || geometry.bounds.isEmpty ||
          geometry.viewport.isEmpty || !geometry.bounds.width.isFinite ||
          !geometry.bounds.height.isFinite) {
        continue;
      }
      measured.add(_BrowseMeasuredRow(row, geometry));
      final placement = row.placement;
      if (placement != null) {
        _sections[row.page.pageNumber]?.setSlotVisibility(
          placement, geometry.isIntersecting, geometry.intersectionRatio,
        );
      }
    }
    final viewport = measured.isEmpty ? null : measured.first.geometry.viewport;
    if (viewport != _lastViewport) {
      _cancelStay('viewport_changed');
      _lastViewport = viewport;
    }
    final visible = measured.where((row) => row.visible)
        .map((row) => row.probe.page.pageNumber).toSet();
    final candidate = _selectContentPage(measured);
    if (_programmaticScroll == null && _artworkReturn && visible.isNotEmpty) {
      _cancelStay('artwork_return');
      _retainedPages.addAll(visible);
      for (final page in visible) {
        final section = _sections[page];
        section?.setActive(false);
        section?.refresh();
        FaAdsLog.event(FaAdsLogCategory.lifecycle, 'visible_section_refreshed',
            section: page, delivery: section?.deliveryGeneration);
      }
      _visitNeedsRefresh = false;
      _artworkReturn = false;
    }
    if (_programmaticScroll == null) {
      _updateVisit(candidate);
    }
    _seen.addAll(visible);
    for (final section in _sections.values) {
      section.setActive(true);
      section.activateVisibleSlots();
    }
  }

  _BrowseContentCandidate? _selectContentPage(List<_BrowseMeasuredRow> rows) {
    if (rows.isEmpty) return null;
    final viewport = rows.first.geometry.viewport;
    final artwork = <int, List<_BrowseMeasuredRow>>{};
    final visibleArtwork = <int, Rect>{};
    for (final row in rows) {
      if (row.probe.kind != BrowseAdRowKind.artwork) continue;
      final page = row.probe.page.pageNumber;
      artwork.putIfAbsent(page, () => []).add(row);
      if (row.visible) {
        final bounds = row.geometry.bounds.intersect(viewport);
        visibleArtwork[page] = visibleArtwork[page]?.expandToInclude(bounds) ?? bounds;
      }
    }
    int? focused;
    double distance = double.infinity;
    final preferred = _stay?.page ?? _confirmedPage;
    for (final entry in visibleArtwork.entries) {
      final bounds = entry.value;
      final center = viewport.center.dy;
      final nextDistance = center < bounds.top ? bounds.top - center
          : center > bounds.bottom ? center - bounds.bottom : 0.0;
      if (nextDistance < distance - _geometryTolerance ||
          ((nextDistance - distance).abs() <= _geometryTolerance &&
              (entry.key == preferred ||
                  (focused != preferred && (focused == null || entry.key < focused))))) {
        focused = entry.key;
        distance = nextDistance;
      }
    }
    final focusedPage = focused;
    if (focusedPage == null) return null;
    final pageRows = artwork[focusedPage]!
      ..sort((left, right) => left.probe.artworkIndex!.compareTo(right.probe.artworkIndex!));
    for (var index = 1; index < pageRows.length; index++) {
      if (pageRows[index].probe.artworkIndex != pageRows[index - 1].probe.artworkIndex! + 1 ||
          (pageRows[index].geometry.bounds.top - pageRows[index - 1].geometry.bounds.bottom)
              .abs() > _geometryTolerance) {
        return null;
      }
    }
    final top = pageRows.first.geometry.bounds.top;
    final bottom = pageRows.last.geometry.bounds.bottom;
    final footerVisible = rows.any((row) => row.probe.page.pageNumber == focusedPage &&
        row.probe.kind == BrowseAdRowKind.footerAd && row.visible);
    if (top <= viewport.top + _geometryTolerance &&
        bottom >= viewport.bottom - _geometryTolerance &&
        visibleArtwork.length == 1 && !footerVisible) {
      return _BrowseContentCandidate(focusedPage, _BrowsePageQualification.content);
    }
    final expectedRows = _pages[focusedPage]!.rows.length;
    final complete = expectedRows > 0 && pageRows.length == expectedRows &&
        pageRows.first.probe.artworkIndex == 0 &&
        pageRows.last.probe.artworkIndex == expectedRows - 1;
    if (complete && bottom - top <= viewport.height + _geometryTolerance &&
        top >= viewport.top - _geometryTolerance &&
        bottom <= viewport.bottom + _geometryTolerance) {
      return _BrowseContentCandidate(focusedPage, _BrowsePageQualification.shortPage);
    }
    if (focusedPage == _firstPage && pageRows.first.geometry.atStart &&
        pageRows.first.probe.artworkIndex == 0 &&
        bottom >= viewport.bottom - _geometryTolerance &&
        visibleArtwork.length == 1 && !footerVisible) {
      return _BrowseContentCandidate(focusedPage, _BrowsePageQualification.listTop);
    }
    return null;
  }

  void _updateVisit(_BrowseContentCandidate? candidate) {
    if (candidate == null) {
      _cancelStay('content_not_qualified');
      return;
    }
    if (_visitPage != candidate.page) {
      _cancelStay('page_changed');
      _visitFromPage = _visitPage;
      _visitNeedsRefresh = _visitPage != null && candidate.page < _visitPage! &&
          _seen.contains(candidate.page);
      _visitPage = candidate.page;
    }
    if (_confirmedPage == candidate.page) {
      _cancelStay('visit_already_confirmed');
      return;
    }
    final section = _sections[candidate.page];
    if (_stay != null && (!identical(_stay!.section, section) ||
        _stay!.generation != section?.deliveryGeneration)) {
      _cancelStay('delivery_changed');
    }
    final stay = _stay ??= _BrowsePageStay(
      page: candidate.page, qualification: candidate.qualification,
      visit: ++_nextVisit, section: section, generation: section?.deliveryGeneration,
      renew: _visitNeedsRefresh && !_retainedPages.contains(candidate.page),
    );
    stay.qualification = candidate.qualification;
    if (_stayTimer == null) {
      FaAdsLog.event(FaAdsLogCategory.lifecycle, 'page_stay_started',
          section: stay.page, delivery: stay.generation,
          counts: {'visit': stay.visit, 'requiredMs': _minimumPageStay.inMilliseconds,
            'fromPage': _visitFromPage ?? stay.page},
          checks: {...stay.qualificationChecks, 'refreshPending': stay.renew,
            'monotonicClock': true, 'idleRequired': false});
      _stayTimer = Timer(_minimumPageStay, () {
        if (!_disposed && identical(_stay, stay)) _scheduleVisibility();
      });
    }
    if (stay.clock.elapsed < _minimumPageStay) return;
    _stayTimer?.cancel();
    _stayTimer = null;
    _stay = null;
    stay.clock.stop();
    _confirmedPage = candidate.page;
    _visitNeedsRefresh = false;
    _retainedPages.clear();
    FaAdsLog.event(FaAdsLogCategory.lifecycle, 'page_stay_completed',
        section: stay.page, delivery: stay.generation,
        counts: {'visit': stay.visit, 'elapsedMs': stay.clock.elapsedMilliseconds,
          'scrollUpdates': stay.scrollUpdates},
        checks: {...stay.qualificationChecks, 'freshGeometryChecked': true,
          'refresh': stay.renew && section != null,
          'scrollActivity': stay.scrollUpdates > 0, 'idleRequired': false});
    if (stay.renew && section != null) {
      section.setActive(false);
      section.refresh();
      FaAdsLog.event(FaAdsLogCategory.lifecycle, 'back_scrolled_section_refreshed',
          section: stay.page, delivery: section.deliveryGeneration,
          counts: {'visit': stay.visit}, checks: stay.qualificationChecks);
    }
  }

  void _cancelStay(String reason) {
    final stay = _stay;
    _stayTimer?.cancel();
    _stayTimer = null;
    _stay = null;
    if (stay == null) return;
    stay.clock.stop();
    FaAdsLog.event(FaAdsLogCategory.lifecycle, 'page_stay_cancelled_$reason',
        section: stay.page, delivery: stay.generation,
        counts: {'visit': stay.visit, 'elapsedMs': stay.clock.elapsedMilliseconds,
          'scrollUpdates': stay.scrollUpdates},
        checks: {'elapsedDiscarded': true});
  }

  void clear() {
    _returnAnchor = null;
    _scrollController.clearResizeAnchor();
    _cancelStay('cleared');
    _scheduleRevision++;
    _scheduled = false;
    for (final section in _sections.values) {
      section.dispose();
    }
    _sections.clear();
    _pages.clear();
    _rows.clear();
    _seen.clear();
    _retainedPages.clear();
    _lastViewport = null;
    _layoutWidth = null;
    _firstPage = null;
    _visitPage = null;
    _visitFromPage = null;
    _confirmedPage = null;
    _programmaticScroll = null;
    _visitNeedsRefresh = false;
    _artworkReturn = false;
    FaAdsLog.event(FaAdsLogCategory.lifecycle, 'browse_deliveries_cleared');
  }

  void dispose() {
    _disposed = true;
    clear();
  }
}

class _BrowseReturnAnchor {
  const _BrowseReturnAnchor(
    this.key, this.page, this.kind, this.placement, this.width,
    this.viewportOffset, this.adHeight,
  );

  final String key;
  final BrowseGridSection page;
  final BrowseAdRowKind kind;
  final FaAdPlacement? placement;
  final double width;
  final double viewportOffset;
  final double adHeight;
}

class _BrowseAdRowProbe {
  const _BrowseAdRowProbe(this.page, this.kind, this.artworkIndex, this.placement, this.reader);

  final BrowseGridSection page;
  final BrowseAdRowKind kind;
  final int? artworkIndex;
  final FaAdPlacement? placement;
  final FaAdGeometryReader reader;
}

class _BrowseMeasuredRow {
  const _BrowseMeasuredRow(this.probe, this.geometry);

  final _BrowseAdRowProbe probe;
  final FaAdViewportGeometry geometry;

  bool get visible {
    final intersection = geometry.bounds.intersect(geometry.viewport);
    return intersection.width > 0 && intersection.height > 0;
  }
}

class _BrowseContentCandidate {
  const _BrowseContentCandidate(this.page, this.qualification);

  final int page;
  final _BrowsePageQualification qualification;
}

class _BrowsePageStay {
  _BrowsePageStay({
    required this.page,
    required this.qualification,
    required this.visit,
    required this.section,
    required this.generation,
    required this.renew,
  });

  final int page;
  _BrowsePageQualification qualification;
  final int visit;
  final FaAdSectionController? section;
  final int? generation;
  final bool renew;
  final Stopwatch clock = Stopwatch()..start();
  int scrollUpdates = 0;

  Map<String, bool> get qualificationChecks => {
    'content': qualification == _BrowsePageQualification.content,
    'shortPage': qualification == _BrowsePageQualification.shortPage,
    'listTop': qualification == _BrowsePageQualification.listTop,
  };
}
