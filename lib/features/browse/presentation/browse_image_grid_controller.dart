import 'dart:async';

import 'package:flutter/material.dart';

import 'package:FANotifier/core/logging/app_logging.dart';
import 'package:FANotifier/core/preferences/sfw_mode_preference.dart';
import 'package:FANotifier/features/auth/domain/cloudflare_check_result.dart';
import 'package:FANotifier/features/browse/data/browse_image_parser.dart';
import 'package:FANotifier/features/browse/data/browse_image_service.dart';
import 'package:FANotifier/features/submissions/data/favorite_service.dart';
import 'package:FANotifier/features/submissions/data/submission_favorite_details_service.dart';
import 'package:FANotifier/shared/fa/cloudflare_challenge_exception.dart';
import 'package:FANotifier/shared/fa/fa_thumbnail_processing.dart';

typedef BrowseCloudflareChallengeHandler = Future<CloudflareCheckResult?>
    Function(String? initialUrl);

class BrowseImageGridController extends ChangeNotifier {
  BrowseImageGridController({
    required Map<String, String> selectedFilters,
    required BrowseCloudflareChallengeHandler onCloudflareChallenge,
    BrowseImageService? browseImageService,
    SubmissionFavoriteDetailsService? favoriteDetailsService,
    FavoriteService? favoriteService,
    SfwModePreference? sfwModePreference,
  })  : _selectedFilters = selectedFilters,
        _onCloudflareChallenge = onCloudflareChallenge,
        _browseImageService = browseImageService ?? BrowseImageService(),
        _favoriteDetailsService = favoriteDetailsService ??
            const SubmissionFavoriteDetailsService(),
        _favoriteService = favoriteService ?? FavoriteService(),
        _sfwModePreference = sfwModePreference ?? SfwModePreference();

  static const double _nextPageLeadScreens = 2.5;

  final BrowseCloudflareChallengeHandler _onCloudflareChallenge;
  final BrowseImageService _browseImageService;
  final SubmissionFavoriteDetailsService _favoriteDetailsService;
  final FavoriteService _favoriteService;
  final SfwModePreference _sfwModePreference;
  final ScrollController scrollController = ScrollController();
  final List<Map<String, dynamic>> _images = [];
  final List<List<Map<String, dynamic>>> _imageRows = [];
  final Set<String> _imageUrls = <String>{};
  final Set<String> _favoritedImages = {};
  final Map<String, String> _favUrls = {};
  final Map<String, String> _unfavUrls = {};

  Map<String, String> _selectedFilters;
  List<Map<String, dynamic>> _normalImagesQueue = [];
  int _currentPage = 1;
  bool _isLoading = false;
  bool _hasMore = true;
  bool _isError = false;
  String? _errorMessage;
  bool _sfwEnabled = true;
  late final Future<void> _sfwLoadFuture;
  bool _isHandlingCloudflareChallenge = false;
  double _nextPageTriggerOffset = double.infinity;
  bool _pendingNextPageFetch = false;
  bool _isNextPageFetchQueued = false;
  bool _disposed = false;

  int get currentPage => _currentPage;
  bool get hasMore => _hasMore;
  List<Map<String, dynamic>> get images => _images;
  List<List<Map<String, dynamic>>> get imageRows => _imageRows;
  List<Map<String, dynamic>> get normalImagesQueue => _normalImagesQueue;
  Set<String> get imageUrls => _imageUrls;
  Set<String> get favoritedImages => _favoritedImages;
  bool get isLoading => _isLoading;
  bool get isError => _isError;
  String? get errorMessage => _errorMessage;

  void initialize() {
    _sfwLoadFuture = _loadSfwEnabled();
    unawaited(_fetchImages(_currentPage));
    scrollController.addListener(_scrollListener);
  }

  Future<void> _loadSfwEnabled() async {
    _sfwEnabled = await _sfwModePreference.loadSfwEnabled();
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
    if (!scrollController.hasClients ||
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

  Future<void> refresh(Map<String, String> selectedFilters) async {
    _selectedFilters = selectedFilters;
    _images.clear();
    _imageUrls.clear();
    _imageRows.clear();
    _normalImagesQueue.clear();
    _currentPage = 1;
    _hasMore = true;
    _nextPageTriggerOffset = double.infinity;
    _pendingNextPageFetch = false;
    _isNextPageFetchQueued = false;
    _favoritedImages.clear();
    _favUrls.clear();
    _unfavUrls.clear();
    _isError = false;
    _errorMessage = null;
    _notifyChanged();
    await _fetchImages(_currentPage, isRefresh: true);
  }

  Future<void> _fetchImages(
    int pageNumber, {
    bool isRefresh = false,
    int remainingCloudflareRecoveries = 2,
  }) async {
    if (_isLoading || !_hasMore) return;
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
        _imageUrls.clear();
        _imageRows.clear();
        _normalImagesQueue.clear();
        _currentPage = 1;
        _hasMore = true;
        _nextPageTriggerOffset = double.infinity;
        _pendingNextPageFetch = false;
        _isNextPageFetchQueued = false;
      }

      await _sfwLoadFuture;
      final newImages = await _browseImageService.fetchImages(
        pageNumber: pageNumber,
        selectedFilters: _selectedFilters,
        sfwEnabled: _sfwEnabled,
      );
      await _appendImages(
        newImages,
        previousMaxScrollExtent: previousMaxScrollExtent,
      );
    } on CloudflareChallengeException catch (e) {
      kDebugPrint('Cloudflare challenge detected while fetching browse images.');
      _isLoading = false;
      _notifyChanged();

      if (remainingCloudflareRecoveries <= 0) {
        _pendingNextPageFetch = false;
        _isNextPageFetchQueued = false;
        _nextPageTriggerOffset = scrollController.hasClients
            ? scrollController.position.pixels + 1
            : double.infinity;
        return;
      }

      final result = await _showCloudflareDialog(initialUrl: e.initialUrl);
      if (result?.passed != true || _disposed) {
        _pendingNextPageFetch = false;
        _isNextPageFetchQueued = false;
        _nextPageTriggerOffset = scrollController.hasClients
            ? scrollController.position.pixels + 1
            : double.infinity;
        return;
      }

      final recoveredHtml = result?.pageHtml;
      if (recoveredHtml != null && recoveredHtml.isNotEmpty) {
        final recoveredImages = await parseBrowseImageHtml(recoveredHtml);
        await _appendImages(
          recoveredImages,
          previousMaxScrollExtent: previousMaxScrollExtent,
        );
        return;
      }

      await _fetchImages(
        pageNumber,
        isRefresh: isRefresh,
        remainingCloudflareRecoveries: remainingCloudflareRecoveries - 1,
      );
    } catch (e) {
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

  Future<void> _appendImages(
    List<Map<String, dynamic>> newImages, {
    required double previousMaxScrollExtent,
  }) async {
    final filtered =
        newImages.where((img) => !_imageUrls.contains(img['url'])).toList();
    for (final img in filtered) {
      _imageUrls.add(img['url']);
    }

    final rowProcessing = await processFaImageRows(
      newImages: filtered,
      normalImagesQueue: _normalImagesQueue,
    );
    final appendedRows = (rowProcessing['rows'] as List)
        .map(
          (row) => List<Map<String, dynamic>>.from(row as List),
        )
        .toList();
    final nextQueue =
        List<Map<String, dynamic>>.from(rowProcessing['queue'] as List);

    if (_disposed) return;

    _isError = false;
    _errorMessage = null;
    _hasMore = newImages.isNotEmpty && filtered.isNotEmpty;
    _images.addAll(filtered);
    _imageRows.addAll(appendedRows);
    _normalImagesQueue = nextQueue;
    _pendingNextPageFetch = false;
    _isNextPageFetchQueued = false;
    _isLoading = false;
    _notifyChanged();

    _scheduleNextPageTrigger(previousMaxScrollExtent: previousMaxScrollExtent);
  }

  void _scheduleNextPageTrigger({required double previousMaxScrollExtent}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
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
    if (notification.metrics.axis != Axis.vertical) return false;

    if (_disposed ||
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
    if (!_pendingNextPageFetch ||
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
    _currentPage = nextPage;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed) {
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

  Future<String> _getAllCookies() async {
    await _sfwLoadFuture;
    return _browseImageService.buildCookieHeader(
      selectedFilters: _selectedFilters,
      sfwEnabled: _sfwEnabled,
    );
  }

  Future<void> _fetchPostDetails(String uniqueNumber) async {
    final links = await _favoriteDetailsService.fetchLinksForSubmissionId(
      submissionId: uniqueNumber,
      cookieHeaderProvider: _getAllCookies,
    );
    if (links == null) return;

    if (links.hasAnyUrl) {
      if (links.hasFavUrl) _favUrls[uniqueNumber] = links.favUrl;
      if (links.hasUnfavUrl) _unfavUrls[uniqueNumber] = links.unfavUrl;
      if (links.hasUnfavUrl && !links.hasFavUrl) {
        _favoritedImages.add(uniqueNumber);
      }
      if (links.hasFavUrl && !links.hasUnfavUrl) {
        _favoritedImages.remove(uniqueNumber);
      }
    }
  }

  Future<void> _refetchFavLinks(String uniqueNumber) async {
    _favUrls[uniqueNumber] = '';
    _unfavUrls[uniqueNumber] = '';
    await _fetchPostDetails(uniqueNumber);
  }

  Future<void> toggleFavorite(String uniqueNumber, bool wantFavorite) async {
    bool hasFavUrl = _favUrls.containsKey(uniqueNumber) &&
        _favUrls[uniqueNumber]!.isNotEmpty;
    bool hasUnfavUrl = _unfavUrls.containsKey(uniqueNumber) &&
        _unfavUrls[uniqueNumber]!.isNotEmpty;
    if (!hasFavUrl && !hasUnfavUrl) {
      await _fetchPostDetails(uniqueNumber);
      hasFavUrl = _favUrls.containsKey(uniqueNumber) &&
          _favUrls[uniqueNumber]!.isNotEmpty;
      hasUnfavUrl = _unfavUrls.containsKey(uniqueNumber) &&
          _unfavUrls[uniqueNumber]!.isNotEmpty;
    }

    final isCurrentlyFav = _favoritedImages.contains(uniqueNumber);

    if (wantFavorite && isCurrentlyFav) {
      debugPrint('Already favored; skipping POST for $uniqueNumber');
      return;
    } else if (!wantFavorite && !isCurrentlyFav) {
      debugPrint('Already unfavored; skipping POST for $uniqueNumber');
      return;
    }

    final urlToUse =
        wantFavorite ? _favUrls[uniqueNumber] : _unfavUrls[uniqueNumber];
    if (urlToUse == null || urlToUse.isEmpty) {
      debugPrint(
          'DEBUG: No URL found for fav/unfav operation on $uniqueNumber.');
      return;
    }

    if (wantFavorite) {
      _favoritedImages.add(uniqueNumber);
    } else {
      _favoritedImages.remove(uniqueNumber);
    }
    _notifyChanged();

    final success = await _favoriteService.executePostWithRetry(urlToUse);
    if (success) {
      await _refetchFavLinks(uniqueNumber);
      _notifyChanged();
    } else {
      if (wantFavorite) {
        _favoritedImages.remove(uniqueNumber);
      } else {
        _favoritedImages.add(uniqueNumber);
      }
      _notifyChanged();
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
