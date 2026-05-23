// lib/fa_image_grid.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:FANotifier/features/browse/data/browse_image_parser.dart';
import 'package:FANotifier/features/browse/data/browse_image_service.dart';
import 'package:FANotifier/shared/fa/cloudflare_challenge_exception.dart';
import 'package:FANotifier/features/submissions/data/submission_favorite_details_service.dart';
import 'package:FANotifier/features/submissions/data/favorite_service.dart';
import 'package:FANotifier/shared/fa/fa_thumbnail_processing.dart';
import 'package:FANotifier/core/logging/app_logging.dart';
import 'package:FANotifier/shared/widgets/PulsatingLoadingIndicator.dart';
import 'package:FANotifier/shared/widgets/heart_animation.dart';
import 'package:FANotifier/shared/widgets/fa_thumbnail_display.dart';
import 'package:FANotifier/features/auth/presentation/cloudflare_check_screen.dart';
import 'package:FANotifier/features/submissions/presentation/openpost.dart';

import '../../auth/domain/cloudflare_check_result.dart';

class FAImageGrid extends StatefulWidget {
  final Map<String, String> selectedFilters;
  const FAImageGrid({required this.selectedFilters, Key? key})
      : super(key: key);

  @override
  FAImageGridState createState() => FAImageGridState();
}

class FAImageGridState extends State<FAImageGrid> {
  static const double _nextPageLeadScreens = 2.5;

  int currentPage = 1;
  bool isLoading = false;
  bool hasMore = true;

  bool _isError = false;
  String? _errorMessage;

  /// Each image is a Map with:
  ///   - 'url': thumbnail URL
  ///   - 'width': double
  ///   - 'height': double
  ///   - 'uniqueNumber': string
  List<Map<String, dynamic>> images = [];
  List<List<Map<String, dynamic>>> imageRows = [];
  List<Map<String, dynamic>> normalImagesQueue = [];

  final Set<String> imageUrls = <String>{}; // For de-duping
  final ScrollController _scrollController = ScrollController();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    iOptions: IOSOptions(
      accountName: 'flutter_secure_storage_service',
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  final Set<String> _favoritedImages = {};
  final Map<String, String> _favUrls = {};
  final Map<String, String> _unfavUrls = {};
  late final BrowseImageService _browseImageService;
  final SubmissionFavoriteDetailsService _favoriteDetailsService =
      const SubmissionFavoriteDetailsService();
  final FavoriteService _favoriteService = FavoriteService();

  bool _sfwEnabled = true;
  late final Future<void> _sfwLoadFuture;
  bool _isHandlingCloudflareChallenge = false;
  double _nextPageTriggerOffset = double.infinity;
  bool _pendingNextPageFetch = false;
  bool _isNextPageFetchQueued = false;

  @override
  void initState() {
    super.initState();
    _browseImageService = BrowseImageService(secureStorage: _secureStorage);
    _sfwLoadFuture = _loadSfwEnabled();
    _fetchImages(currentPage);
    _scrollController.addListener(_scrollListener);
  }

  Future<void> _loadSfwEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    _sfwEnabled = prefs.getBool('sfwEnabled') ?? true;
  }

  @override
  void didUpdateWidget(covariant FAImageGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedFilters != widget.selectedFilters) {
      _refreshImages();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> scrollToTop({bool animate = true}) async {
    if (!_scrollController.hasClients) return;
    if (!animate) {
      _scrollController.jumpTo(0);
      return;
    }
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _scrollListener() {
    if (!_scrollController.hasClients ||
        isLoading ||
        _isNextPageFetchQueued ||
        !hasMore ||
        _isHandlingCloudflareChallenge) {
      return;
    }

    if (!_hasReachedNextPageTrigger(_scrollController.position)) {
      return;
    }

    _pendingNextPageFetch = true;
    _tryStartPendingNextPageFetch();
  }

  Future<void> _refreshImages() async {
    setState(() {
      images.clear();
      imageUrls.clear();
      imageRows.clear();
      normalImagesQueue.clear();
      currentPage = 1;
      hasMore = true;
      _nextPageTriggerOffset = double.infinity;
      _pendingNextPageFetch = false;
      _isNextPageFetchQueued = false;
      _favoritedImages.clear();
      _favUrls.clear();
      _unfavUrls.clear();
      _isError = false;
      _errorMessage = null;
    });
    await _fetchImages(currentPage, isRefresh: true);
  }

  Future<void> _fetchImages(
    int pageNumber, {
    bool isRefresh = false,
    int remainingCloudflareRecoveries = 2,
  }) async {
    if (isLoading || !hasMore) return;
    kDebugPrint('[Browse] Fetching page $pageNumber${isRefresh ? ' (refresh)' : ''}');
    final previousMaxScrollExtent = isRefresh || !_scrollController.hasClients
        ? 0.0
        : _scrollController.position.maxScrollExtent;
    final shouldRebuildImmediately = isRefresh || imageRows.isEmpty;
    if (shouldRebuildImmediately) {
      setState(() => isLoading = true);
    } else {
      isLoading = true;
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

      await _sfwLoadFuture;
      final newImages = await _browseImageService.fetchImages(
        pageNumber: pageNumber,
        selectedFilters: widget.selectedFilters,
        sfwEnabled: _sfwEnabled,
      );
      await _appendImages(
        newImages,
        previousMaxScrollExtent: previousMaxScrollExtent,
      );
    } on CloudflareChallengeException catch (e) {
      kDebugPrint('Cloudflare challenge detected while fetching browse images.');
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }

      if (remainingCloudflareRecoveries <= 0) {
        _pendingNextPageFetch = false;
        _isNextPageFetchQueued = false;
        _nextPageTriggerOffset = _scrollController.hasClients
            ? _scrollController.position.pixels + 1
            : double.infinity;
        return;
      }

      final result = await _showCloudflareDialog(initialUrl: e.initialUrl);
      if (result?.passed != true || !mounted) {
        _pendingNextPageFetch = false;
        _isNextPageFetchQueued = false;
        _nextPageTriggerOffset = _scrollController.hasClients
            ? _scrollController.position.pixels + 1
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
      setState(() {
        _pendingNextPageFetch = false;
        _isNextPageFetchQueued = false;
        isLoading = false;
        _isError = true;
        _errorMessage = e.toString();
      });
      kDebugPrint('FAImageGrid: Error fetching images => $e');
      _nextPageTriggerOffset = _scrollController.hasClients
          ? _scrollController.position.pixels + 1
          : double.infinity;
    }
  }

  Future<void> _appendImages(
    List<Map<String, dynamic>> newImages, {
    required double previousMaxScrollExtent,
  }) async {
    final filtered =
        newImages.where((img) => !imageUrls.contains(img['url'])).toList();
    for (final img in filtered) {
      imageUrls.add(img['url']);
    }

    final rowProcessing = await processFaImageRows(
      newImages: filtered,
      normalImagesQueue: normalImagesQueue,
    );
    final appendedRows = (rowProcessing['rows'] as List)
        .map(
          (row) => List<Map<String, dynamic>>.from(row as List),
        )
        .toList();
    final nextQueue =
        List<Map<String, dynamic>>.from(rowProcessing['queue'] as List);

    if (!mounted) return;

    setState(() {
      _isError = false;
      _errorMessage = null;
      hasMore = newImages.isNotEmpty && filtered.isNotEmpty;
      images.addAll(filtered);
      imageRows.addAll(appendedRows);
      normalImagesQueue = nextQueue;
      _pendingNextPageFetch = false;
      _isNextPageFetchQueued = false;
      isLoading = false;
    });

    _scheduleNextPageTrigger(previousMaxScrollExtent: previousMaxScrollExtent);
  }

  void _scheduleNextPageTrigger({required double previousMaxScrollExtent}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !hasMore) {
        _pendingNextPageFetch = false;
        _isNextPageFetchQueued = false;
        _nextPageTriggerOffset = double.infinity;
        return;
      }

      if (!_scrollController.hasClients) {
        _scheduleNextPageTrigger(
          previousMaxScrollExtent: previousMaxScrollExtent,
        );
        return;
      }

      final newMaxScrollExtent = _scrollController.position.maxScrollExtent;
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

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;

    if (!mounted ||
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
        !_scrollController.hasClients ||
        isLoading ||
        _isNextPageFetchQueued ||
        !hasMore ||
        _isHandlingCloudflareChallenge) {
      return;
    }
    if (!_hasReachedNextPageTrigger(_scrollController.position)) {
      return;
    }

    _pendingNextPageFetch = false;
    _isNextPageFetchQueued = true;
    _nextPageTriggerOffset = double.infinity;
    final nextPage = currentPage + 1;
    currentPage = nextPage;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
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
    if (!mounted || _isHandlingCloudflareChallenge) return null;
    _isHandlingCloudflareChallenge = true;
    try {
      return await showDialog<CloudflareCheckResult>(
        context: context,
        barrierDismissible: false,
        useSafeArea: false,
        builder: (_) => CloudflareCheckScreen(
          initialUrl: initialUrl ?? 'https://www.furaffinity.net/',
          returnPageHtml: true,
        ),
      );
    } finally {
      _isHandlingCloudflareChallenge = false;
    }
  }

  Future<String> _getAllCookies() async {
    await _sfwLoadFuture;
    return _browseImageService.buildCookieHeader(
      selectedFilters: widget.selectedFilters,
      sfwEnabled: _sfwEnabled,
    );
  }

  /// Fetch post details (like /fav/ or /unfav/ links) for [uniqueNumber].
  /// Also updates _favoritedImages if the post page indicates it's already faved.
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

  /// Clears old links, re-fetches, and updates _favoritedImages.
  Future<void> _refetchFavLinks(String uniqueNumber) async {
    _favUrls[uniqueNumber] = '';
    _unfavUrls[uniqueNumber] = '';
    await _fetchPostDetails(uniqueNumber);
  }

  Future<void> _toggleFavorite(String uniqueNumber, bool wantFavorite) async {
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

    // optimistic UI
    if (wantFavorite) {
      _favoritedImages.add(uniqueNumber);
    } else {
      _favoritedImages.remove(uniqueNumber);
    }
    setState(() {});

    final success = await _favoriteService.executePostWithRetry(urlToUse);
    if (success) {
      await _refetchFavLinks(
          uniqueNumber); // re-parse the page to see updated state
      setState(() {});
    } else {
      // rollback
      if (wantFavorite) {
        _favoritedImages.remove(uniqueNumber);
      } else {
        _favoritedImages.add(uniqueNumber);
      }
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = screenHeight * 0.4;

    return RefreshIndicator(
      onRefresh: _refreshImages,
      child: NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
          child: imageRows.isEmpty
              ? ListView(
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
                        child: Text(
                          _isError
                              ? 'Network error. Pull to retry.'
                              : 'No results. Pull to refresh.',
                        ),
                      ),
                    if (!isLoading && _errorMessage != null)
                      const SizedBox(height: 8),
                    if (!isLoading && _errorMessage != null)
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12),
                      ),
                  ],
                )
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics()),
                  controller: _scrollController,
                  cacheExtent: screenHeight * 1.5,
                  itemCount: imageRows.length + (isLoading ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == imageRows.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Center(
                          child: PulsatingLoadingIndicator(
                            size: 58.0,
                            assetPath: 'assets/icons/fathemed.png',
                          ),
                        ),
                      );
                    }

                    final rowImages = imageRows[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2.0),
                      child: _buildImageRow(rowImages, maxHeight),
                    );
                  },
                ),
        ),
      ),
    );
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
              isFav: _favoritedImages.contains(image['uniqueNumber']),
              onToggle: (wantFav) =>
                  _toggleFavorite(image['uniqueNumber'], wantFav),
              onTap: () {
                Navigator.push(
                  context,
                  OpenPost.route(
                    imageUrl: image['url'],
                    uniqueNumber: image['uniqueNumber'],
                    skipInitialWatchCheck: true,
                  ),
                );
              },
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
              isFav: _favoritedImages.contains(left['uniqueNumber']),
              onToggle: (wantFav) =>
                  _toggleFavorite(left['uniqueNumber'], wantFav),
              onTap: () {
                Navigator.push(
                  context,
                  OpenPost.route(
                    imageUrl: left['url'],
                    uniqueNumber: left['uniqueNumber'],
                    skipInitialWatchCheck: true,
                  ),
                );
              },
            ),
            const SizedBox(width: margin),
            _FavImageTile(
              image: right,
              width: wR,
              height: h,
              isFav: _favoritedImages.contains(right['uniqueNumber']),
              onToggle: (wantFav) =>
                  _toggleFavorite(right['uniqueNumber'], wantFav),
              onTap: () {
                Navigator.push(
                  context,
                  OpenPost.route(
                    imageUrl: right['url'],
                    uniqueNumber: right['uniqueNumber'],
                    skipInitialWatchCheck: true,
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _FavImageTile extends StatefulWidget {
  final Map<String, dynamic> image;
  final double width;
  final double height;
  final bool isFav;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;

  const _FavImageTile({
    Key? key,
    required this.image,
    required this.width,
    required this.height,
    required this.isFav,
    required this.onToggle,
    required this.onTap,
  }) : super(key: key);

  @override
  State<_FavImageTile> createState() => _FavImageTileState();
}

class _FavImageTileState extends State<_FavImageTile> {
  late bool _localFav;

  @override
  void initState() {
    super.initState();
    _localFav = widget.isFav;
  }

  @override
  void didUpdateWidget(covariant _FavImageTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isFav != widget.isFav) {
      setState(() => _localFav = widget.isFav);
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = widget.image['url'];
    final String? rating = widget.image['rating'] as String?;
    final String? title = widget.image['title'] as String?;
    final String? author = widget.image['author'] as String?;
    final String? authorProfileUrl = widget.image['authorProfileUrl'] as String?;

    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: () {
        setState(() => _localFav = !_localFav);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HeartAnimationWidget(
            isFavorite: _localFav,
            containerWidth: widget.width,
            containerHeight: widget.height,
            onDebounceComplete: (finalVal) {
              widget.onToggle(finalVal);
            },
            debounceDuration: const Duration(seconds: 3),
            child: FaThumbnailOutline(
              rating: rating,
              borderRadius: 8.0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8.0),
                child: Image.network(
                  imageUrl,
                  width: widget.width,
                  height: widget.height,
                  fit: BoxFit.cover,
                  loadingBuilder: (ctx, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      width: widget.width,
                      height: widget.height,
                      color: Colors.grey[300],
                    );
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
