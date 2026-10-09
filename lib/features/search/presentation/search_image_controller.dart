import 'dart:async';

import 'package:fanotifier/core/logging/app_logging.dart';
import 'package:fanotifier/core/preferences/sfw_mode_preference.dart';
import 'package:fanotifier/features/auth/domain/cloudflare_check_result.dart';
import 'package:fanotifier/features/search/domain/search_repository.dart';
import 'package:fanotifier/shared/fa/cloudflare_challenge_exception.dart';
import 'package:fanotifier/shared/fa/domain/fa_grid_pagination.dart';
import 'package:fanotifier/shared/fa/domain/fa_page_settings.dart';
import 'package:fanotifier/shared/fa/fa_thumbnail_processing.dart';
import 'package:fanotifier/shared/fa/presentation/fa_content_block_controller.dart';
import 'package:material_ui/material_ui.dart';

typedef SearchCloudflareCheck = Future<CloudflareCheckResult?> Function({
  String? initialUrl,
});

class SearchImageController {
  SearchImageController({
    required this._selectedFilters,
    required this._searchQuery,
    required this._isMounted,
    required this._notifyView,
    required this._showCloudflareCheck,
    required this._repository,
    this.contentBlockController,
    SfwModePreference? sfwModePreference,
  }) : _sfwModePreference = sfwModePreference ?? SfwModePreference();

  static const double _nextPageLeadScreens = 2.5;

  Map<String, String> _selectedFilters;
  String _searchQuery;
  final bool Function() _isMounted;
  final VoidCallback _notifyView;
  final SearchCloudflareCheck _showCloudflareCheck;
  final SearchRepository _repository;
  final FaContentBlockController? contentBlockController;
  final SfwModePreference _sfwModePreference;

  int currentPage = 1;
  bool isLoading = false;
  bool hasMore = true;
  bool isError = false;
  String? errorMessage;
  final List<Map<String, dynamic>> images = [];
  final List<List<Map<String, dynamic>>> imageRows = [];
  final FaLoadedItemIds _loadedIds = FaLoadedItemIds();
  final FaGridPaginationProgress _pagination = FaGridPaginationProgress();
  List<Map<String, dynamic>> normalImagesQueue = [];
  final ScrollController scrollController = ScrollController();

  bool _sfwEnabled = true;
  late final Future<void> _sfwLoadFuture;
  bool _isHandlingCloudflareChallenge = false;
  bool _cloudflareRecoveryCancelled = false;
  double _nextPageTriggerOffset = double.infinity;
  bool _pendingNextPageFetch = false;
  bool _isNextPageFetchQueued = false;
  bool isNavbarScrolling = false;
  int _requestGeneration = 0;
  bool _disposed = false;

  void start() {
    _sfwLoadFuture = _loadSfwEnabled();
    currentPage = FaPageSettings.startingPage(_selectedFilters);
    fetchImages(currentPage);
    scrollController.addListener(_scrollListener);
  }

  bool get sfwEnabled => _sfwEnabled;
  bool get isHandlingChallenge => _isHandlingCloudflareChallenge;

  Future<void> recoverVerifiedSession() async {
    if (!_isMounted() || isLoading || _isHandlingCloudflareChallenge) return;
    _cloudflareRecoveryCancelled = false;
    hasMore = true;
    await fetchImages(currentPage, remainingCloudflareRecoveries: 0);
  }

  Future<void> _loadSfwEnabled() async {
    _sfwEnabled = await _sfwModePreference.loadSfwEnabled();
  }

  void dispose() {
    _disposed = true;
    _requestGeneration++;
    scrollController.dispose();
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

  Future<void> refresh({
    required Map<String, String> selectedFilters,
    required String searchQuery,
  }) async {
    _requestGeneration++;
    isLoading = false;
    _cloudflareRecoveryCancelled = false;
    _selectedFilters = Map<String, String>.from(selectedFilters);
    _searchQuery = searchQuery;
    images.clear();
    _loadedIds.clear();
    _pagination.clear();
    imageRows.clear();
    normalImagesQueue.clear();
    currentPage = FaPageSettings.startingPage(_selectedFilters);
    hasMore = true;
    _nextPageTriggerOffset = double.infinity;
    _pendingNextPageFetch = false;
    _isNextPageFetchQueued = false;
    isError = false;
    errorMessage = null;
    _notifyIfMounted();
    await fetchImages(currentPage, isRefresh: true);
  }

  Future<String> _getAllCookies(Map<String, String> filters) async {
    await _sfwLoadFuture;
    return _repository.buildCookieHeader(
      selectedFilters: filters,
      sfwEnabled: _sfwEnabled,
    );
  }

  Future<bool> _appendImages(
    List<Map<String, dynamic>> newImages, {
    required int pageNumber,
    required int generation,
    required double previousMaxScrollExtent,
  }) async {
    final batch = _loadedIds.prepare(
      newImages,
      idOf: (image) => image['uniqueNumber'] as String,
    );
    var appendedRows = <List<Map<String, dynamic>>>[];
    var nextQueue = normalImagesQueue;
    if (batch.items.isNotEmpty) {
      final rowProcessing = await processFaImageRows(
        newImages: batch.items,
        normalImagesQueue: normalImagesQueue,
      );
      appendedRows = (rowProcessing['rows'] as List)
          .map((row) => List<Map<String, dynamic>>.from(row as List))
          .toList();
      nextQueue =
          List<Map<String, dynamic>>.from(rowProcessing['queue'] as List);
    }

    if (_disposed || !_isMounted() || generation != _requestGeneration) {
      return false;
    }

    hasMore = newImages.isNotEmpty;
    _loadedIds.commit(batch);
    _pagination.record(
      cursor: '$pageNumber',
      duplicateOnly: batch.duplicateOnly,
    );
    images.addAll(batch.items);
    imageRows.addAll(appendedRows);
    normalImagesQueue = nextQueue;
    _pendingNextPageFetch = false;
    _isNextPageFetchQueued = false;
    isLoading = false;
    final continueLoading = batch.duplicateOnly && !_pagination.paused;
    if (!continueLoading) _notifyView();
    if (appendedRows.isNotEmpty) {
      _scheduleNextPageTrigger(previousMaxScrollExtent: previousMaxScrollExtent);
    }
    return continueLoading;
  }

  Future<void> fetchImages(
    int pageNumber, {
    bool isRefresh = false,
    int remainingCloudflareRecoveries = 2,
  }) async {
    if (_disposed ||
        !_isMounted() ||
        isLoading ||
        !hasMore ||
        _cloudflareRecoveryCancelled) {
      return;
    }
    final generation = _requestGeneration;
    final filters = Map<String, String>.from(_selectedFilters);
    final query = _searchQuery;
    final contentBlockRevision = contentBlockController?.revision ?? 0;
    bool stale() =>
        _disposed || !_isMounted() || generation != _requestGeneration;
    kDebugPrint(
      '[Search] Fetching page $pageNumber${isRefresh ? ' (refresh)' : ''}',
    );
    final previousMaxScrollExtent = isRefresh || !scrollController.hasClients
        ? 0.0
        : scrollController.position.maxScrollExtent;

    final shouldRebuildImmediately = isRefresh || imageRows.isEmpty;
    isLoading = true;
    isError = false;
    errorMessage = null;
    if (shouldRebuildImmediately) {
      _notifyIfMounted();
    }
    try {
      if (isRefresh) {
        images.clear();
        _loadedIds.clear();
        _pagination.clear();
        imageRows.clear();
        normalImagesQueue.clear();
        currentPage = pageNumber;
        hasMore = true;
        _nextPageTriggerOffset = double.infinity;
        _pendingNextPageFetch = false;
        _isNextPageFetchQueued = false;
      }

      if (stale()) return;
      final page = await _repository.fetchImages(
        pageNumber: pageNumber,
        selectedFilters: filters,
        searchQuery: query,
        cookieHeader: _getAllCookies(filters),
        isCancelled: stale,
      );
      if (stale()) return;
      contentBlockController?.acceptItems(
        page.images,
        expectedRevision: contentBlockRevision,
      );
      final continueLoading = await _appendImages(
        page.images,
        pageNumber: pageNumber,
        generation: generation,
        previousMaxScrollExtent: previousMaxScrollExtent,
      );
      if (continueLoading && !stale()) {
        currentPage = pageNumber + 1;
        await fetchImages(currentPage);
      }
    } on CloudflareChallengeException catch (e) {
      if (stale()) return;
      kDebugPrint('Cloudflare challenge detected while fetching search images.');
      if (_isMounted()) {
        _pendingNextPageFetch = false;
        _isNextPageFetchQueued = false;
        isLoading = false;
        _notifyView();
      }

      if (remainingCloudflareRecoveries <= 0) {
        _cloudflareRecoveryCancelled = true;
        hasMore = false;
        isError = true;
        errorMessage = 'Fur Affinity access could not be verified. Pull to retry.';
        _pendingNextPageFetch = false;
        _isNextPageFetchQueued = false;
        _nextPageTriggerOffset = scrollController.hasClients
            ? scrollController.position.pixels + 1
            : double.infinity;
        _notifyIfMounted();
        return;
      }
      final result = await _requestCloudflareCheck(initialUrl: e.initialUrl);
      if (stale()) return;
      if (result?.passed != true || !_isMounted()) {
        _cloudflareRecoveryCancelled = true;
        hasMore = false;
        isError = true;
        errorMessage = result?.siteUnavailableMessage ??
            'Verification was closed. Pull to retry.';
        _pendingNextPageFetch = false;
        _isNextPageFetchQueued = false;
        _nextPageTriggerOffset = scrollController.hasClients
            ? scrollController.position.pixels + 1
            : double.infinity;
        _notifyIfMounted();
        return;
      }

      await fetchImages(
        pageNumber,
        isRefresh: isRefresh,
        remainingCloudflareRecoveries: remainingCloudflareRecoveries - 1,
      );
      return;
    } catch (e) {
      if (stale()) return;
      kDebugPrint('Error fetching images: $e');
      _pendingNextPageFetch = false;
      _isNextPageFetchQueued = false;
      isLoading = false;
      isError = true;
      errorMessage = e.toString();
      _notifyIfMounted();
      _nextPageTriggerOffset = scrollController.hasClients
          ? scrollController.position.pixels + 1
          : double.infinity;
    }
  }

  Future<CloudflareCheckResult?> _requestCloudflareCheck({
    String? initialUrl,
  }) async {
    if (!_isMounted() || _isHandlingCloudflareChallenge) return null;
    _isHandlingCloudflareChallenge = true;
    try {
      return await _showCloudflareCheck(initialUrl: initialUrl);
    } finally {
      _isHandlingCloudflareChallenge = false;
    }
  }

  void _scrollListener() {
    if (_disposed || _pagination.paused || isNavbarScrolling ||
        !scrollController.hasClients ||
        isLoading ||
        _isNextPageFetchQueued ||
        !hasMore ||
        _isHandlingCloudflareChallenge) {
      return;
    }

    if (!_hasReachedNextPageTrigger(scrollController.position)) {
      return;
    }

    _pendingNextPageFetch = true;
    _tryStartPendingNextPageFetch();
  }

  bool handleScrollNotification(ScrollNotification notification) {
    if (isNavbarScrolling || notification.metrics.axis != Axis.vertical) return false;
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _pagination.resume();
    }

    if (_disposed || _pagination.paused || !_isMounted() ||
        isLoading ||
        _isNextPageFetchQueued ||
        !hasMore ||
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
        isLoading ||
        _isNextPageFetchQueued ||
        !hasMore ||
        _isHandlingCloudflareChallenge) {
      return;
    }
    if (!_hasReachedNextPageTrigger(scrollController.position)) {
      return;
    }

    _pendingNextPageFetch = false;
    _isNextPageFetchQueued = true;
    _nextPageTriggerOffset = double.infinity;
    final nextPage = currentPage + 1;
    currentPage = nextPage;
    final generation = _requestGeneration;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || generation != _requestGeneration) return;
      if (!_isMounted()) {
        _isNextPageFetchQueued = false;
        return;
      }
      unawaited(fetchImages(nextPage));
    });
  }

  bool _hasReachedNextPageTrigger(ScrollMetrics metrics) {
    final reachedPageThreshold = metrics.pixels >= _nextPageTriggerOffset;
    final reachedLeadThreshold =
        metrics.extentAfter <= metrics.viewportDimension * _nextPageLeadScreens;
    return reachedPageThreshold || reachedLeadThreshold;
  }

  void _scheduleNextPageTrigger({required double previousMaxScrollExtent}) {
    final generation = _requestGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || generation != _requestGeneration) return;
      if (!_isMounted() || !hasMore) {
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

      _nextPageTriggerOffset = previousMaxScrollExtent + (addedExtent * 0.6);
    });
  }

  void _notifyIfMounted() {
    if (_isMounted()) {
      _notifyView();
    }
  }
}
