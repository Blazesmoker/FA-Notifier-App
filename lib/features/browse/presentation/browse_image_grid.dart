import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:fanotifier/app/navigation/app_navigation.dart';
import 'package:fanotifier/core/logging/fa_ads_logging.dart';
import 'package:fanotifier/features/ads/domain/fa_ad_models.dart';
import 'package:fanotifier/features/ads/domain/fa_ads_repository.dart';
import 'package:fanotifier/features/ads/presentation/fa_ad_banner.dart';
import 'package:fanotifier/features/ads/presentation/fa_ad_section_controller.dart';
import 'package:fanotifier/features/ads/presentation/fa_ad_viewport.dart';
import 'package:fanotifier/features/browse/domain/browse_page_data.dart';
import 'package:fanotifier/features/browse/presentation/browse_ads_controller.dart';
import 'package:fanotifier/shared/navigation/fa_link_handler.dart';
import 'package:fanotifier/shared/widgets/fa_network_image.dart';
import 'package:fanotifier/shared/widgets/scroll_return_controller.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:fanotifier/features/browse/domain/browse_repository.dart';
import 'package:fanotifier/features/browse/presentation/browse_image_grid_controller.dart';
import 'package:fanotifier/features/submissions/presentation/submission_favorite_state_controller.dart';
import 'package:fanotifier/shared/fa/fa_system_message_parser.dart';
import 'package:fanotifier/shared/widgets/pulsating_loading_indicator.dart';
import 'package:fanotifier/shared/widgets/heart_animation.dart';
import 'package:fanotifier/shared/widgets/fa_thumbnail_display.dart';
import 'package:fanotifier/shared/widgets/fa_unavailable_screen.dart';
import 'package:fanotifier/features/auth/presentation/cloudflare_check_screen.dart';
import 'package:fanotifier/features/submissions/presentation/submission_details_screen.dart';

import '../../auth/domain/cloudflare_check_result.dart';

class BrowseImageGrid extends StatefulWidget {
  final Map<String, String> selectedFilters;
  final bool sfwEnabled;
  final bool isActive;
  final ScrollReturnActionPort? scrollActionPort;

  const BrowseImageGrid({
    required this.selectedFilters,
    required this.sfwEnabled,
    required this.isActive,
    this.scrollActionPort,
    super.key,
  });

  @override
  BrowseImageGridState createState() => BrowseImageGridState();
}

class BrowseImageGridState extends State<BrowseImageGrid>
    with RouteAware, WidgetsBindingObserver {
  late final BrowseImageGridController _controller;
  late final BrowseAdsController _ads;
  late final ScrollReturnController _scrollReturn;
  final GlobalKey _viewportKey = GlobalKey();
  final ValueNotifier<bool> _adsActive = ValueNotifier(false);
  List<_BrowseGridRow> _cachedGridRows = const [];
  Map<String, int> _rowIndexByKey = const {};
  int _cachedContentRevision = -1;
  int _cachedAdsRevision = -1;
  ModalRoute<dynamic>? _route;
  bool _routeVisible = true;
  bool _appResumed = true;
  bool _artworkExcursion = false;
  bool _adExcursion = false;
  bool _adTapPending = false;
  bool _adHandoff = false;
  bool _loggedOut = false;

  int get currentPage => _controller.currentPage;
  bool get isLoading => _controller.isLoading;
  bool get hasMore => _controller.hasMore;
  bool get _isError => _controller.isError;
  String? get _errorMessage => _controller.errorMessage;
  List<Map<String, dynamic>> get images => _controller.images;
  List<List<Map<String, dynamic>>> get imageRows => _controller.imageRows;
  List<Map<String, dynamic>> get normalImagesQueue =>
      _controller.normalImagesQueue;
  ScrollController get _scrollController => _controller.scrollController;

  @override
  void initState() {
    super.initState();
    _controller = BrowseImageGridController(
      selectedFilters: widget.selectedFilters,
      onCloudflareChallenge: (initialUrl) =>
          _showCloudflareDialog(initialUrl: initialUrl),
      repository: context.read<BrowseRepository>(),
      sfwEnabled: widget.sfwEnabled,
    );
    _ads = BrowseAdsController(
      context.read<FaAdsRepository>(), _controller.scrollController, _viewportKey,
    );
    _scrollReturn = ScrollReturnController(
      scrollController: _controller.scrollController,
      onSavePosition: _ads.captureReturnPosition,
      resolveReturnOffset: _ads.resolveReturnOffset,
    );
    widget.scrollActionPort?.bind(_scrollFromNavigation, _scrollReturn.cancelMovement);
    _appResumed = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_handleAdScroll);
    _controller.addListener(_handleControllerChanged);
    _controller.initialize();
    _updateAdActivity();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _route) {
      if (_route != null) routeObserver.unsubscribe(this);
      _route = route;
      if (route != null) {
        routeObserver.subscribe(this, route);
        _routeVisible = route.isCurrent;
      }
    }
    _updateAdActivity();
  }

  @override
  void didPushNext() {
    _routeVisible = false;
    _updateAdActivity();
  }

  @override
  void didPopNext() {
    _routeVisible = true;
    _adHandoff = false;
    if (_adExcursion) {
      _ads.adReturned();
    } else if (_artworkExcursion) {
      _ads.artworkReturned();
    }
    _adExcursion = false;
    _artworkExcursion = false;
    _updateAdActivity();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appResumed = state == AppLifecycleState.resumed;
    if (_appResumed && _adHandoff && _routeVisible) {
      _adHandoff = false;
      _adExcursion = false;
      _ads.adReturned();
    }
    _updateAdActivity();
  }

  void _updateAdActivity() {
    final active = !_loggedOut && widget.isActive && _routeVisible &&
        _appResumed && !_adHandoff;
    if (!active) _scrollReturn.cancelMovement();
    _ads.setActive(active);
    _adsActive.value = active;
  }

  void _handleAdScroll() {
    if (_scrollController.hasClients) {
      _ads.scrollChanged();
    }
  }

  Future<void> stopAdsForLogout() async {
    _scrollReturn.reset();
    _loggedOut = true;
    _controller.cancelPendingRequests();
    _updateAdActivity();
    _ads.clear();
    await context.read<FaAdsRepository>().resetSession();
  }

  void _handleControllerChanged() {
    _scrollReturn.updateContent(_controller.sections);
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant BrowseImageGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollActionPort != widget.scrollActionPort) {
      oldWidget.scrollActionPort?.unbind(_scrollFromNavigation);
      widget.scrollActionPort?.bind(_scrollFromNavigation, _scrollReturn.cancelMovement);
    }
    if (!widget.isActive) _scrollReturn.cancelMovement();
    if (oldWidget.selectedFilters != widget.selectedFilters ||
        oldWidget.sfwEnabled != widget.sfwEnabled) {
      _refreshImages();
    }
    _updateAdActivity();
  }

  @override
  void dispose() {
    widget.scrollActionPort?.unbind(_scrollFromNavigation);
    _scrollReturn.dispose();
    routeObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_handleAdScroll);
    _ads.dispose();
    _adsActive.dispose();
    _controller.removeListener(_handleControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  Future<void> scrollToTop({bool animate = true}) async {
    final token = _ads.beginScrollToTop();
    try {
      await _controller.scrollToTop(animate: animate);
    } finally {
      _ads.endScrollToTop(token);
    }
  }

  Future<void> _scrollFromNavigation(
    ValueChanged<ScrollReturnDirection> onStarted,
  ) async {
    if (!_adsActive.value) return;
    int? token;
    var returning = false;
    try {
      await _scrollReturn.perform(
        animate: !MediaQuery.disableAnimationsOf(context),
        onStarted: (direction) {
          returning = direction == ScrollReturnDirection.down;
          _controller.isNavbarScrolling = true;
          token = _ads.beginNavigationScroll(returning: returning);
          onStarted(direction);
        },
      );
    } finally {
      if (token != null) {
        _controller.isNavbarScrolling = false;
        _ads.endNavigationScroll(token!, returning: returning);
      }
    }
  }

  Future<void> _refreshImages() async {
    _scrollReturn.reset();
    _ads.clear();
    await _controller.refresh(widget.selectedFilters, sfwEnabled: widget.sfwEnabled);
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    _scrollReturn.handleScrollNotification(notification);
    return _controller.handleScrollNotification(notification);
  }

  Future<CloudflareCheckResult?> _showCloudflareDialog({
    String? initialUrl,
  }) async {
    if (!mounted) return null;
    return showDialog<CloudflareCheckResult>(
      context: context,
      barrierDismissible: false,
      useSafeArea: false,
      builder: (_) => CloudflareCheckScreen(
        initialUrl: initialUrl ?? 'https://www.furaffinity.net/',
        returnPageHtml: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    FaAdsLog.event(FaAdsLogCategory.perf, 'browse_grid_build',
        counts: {'artworkRows': imageRows.length, 'sections': _controller.sections.length});
    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = screenHeight * 0.4;
    final errorMessage = _errorMessage;
    _ads.synchronize(
      _controller.sections, MediaQuery.sizeOf(context).width,
      contentRevision: _controller.sectionsRevision,
    );
    final rows = _gridRows();

    if (!isLoading &&
        errorMessage != null &&
        isFaMaintenanceOrUnavailableText(errorMessage)) {
      return FaUnavailableScreen(
        message: errorMessage,
        onRefresh: _refreshImages,
      );
    }

    return RefreshIndicator(
      color: const Color(0xFFE09321),
      backgroundColor: Colors.black,
      onRefresh: _refreshImages,
      child: NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: imageRows.isEmpty
              ? ListView(
                  key: _viewportKey,
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(height: screenHeight * 0.25),
                    if (isLoading)
                      const Center(
                        child: PulsatingLoadingIndicator(
                          size: 88.0,
                          assetPath: 'assets/icons/fathemed.png',
                        ),
                      )
                    else
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: Text(
                            _isError
                                ? 'Network error. Pull to retry.'
                                : 'No results. Pull to refresh.',
                          ),
                        ),
                      ),
                    if (!isLoading && _errorMessage != null)
                      const SizedBox(height: 8),
                    if (!isLoading && _errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                  ],
                )
              : ListView.builder(
                  key: _viewportKey,
                  physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics()),
                  controller: _scrollController,
                  scrollCacheExtent:
                      ScrollCacheExtent.pixels(screenHeight * 1.5),
                  itemCount: rows.length + (isLoading ? 1 : 0),
                  findChildIndexCallback: (key) {
                    if (key is! ValueKey<String>) return null;
                    return _rowIndexByKey[key.value];
                  },
                  itemBuilder: (context, index) {
                    if (index == rows.length) {
                      return const Padding(
                        padding: EdgeInsets.fromLTRB(24.0, 16.0, 24.0, 16.0),
                        child: Center(
                          child: PulsatingLoadingIndicator(
                            size: 58.0,
                            assetPath: 'assets/icons/fathemed.png',
                          ),
                        ),
                      );
                    }

                    final row = rows[index];
                    if (row.kind == BrowseAdRowKind.divider) {
                      return Padding(
                        key: ValueKey(row.key),
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: const Divider(
                          height: 4.0,
                          thickness: 4.0,
                          indent: 0.0,
                          endIndent: 0.0,
                          color: Color(0xFF111111),
                        ),
                      );
                    }
                    final slot = row.slot;
                    final section = row.section;
                    final rowPadding = EdgeInsets.fromLTRB(
                      8.0,
                      row.isAd && index > 0 && rows[index - 1].isAd ? 6.0 : 2.0,
                      8.0,
                      2.0,
                    );
                    return Padding(
                      key: ValueKey(row.key),
                      padding: rowPadding,
                      child: FaAdViewport(
                        viewportKey: _viewportKey,
                        scrollController: _scrollController,
                        active: _adsActive,
                        geometryPadding: rowPadding,
                        visibilityManagedExternally: true,
                        onGeometryReader: (reader, attached) {
                          _ads.registerViewportRow(
                            page: row.page, key: row.key, kind: row.kind,
                            artworkIndex: row.artworkIndex,
                            placement: slot?.definition.placement,
                            reader: reader, attached: attached,
                          );
                        },
                        onLayoutChanged: _ads.layoutChanged,
                        onVisibility: (visible, ratio) {
                          if (slot != null && section != null) {
                            section.setSlotVisibility(slot.definition.placement, visible, ratio);
                          }
                        },
                        child: slot != null && section != null
                            ? FaAdBanner(
                                section: section, slot: slot, active: _adsActive,
                                onTap: () => unawaited(_openAd(section, slot)),
                              )
                            : _buildImageRow(row.images!, maxHeight),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  List<_BrowseGridRow> _gridRows() {
    final contentRevision = _controller.sectionsRevision;
    final adsRevision = _ads.structureRevision;
    if (_cachedContentRevision == contentRevision &&
        _cachedAdsRevision == adsRevision) {
      return _cachedGridRows;
    }
    final result = <_BrowseGridRow>[];
    for (final page in _controller.sections) {
      final section = _ads.section(page.pageNumber);
      void addAd(FaAdSlotController slot) {
        result.add(_BrowseGridRow(
          key: 'page-${page.pageNumber}-ad-${slot.definition.placement.name}',
          page: page, section: section, slot: slot,
          kind: slot.definition.placement == FaAdPlacement.headerMiddle
              ? BrowseAdRowKind.headerAd : BrowseAdRowKind.footerAd,
        ));
      }
      if (section != null) {
        for (final slot in section.slots) {
          if (slot.definition.placement == FaAdPlacement.headerMiddle) addAd(slot);
        }
      }
      for (var index = 0; index < page.rows.length; index++) {
        result.add(_BrowseGridRow(
          key: 'page-${page.pageNumber}-art-$index',
          page: page, images: page.rows[index],
          kind: BrowseAdRowKind.artwork, artworkIndex: index,
        ));
      }
      if (section != null) {
        for (final slot in section.slots) {
          if (slot.definition.placement != FaAdPlacement.headerMiddle) addAd(slot);
        }
      }
    }
    final decorated = <_BrowseGridRow>[];
    for (var index = 0; index < result.length; index++) {
      final row = result[index];
      if (row.isAd && (index == 0 || !result[index - 1].isAd)) {
        decorated.add(_BrowseGridRow(
          key: 'ad-block-start-${row.key}',
          page: row.page, kind: BrowseAdRowKind.divider,
        ));
      }
      decorated.add(row);
      if (row.isAd && (index == result.length - 1 || !result[index + 1].isAd)) {
        decorated.add(_BrowseGridRow(
          key: 'ad-block-end-${row.key}',
          page: row.page, kind: BrowseAdRowKind.divider,
        ));
      }
    }
    _cachedGridRows = List.unmodifiable(decorated);
    _rowIndexByKey = {
      for (var index = 0; index < decorated.length; index++)
        decorated[index].key: index,
    };
    _cachedContentRevision = contentRevision;
    _cachedAdsRevision = adsRevision;
    FaAdsLog.event(FaAdsLogCategory.perf, 'browse_row_cache_rebuilt',
        counts: {'rows': decorated.length, 'sections': _controller.sections.length},
        checks: {'stableKeys': true, 'countingRequest': false});
    return _cachedGridRows;
  }

  void _openArtwork(Map<String, dynamic> image) {
    _artworkExcursion = true;
    Navigator.push(
      context,
      SubmissionDetailsScreen.route(
        imageUrl: image['url'], submissionId: image['uniqueNumber'],
        skipInitialWatchCheck: true,
      ),
    );
  }

  Future<void> _openAd(FaAdSectionController section, FaAdSlotController slot) async {
    if (_adTapPending || !_adsActive.value) return;
    _adTapPending = true;
    _ads.adInteractionStarted(section.sectionNumber);
    try {
      final destination = await section.click(slot);
      if (destination == null || !mounted || !_adsActive.value) {
        return;
      }
      _adExcursion = true;
      _adHandoff = true;
      _updateAdActivity();
      final disposition = await handleFAAdDestination(context, destination);
      if (!mounted) return;
      FaAdsLog.event(FaAdsLogCategory.click, 'destination_handed_off',
          section: section.sectionNumber, slot: slot.definition.placement.name,
          checks: {'internal': disposition == FaAdLinkDisposition.internal,
            'external': disposition == FaAdLinkDisposition.external,
            'opened': disposition != FaAdLinkDisposition.failed,
            'confirmationSkippedForAd': true, 'trackingUrlOpenedTwice': false});
      if (disposition == FaAdLinkDisposition.failed) {
        _adHandoff = false;
        _adExcursion = false;
        _updateAdActivity();
      } else if (disposition == FaAdLinkDisposition.external && _appResumed && _routeVisible) {
        _adHandoff = false;
        _adExcursion = false;
        _ads.adReturned();
        _updateAdActivity();
      }
    } catch (_) {
      if (!mounted) return;
      _adHandoff = false;
      _adExcursion = false;
      _updateAdActivity();
      FaAdsLog.event(FaAdsLogCategory.click, 'handoff_failed');
    } finally {
      _adTapPending = false;
    }
  }

  Widget _buildImageRow(
      List<Map<String, dynamic>> rowImages, double maxHeight) {
    if (rowImages.length == 1) {
      return _buildSingleImage(rowImages[0], maxHeight);
    } else {
      return _buildDoubleImage(rowImages[0], rowImages[1], maxHeight);
    }
  }

  Widget _buildSingleImage(Map<String, dynamic> image, double maxHeight) {
    final aspectRatio = image['width'] / image['height'];

    return LayoutBuilder(
      builder: (context, constraints) {
        final rowWidth = constraints.maxWidth;
        double width = rowWidth;
        double height = width / aspectRatio;

        if (height > maxHeight) {
          final scalingFactor = maxHeight / height;
          width *= scalingFactor;
          height = maxHeight;
        }

        return Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
            child: _FavImageTile(
              image: image,
              width: width,
              height: height,
              sfwEnabled: _controller.sfwEnabled,
              onTap: () => _openArtwork(image),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDoubleImage(
    Map<String, dynamic> left,
    Map<String, dynamic> right,
    double maxHeight,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const margin = 4.0;
        double rowWidth = constraints.maxWidth - margin;
        final arL = left['width'] / left['height'];
        final arR = right['width'] / right['height'];
        final ratio = arR / arL;

        double wL = rowWidth / (1 + ratio);
        double wR = rowWidth - wL;
        double h = wL / arL;
        if (h > maxHeight) {
          final scale = maxHeight / h;
          wL *= scale;
          wR *= scale;
          h = maxHeight;
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FavImageTile(
              image: left,
              width: wL,
              height: h,
              sfwEnabled: _controller.sfwEnabled,
              onTap: () => _openArtwork(left),
            ),
            const SizedBox(width: margin),
            _FavImageTile(
              image: right,
              width: wR,
              height: h,
              sfwEnabled: _controller.sfwEnabled,
              onTap: () => _openArtwork(right),
            ),
          ],
        );
      },
    );
  }
}

class _BrowseGridRow {
  const _BrowseGridRow({
    required this.key,
    required this.page,
    required this.kind,
    this.artworkIndex,
    this.images,
    this.section,
    this.slot,
  });

  final String key;
  final BrowseGridSection page;
  final BrowseAdRowKind kind;
  final int? artworkIndex;
  final List<Map<String, dynamic>>? images;
  final FaAdSectionController? section;
  final FaAdSlotController? slot;

  bool get isAd => kind == BrowseAdRowKind.headerAd || kind == BrowseAdRowKind.footerAd;
}

class _FavImageTile extends StatefulWidget {
  final Map<String, dynamic> image;
  final double width;
  final double height;
  final bool sfwEnabled;
  final VoidCallback onTap;

  const _FavImageTile({
    required this.image,
    required this.width,
    required this.height,
    required this.sfwEnabled,
    required this.onTap,
  });

  @override
  State<_FavImageTile> createState() => _FavImageTileState();
}

class _FavImageTileState extends State<_FavImageTile> {
  @override
  Widget build(BuildContext context) {
    final imageUrl = widget.image['url'];
    final submissionId = widget.image['uniqueNumber'] as String;
    final fallbackIsFavorite = widget.image['isFav'] as bool? ?? false;
    final isFavorite = context.select<SubmissionFavoriteStateController, bool>(
      (controller) => controller.valueFor(submissionId, fallbackIsFavorite),
    );
    final String? rating = widget.image['rating'] as String?;
    final String? title = widget.image['title'] as String?;
    final String? author = widget.image['author'] as String?;
    final String? authorProfileUrl = widget.image['authorProfileUrl'] as String?;

    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: () {
        context.read<SubmissionFavoriteStateController>().toggle(
              submissionId: submissionId,
              fallbackIsFavorite: fallbackIsFavorite,
              favUrl: widget.image['favUrl'] as String?,
              unfavUrl: widget.image['unfavUrl'] as String?,
              sfwEnabled: widget.sfwEnabled,
            );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HeartAnimationWidget(
            isFavorite: isFavorite,
            containerWidth: widget.width,
            containerHeight: widget.height,
            child: FaThumbnailOutline(
              rating: rating,
              borderRadius: 8.0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8.0),
                child: Container(
                  width: widget.width,
                  height: widget.height,
                  color: const Color(0xFF2C2C2C),
                  child: FaNetworkImage(
                    imageUrl,
                    width: widget.width,
                    height: widget.height,
                    fit: BoxFit.cover,
                    loadingBuilder: (ctx, child, progress) {
                      if (progress == null) return child;
                      return const ColoredBox(color: Color(0xFF2C2C2C));
                    },
                    errorBuilder: (ctx, err, stack) {
                      return Container(
                        width: widget.width,
                        height: widget.height,
                        color: Colors.grey,
                        alignment: Alignment.center,
                        child: const Icon(Icons.error, color: Colors.red),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          FaThumbnailCaption(
            maxWidth: widget.width,
            title: title,
            author: author,
            authorProfileUrl: authorProfileUrl,
          ),
        ],
      ),
    );
  }
}
