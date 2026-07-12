import 'dart:async';

import 'package:FANotifier/core/logging/app_logging.dart';
import 'package:FANotifier/core/preferences/sfw_mode_preference.dart';
import 'package:FANotifier/features/auth/domain/cloudflare_check_result.dart';
import 'package:FANotifier/features/search/data/search_image_parser.dart';
import 'package:FANotifier/features/search/data/search_image_service.dart';
import 'package:FANotifier/features/submissions/data/favorite_service.dart';
import 'package:FANotifier/features/submissions/data/submission_favorite_details_service.dart';
import 'package:FANotifier/shared/fa/cloudflare_challenge_exception.dart';
import 'package:FANotifier/shared/fa/fa_thumbnail_processing.dart';
import 'package:flutter/material.dart';

typedef SearchCloudflareCheck = Future<CloudflareCheckResult?> Function({
  String? initialUrl,
});

class SearchImageController {
  SearchImageController({
    required Map<String, String> selectedFilters,
    required String searchQuery,
    required bool Function() isMounted,
    required VoidCallback notifyView,
    required SearchCloudflareCheck showCloudflareCheck,
    SearchImageService? searchImageService,
    FavoriteService? favoriteService,
    SfwModePreference? sfwModePreference,
    SubmissionFavoriteDetailsService? favoriteDetailsService,
  })  : _selectedFilters = selectedFilters,
        _searchQuery = searchQuery,
        _isMounted = isMounted,
        _notifyView = notifyView,
        _showCloudflareCheck = showCloudflareCheck,
        _searchImageService = searchImageService ?? SearchImageService(),
        _favoriteService = favoriteService ?? FavoriteService(),
        _sfwModePreference = sfwModePreference ?? SfwModePreference(),
        _favoriteDetailsService = favoriteDetailsService ??
            const SubmissionFavoriteDetailsService();

  static const double _nextPageLeadScreens = 2.5;

  Map<String, String> _selectedFilters;
  String _searchQuery;
  final bool Function() _isMounted;
  final VoidCallback _notifyView;
  final SearchCloudflareCheck _showCloudflareCheck;
  final SearchImageService _searchImageService;
  final FavoriteService _favoriteService;
  final SfwModePreference _sfwModePreference;
  final SubmissionFavoriteDetailsService _favoriteDetailsService;

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
  final Set<String> favoritedImages = {};
  final Map<String, String> favUrls = {};
  final Map<String, String> unfavUrls = {};

  bool _sfwEnabled = true;
  late final Future<void> _sfwLoadFuture;
  int _detailsEpoch = 0;
  final Map<String, Future<void>> _detailsInFlight = {};
  bool _isHandlingCloudflareChallenge = false;
  double _nextPageTriggerOffset = double.infinity;
  bool _pendingNextPageFetch = false;
  bool _isNextPageFetchQueued = false;

  void start() {
    _sfwLoadFuture = _loadSfwEnabled();
    fetchImages(currentPage);
    scrollController.addListener(_scrollListener);
  }

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
    _detailsEpoch++;
    _detailsInFlight.clear();

    images.clear();
    imageUrls.clear();
    imageRows.clear();
    normalImagesQueue.clear();
    currentPage = 1;
    hasMore = true;
    _nextPageTriggerOffset = double.infinity;
    _pendingNextPageFetch = false;
    _isNextPageFetchQueued = false;
    favoritedImages.clear();
    favUrls.clear();
    unfavUrls.clear();
    isError = false;
    errorMessage = null;
    _notifyIfMounted();
    await fetchImages(currentPage, isRefresh: true);
  }

  Future<String> _getAllCookies() async {
    await _sfwLoadFuture;
    return _searchImageService.buildCookieHeader(
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

      final newImages = await _searchImageService.fetchImages(
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
        final recoveredImages = await parseSearchImageHtml(recoveredHtml);
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

  Future<void> _ensurePostDetails({
    required String uniqueNumber,
    required String postUrl,
  }) async {
    if (uniqueNumber.isEmpty || postUrl.isEmpty) return;

    final hasFav = favUrls[uniqueNumber]?.isNotEmpty == true;
    final hasUnfav = unfavUrls[uniqueNumber]?.isNotEmpty == true;
    if (hasFav || hasUnfav) return;

    final existing = _detailsInFlight[uniqueNumber];
    if (existing != null) {
      await existing;
      return;
    }

    final int epoch = _detailsEpoch;

    final future = () async {
      final details = await _fetchPostDetails(postUrl);
      if (!_isMounted()) return;
      if (epoch != _detailsEpoch) return;
      if (details == null) return;

      final favUrl = details['favUrl'] ?? '';
      final unfavUrl = details['unfavUrl'] ?? '';

      favUrls[uniqueNumber] = favUrl;
      unfavUrls[uniqueNumber] = unfavUrl;

      if (unfavUrl.isNotEmpty && favUrl.isEmpty) {
        favoritedImages.add(uniqueNumber);
      } else if (favUrl.isNotEmpty && unfavUrl.isEmpty) {
        favoritedImages.remove(uniqueNumber);
      } else if (unfavUrl.isNotEmpty) {
        favoritedImages.add(uniqueNumber);
      }
      _notifyView();
    }();

    _detailsInFlight[uniqueNumber] = future;

    try {
      await future;
    } finally {
      if (_detailsInFlight[uniqueNumber] == future) {
        _detailsInFlight.remove(uniqueNumber);
      }
    }
  }

  Future<Map<String, String>?> _fetchPostDetails(String postUrl) async {
    final links = await _favoriteDetailsService.fetchLinksForPostUrl(
      postUrl: postUrl,
      cookieHeaderProvider: _getAllCookies,
    );
    if (links == null) return null;

    return {
      'favUrl': links.favUrl,
      'unfavUrl': links.unfavUrl,
    };
  }

  Future<void> toggleFavorite(String uniqueNumber, bool wantFavorite) async {
    final idx = images.indexWhere((e) => e['uniqueNumber'] == uniqueNumber);
    if (idx == -1) return;

    final postUrl = (images[idx]['postUrl'] ?? '') as String;
    if (postUrl.isEmpty) return;

    await _ensurePostDetails(uniqueNumber: uniqueNumber, postUrl: postUrl);

    final hasFav = favUrls[uniqueNumber]?.isNotEmpty == true;
    final hasUnfav = unfavUrls[uniqueNumber]?.isNotEmpty == true;

    if (!hasFav && !hasUnfav) {
      debugPrint('DEBUG: No fav/unfav URLs found for $uniqueNumber');
      return;
    }

    final isCurrentlyFav = favoritedImages.contains(uniqueNumber);

    if (wantFavorite && isCurrentlyFav) {
      debugPrint('Already favored; skipping POST for $uniqueNumber');
      return;
    }
    if (!wantFavorite && !isCurrentlyFav) {
      debugPrint('Already unfavored; skipping POST for $uniqueNumber');
      return;
    }

    final urlToUse = wantFavorite ? favUrls[uniqueNumber] : unfavUrls[uniqueNumber];
    if (urlToUse == null || urlToUse.isEmpty) {
      debugPrint(
        'DEBUG: No URL found for fav/unfav operation on $uniqueNumber.',
      );
      return;
    }

    if (wantFavorite) {
      favoritedImages.add(uniqueNumber);
    } else {
      favoritedImages.remove(uniqueNumber);
    }
    _notifyIfMounted();

    final success = await _favoriteService.executePostWithRetry(urlToUse);
    if (!success) {
      if (wantFavorite) {
        favoritedImages.remove(uniqueNumber);
      } else {
        favoritedImages.add(uniqueNumber);
      }
      _notifyIfMounted();
      debugPrint(
        'DEBUG: Failed to ${wantFavorite ? 'fav' : 'unfav'} $uniqueNumber.',
      );
      return;
    }

    debugPrint(
      'DEBUG: Successfully ${wantFavorite ? 'favored' : 'unfavored'} $uniqueNumber.',
    );

    favUrls[uniqueNumber] = '';
    unfavUrls[uniqueNumber] = '';
    await _ensurePostDetails(uniqueNumber: uniqueNumber, postUrl: postUrl);
  }

  void _notifyIfMounted() {
    if (_isMounted()) {
      _notifyView();
    }
  }
}
