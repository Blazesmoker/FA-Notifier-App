import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'package:fanotifier/core/logging/app_logging.dart';
import 'package:fanotifier/features/auth/domain/cloudflare_check_result.dart';
import 'package:fanotifier/features/browse/domain/browse_page_data.dart';
import 'package:fanotifier/features/browse/domain/browse_repository.dart';
import 'package:fanotifier/features/browse/presentation/browse_ad_scroll_controller.dart';
import 'package:fanotifier/shared/fa/cloudflare_challenge_exception.dart';
import 'package:fanotifier/shared/fa/domain/fa_grid_pagination.dart';
import 'package:fanotifier/shared/fa/domain/fa_page_settings.dart';
import 'package:fanotifier/shared/fa/fa_thumbnail_processing.dart';
import 'package:fanotifier/shared/fa/presentation/fa_content_block_controller.dart';

typedef BrowseCloudflareChallengeHandler = Future<CloudflareCheckResult?>
    Function(String? initialUrl);

class BrowseImageGridController extends ChangeNotifier {
  BrowseImageGridController({
    required this._selectedFilters,
    required this._onCloudflareChallenge,
    required this._repository,
    required this._sfwEnabled,
    this.contentBlockController,
  });

  static const double _nextPageLeadScreens = 2.5;

  final BrowseCloudflareChallengeHandler _onCloudflareChallenge;
  final BrowseRepository _repository;
  final FaContentBlockController? contentBlockController;
  final BrowseAdScrollController scrollController = BrowseAdScrollController();
  final List<Map<String, dynamic>> _images = [];
  final List<List<Map<String, dynamic>>> _imageRows = [];
  final List<BrowseGridSection> _sections = [];
  final FaLoadedItemIds _loadedIds = FaLoadedItemIds();
  final FaGridPaginationProgress _pagination = FaGridPaginationProgress();

  Map<String, String> _selectedFilters;
  List<Map<String, dynamic>> _normalImagesQueue = [];
  int _currentPage = 1;
  bool _isLoading = false;
  bool _hasMore = true;
  bool _isError = false;
  String? _errorMessage;
  bool _sfwEnabled;
  int _requestGeneration = 0;
  int _sectionsRevision = 0;
  bool _isHandlingCloudflareChallenge = false;
  bool _cloudflareRecoveryCancelled = false;
  double _nextPageTriggerOffset = double.infinity;
  bool _pendingNextPageFetch = false;
  bool _isNextPageFetchQueued = false;
  bool _disposed = false;
  bool isNavbarScrolling = false;

  int get currentPage => _currentPage;
  bool get hasMore => _hasMore;
  List<Map<String, dynamic>> get images => _images;
  List<List<Map<String, dynamic>>> get imageRows => _imageRows;
  List<BrowseGridSection> get sections => _sections;
  int get sectionsRevision => _sectionsRevision;
  List<Map<String, dynamic>> get normalImagesQueue => _normalImagesQueue;
  bool get sfwEnabled => _sfwEnabled;
  bool get isLoading => _isLoading;
  bool get isHandlingChallenge => _isHandlingCloudflareChallenge;

  Future<void> recoverVerifiedSession() async {
    if (_disposed || _isLoading || _isHandlingCloudflareChallenge) return;
    _cloudflareRecoveryCancelled = false;
    _hasMore = true;
    await _fetchImages(_currentPage, remainingCloudflareRecoveries: 0);
  }
  bool get isError => _isError;
  String? get errorMessage => _errorMessage;

  void initialize() {
    _currentPage = FaPageSettings.startingPage(_selectedFilters);
    unawaited(_fetchImages(_currentPage));
    scrollController.addListener(_scrollListener);
  }

  Future<void> scrollToTop({bool animate = true}) async {
    if (!scrollController.hasClients) return;
    if (!animate) {
      scrollController.jumpTo(0);
      return;
    }
    await scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _scrollListener() {
    if (_disposed || _pagination.paused || isNavbarScrolling ||
        !scrollController.hasClients ||
        _isLoading ||
        _isNextPageFetchQueued ||
        !_hasMore ||
        _isHandlingCloudflareChallenge) {
      return;
    }

    if (!_hasReachedNextPageTrigger(scrollController.position)) {
      return;
    }

    _pendingNextPageFetch = true;
    _tryStartPendingNextPageFetch();
  }

  Future<void> refresh(
    Map<String, String> selectedFilters, {
    required bool sfwEnabled,
  }) async {
    _requestGeneration++;
    _isLoading = false;
    _cloudflareRecoveryCancelled = false;
    _sfwEnabled = sfwEnabled;
    _selectedFilters = selectedFilters;
    _images.clear();
    _loadedIds.clear();
    _pagination.clear();
    _imageRows.clear();
    _sections.clear();
    _sectionsRevision++;
    _normalImagesQueue.clear();
    _currentPage = FaPageSettings.startingPage(_selectedFilters);
    _hasMore = true;
    _nextPageTriggerOffset = double.infinity;
    _pendingNextPageFetch = false;
    _isNextPageFetchQueued = false;
    _isError = false;
    _errorMessage = null;
    _notifyChanged();
    await _fetchImages(_currentPage, isRefresh: true);
  }

  void cancelPendingRequests() {
    _requestGeneration++;
    _hasMore = false;
    _pendingNextPageFetch = false;
    _isNextPageFetchQueued = false;
  }

  Future<void> _fetchImages(
    int pageNumber, {
    bool isRefresh = false,
    int remainingCloudflareRecoveries = 2,
  }) async {
    if (_isLoading || !_hasMore || _cloudflareRecoveryCancelled) return;
    final generation = _requestGeneration;
    final filters = Map<String, String>.from(_selectedFilters);
    final sfwEnabled = _sfwEnabled;
    final contentBlockRevision = contentBlockController?.revision ?? 0;
    bool stale() => _disposed || generation != _requestGeneration;
    kDebugPrint('[Browse] Fetching page $pageNumber${isRefresh ? ' (refresh)' : ''}');
    final previousMaxScrollExtent = isRefresh || !scrollController.hasClients
        ? 0.0
        : scrollController.position.maxScrollExtent;
    final shouldRebuildImmediately = isRefresh || _imageRows.isEmpty;
    _isLoading = true;
    if (shouldRebuildImmediately) {
      _notifyChanged();
    }

    try {
      if (isRefresh) {
        _images.clear();
        _loadedIds.clear();
        _pagination.clear();
        _imageRows.clear();
        _sections.clear();
        _sectionsRevision++;
        _normalImagesQueue.clear();
        _currentPage = pageNumber;
        _hasMore = true;
        _nextPageTriggerOffset = double.infinity;
        _pendingNextPageFetch = false;
        _isNextPageFetchQueued = false;
      }

      final page = await _repository.fetchImages(
        pageNumber: pageNumber,
        selectedFilters: filters,
        sfwEnabled: sfwEnabled,
        isCancelled: stale,
      );
      if (stale()) return;
      contentBlockController?.acceptItems(
        page.images,
        expectedRevision: contentBlockRevision,
      );
      final continueLoading = await _appendImages(
        page,
        pageNumber: pageNumber,
        generation: generation,
        previousMaxScrollExtent: previousMaxScrollExtent,
      );
      if (continueLoading && !stale()) {
        _currentPage = pageNumber + 1;
        await _fetchImages(_currentPage);
      }
    } on CloudflareChallengeException catch (e) {
      if (stale()) return;
      kDebugPrint('Cloudflare challenge detected while fetching browse images.');
      _isLoading = false;
      _notifyChanged();

      if (remainingCloudflareRecoveries <= 0) {
        _cloudflareRecoveryCancelled = true;
        _hasMore = false;
        _isError = true;
        _errorMessage = 'Fur Affinity access could not be verified. Pull to retry.';
        _pendingNextPageFetch = false;
        _isNextPageFetchQueued = false;
        _nextPageTriggerOffset = scrollController.hasClients
            ? scrollController.position.pixels + 1
            : double.infinity;
        _notifyChanged();
        return;
      }

      final result = await _showCloudflareDialog(initialUrl: e.initialUrl);
      if (stale()) return;
      if (result?.passed != true) {
        _cloudflareRecoveryCancelled = true;
        _hasMore = false;
        _isError = true;
        _errorMessage = result?.siteUnavailableMessage ??
            'Verification was closed. Pull to retry.';
        _pendingNextPageFetch = false;
        _isNextPageFetchQueued = false;
        _nextPageTriggerOffset = scrollController.hasClients
            ? scrollController.position.pixels + 1
            : double.infinity;
        _notifyChanged();
        return;
      }

      await _fetchImages(
        pageNumber,
        isRefresh: isRefresh,
        remainingCloudflareRecoveries: remainingCloudflareRecoveries - 1,
      );
    } catch (e) {
      if (stale()) return;
      _pendingNextPageFetch = false;
      _isNextPageFetchQueued = false;
      _isLoading = false;
      _isError = true;
      _errorMessage = e.toString();
      _notifyChanged();
      kDebugPrint('FAImageGrid: Error fetching images => $e');
      _nextPageTriggerOffset = scrollController.hasClients
          ? scrollController.position.pixels + 1
          : double.infinity;
    }
  }

  Future<bool> _appendImages(
    BrowsePageData page, {
    required int pageNumber,
    required int generation,
    required double previousMaxScrollExtent,
  }) async {
    final newImages = page.images;
    final batch = _loadedIds.prepare(
      newImages,
      idOf: (image) => image['uniqueNumber'] as String,
    );
    var appendedRows = <List<Map<String, dynamic>>>[];
    var nextQueue = _normalImagesQueue;
    if (batch.items.isNotEmpty) {
      final rowProcessing = await processFaImageRows(
        newImages: batch.items,
        normalImagesQueue: _normalImagesQueue,
      );
      appendedRows = (rowProcessing['rows'] as List)
          .map((row) => List<Map<String, dynamic>>.from(row as List))
          .toList();
      nextQueue =
          List<Map<String, dynamic>>.from(rowProcessing['queue'] as List);
    }

    if (_disposed || generation != _requestGeneration) return false;

    _isError = false;
    _errorMessage = null;
    _hasMore = newImages.isNotEmpty;
    _loadedIds.commit(batch);
    _pagination.record(
      cursor: '$pageNumber',
      duplicateOnly: batch.duplicateOnly,
    );
    _images.addAll(batch.items);
    _imageRows.addAll(appendedRows);
    if (appendedRows.isNotEmpty) {
      _sections.add(BrowseGridSection(
        pageNumber: pageNumber,
        rows: appendedRows,
        ads: page.ads,
      ));
      _sectionsRevision++;
    }
    _normalImagesQueue = nextQueue;
    _pendingNextPageFetch = false;
    _isNextPageFetchQueued = false;
    _isLoading = false;
    final continueLoading = batch.duplicateOnly && !_pagination.paused;
    if (!continueLoading) _notifyChanged();
    if (appendedRows.isNotEmpty) {
      _scheduleNextPageTrigger(previousMaxScrollExtent: previousMaxScrollExtent);
    }
    return continueLoading;
  }

  void _scheduleNextPageTrigger({required double previousMaxScrollExtent}) {
    final generation = _requestGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || generation != _requestGeneration) return;
      if (_disposed || !_hasMore) {
        _pendingNextPageFetch = false;
        _isNextPageFetchQueued = false;
        _nextPageTriggerOffset = double.infinity;
        return;
      }

      if (!scrollController.hasClients) {
        _scheduleNextPageTrigger(
          previousMaxScrollExtent: previousMaxScrollExtent,
        );
        return;
      }

      final newMaxScrollExtent = scrollController.position.maxScrollExtent;
      final addedExtent = newMaxScrollExtent - previousMaxScrollExtent;
      if (addedExtent <= 0) {
        _pendingNextPageFetch = false;
        _isNextPageFetchQueued = false;
        _nextPageTriggerOffset = double.infinity;
        return;
      }

      _nextPageTriggerOffset =
          previousMaxScrollExtent + (addedExtent * 0.6);
    });
  }

  bool handleScrollNotification(ScrollNotification notification) {
    if (isNavbarScrolling || notification.metrics.axis != Axis.vertical) return false;
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _pagination.resume();
    }

    if (_disposed || _pagination.paused ||
        _isLoading ||
        _isNextPageFetchQueued ||
        !_hasMore ||
        _isHandlingCloudflareChallenge) {
      return false;
    }

    if (_hasReachedNextPageTrigger(notification.metrics)) {
      _pendingNextPageFetch = true;
      _tryStartPendingNextPageFetch();
    }

    return false;
  }

  void _tryStartPendingNextPageFetch() {
    if (_disposed || _pagination.paused || isNavbarScrolling ||
        !_pendingNextPageFetch ||
        !scrollController.hasClients ||
        _isLoading ||
        _isNextPageFetchQueued ||
        !_hasMore ||
        _isHandlingCloudflareChallenge) {
      return;
    }
    if (!_hasReachedNextPageTrigger(scrollController.position)) {
      return;
    }

    _pendingNextPageFetch = false;
    _isNextPageFetchQueued = true;
    _nextPageTriggerOffset = double.infinity;
    final nextPage = _currentPage + 1;
    final generation = _requestGeneration;
    _currentPage = nextPage;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || generation != _requestGeneration) return;
      if (nextPage != _currentPage) {
        _isNextPageFetchQueued = false;
        return;
      }
      unawaited(_fetchImages(nextPage));
    });
  }

  bool _hasReachedNextPageTrigger(ScrollMetrics metrics) {
    final reachedPageThreshold = metrics.pixels >= _nextPageTriggerOffset;
    final reachedLeadThreshold =
        metrics.extentAfter <= metrics.viewportDimension * _nextPageLeadScreens;
    return reachedPageThreshold || reachedLeadThreshold;
  }

  Future<CloudflareCheckResult?> _showCloudflareDialog({
    String? initialUrl,
  }) async {
    if (_disposed || _isHandlingCloudflareChallenge) return null;
    _isHandlingCloudflareChallenge = true;
    try {
      return await _onCloudflareChallenge(initialUrl);
    } finally {
      _isHandlingCloudflareChallenge = false;
    }
  }

  void _notifyChanged() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    scrollController.removeListener(_scrollListener);
    scrollController.dispose();
    super.dispose();
  }
}
