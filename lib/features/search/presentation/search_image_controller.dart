import 'dart:async';

import 'package:fanotifier/core/logging/app_logging.dart';
import 'package:fanotifier/core/preferences/sfw_mode_preference.dart';
import 'package:fanotifier/features/auth/domain/cloudflare_check_result.dart';
import 'package:fanotifier/features/search/domain/search_repository.dart';
import 'package:fanotifier/shared/fa/cloudflare_challenge_exception.dart';
import 'package:fanotifier/shared/fa/fa_thumbnail_processing.dart';
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
    SfwModePreference? sfwModePreference,
  }) : _sfwModePreference = sfwModePreference ?? SfwModePreference();

  static const double _nextPageLeadScreens = 2.5;

  Map<String, String> _selectedFilters;
  String _searchQuery;
  final bool Function() _isMounted;
  final VoidCallback _notifyView;
  final SearchCloudflareCheck _showCloudflareCheck;
  final SearchRepository _repository;
  final SfwModePreference _sfwModePreference;

  int currentPage = 1;
  bool isLoading = false;
  bool hasMore = true;
  bool isError = false;
  String? errorMessage;
  final List<Map<String, dynamic>> images = [];
  final List<List<Map<String, dynamic>>> imageRows = [];
  List<Map<String, dynamic>> normalImagesQueue = [];
  final Set<String> imageUrls = <String>{};
  final ScrollController scrollController = ScrollController();

  bool _sfwEnabled = true;
  late final Future<void> _sfwLoadFuture;
  bool _isHandlingCloudflareChallenge = false;
  double _nextPageTriggerOffset = double.infinity;
  bool _pendingNextPageFetch = false;
  bool _isNextPageFetchQueued = false;

  void start() {
    _sfwLoadFuture = _loadSfwEnabled();
    fetchImages(currentPage);
    scrollController.addListener(_scrollListener);
  }

  bool get sfwEnabled => _sfwEnabled;

  Future<void> _loadSfwEnabled() async {
    _sfwEnabled = await _sfwModePreference.loadSfwEnabled();
  }

  void dispose() {
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
    _selectedFilters = selectedFilters;
    _searchQuery = searchQuery;
    images.clear();
    imageUrls.clear();
    imageRows.clear();
    normalImagesQueue.clear();
    currentPage = 1;
    hasMore = true;
    _nextPageTriggerOffset = double.infinity;
    _pendingNextPageFetch = false;
    _isNextPageFetchQueued = false;
    isError = false;
    errorMessage = null;
    _notifyIfMounted();
    await fetchImages(currentPage, isRefresh: true);
  }

  Future<String> _getAllCookies() async {
    await _sfwLoadFuture;
    return _repository.buildCookieHeader(
      selectedFilters: _selectedFilters,
      sfwEnabled: _sfwEnabled,
    );
  }

  Future<void> _appendImages(
    List<Map<String, dynamic>> newImages, {
    required double previousMaxScrollExtent,
  }) async {
    final filteredImages =
        newImages.where((image) => !imageUrls.contains(image['url'])).toList();

    kDebugPrint(
      '[Search] Parsed ${newImages.length} thumbnails, '
      'appending ${filteredImages.length} new ones.',
    );

    for (final image in filteredImages) {
      imageUrls.add(image['url']);
    }

    final rowProcessing = await processFaImageRows(
      newImages: filteredImages,
      normalImagesQueue: normalImagesQueue,
    );
    final appendedRows = (rowProcessing['rows'] as List)
        .map(
          (row) => List<Map<String, dynamic>>.from(row as List),
        )
        .toList();
    final nextQueue =
        List<Map<String, dynamic>>.from(rowProcessing['queue'] as List);

    if (!_isMounted()) return;

    hasMore = newImages.isNotEmpty && filteredImages.isNotEmpty;
    images.addAll(filteredImages);
    imageRows.addAll(appendedRows);
    normalImagesQueue = nextQueue;
    _pendingNextPageFetch = false;
    _isNextPageFetchQueued = false;
    isLoading = false;
    _notifyView();

    _scheduleNextPageTrigger(previousMaxScrollExtent: previousMaxScrollExtent);
  }

  Future<void> fetchImages(
    int pageNumber, {
    bool isRefresh = false,
    int remainingCloudflareRecoveries = 2,
  }) async {
    if (isLoading || !hasMore) return;
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
        imageUrls.clear();
        imageRows.clear();
        normalImagesQueue.clear();
        currentPage = 1;
        hasMore = true;
        _nextPageTriggerOffset = double.infinity;
        _pendingNextPageFetch = false;
        _isNextPageFetchQueued = false;
      }

      final newImages = await _repository.fetchImages(
        pageNumber: pageNumber,
        selectedFilters: _selectedFilters,
        searchQuery: _searchQuery,
        cookieHeader: await _getAllCookies(),
      );
      await _appendImages(
        newImages,
        previousMaxScrollExtent: previousMaxScrollExtent,
      );
    } on CloudflareChallengeException catch (e) {
      kDebugPrint('Cloudflare challenge detected while fetching search images.');
      if (_isMounted()) {
        _pendingNextPageFetch = false;
        _isNextPageFetchQueued = false;
        isLoading = false;
        _notifyView();
      }

      if (remainingCloudflareRecoveries <= 0) {
        _pendingNextPageFetch = false;
        _isNextPageFetchQueued = false;
        _nextPageTriggerOffset = scrollController.hasClients
            ? scrollController.position.pixels + 1
            : double.infinity;
        return;
      }
      final result = await _requestCloudflareCheck(initialUrl: e.initialUrl);
      if (result?.passed != true || !_isMounted()) {
        _pendingNextPageFetch = false;
        _isNextPageFetchQueued = false;
        _nextPageTriggerOffset = scrollController.hasClients
            ? scrollController.position.pixels + 1
            : double.infinity;
        return;
      }

      final recoveredHtml = result?.pageHtml;
      if (recoveredHtml != null && recoveredHtml.isNotEmpty) {
        final recoveredImages =
            await _repository.parseRecoveredHtml(recoveredHtml);
        await _appendImages(
          recoveredImages,
          previousMaxScrollExtent: previousMaxScrollExtent,
        );
        return;
      }

      await fetchImages(
        pageNumber,
        isRefresh: isRefresh,
        remainingCloudflareRecoveries: remainingCloudflareRecoveries - 1,
      );
      return;
    } catch (e) {
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
    if (!scrollController.hasClients ||
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
    if (notification.metrics.axis != Axis.vertical) return false;

    if (!_isMounted() ||
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
    if (!_pendingNextPageFetch ||
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
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
