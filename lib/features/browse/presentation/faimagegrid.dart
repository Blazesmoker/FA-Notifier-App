// lib/fa_image_grid.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:html/parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:FANotifier/shared/fa/fa_cookie_helper.dart';
import 'package:FANotifier/shared/fa/fa_http.dart';
import 'package:FANotifier/features/submissions/data/favorite_service.dart';
import 'package:FANotifier/shared/fa/fa_thumbnail_processing.dart';
import 'package:FANotifier/core/logging/app_logging.dart';
import 'package:FANotifier/shared/utils/content_rating_filters.dart';
import 'package:FANotifier/shared/widgets/PulsatingLoadingIndicator.dart';
import 'package:FANotifier/shared/widgets/heart_animation.dart';
import 'package:FANotifier/shared/widgets/fa_thumbnail_display.dart';
import 'package:FANotifier/features/auth/presentation/cloudflare_check_screen.dart';
import 'package:FANotifier/features/submissions/presentation/openpost.dart';

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

      final cookieHeader = await _getAllCookies();
      final uri = Uri.parse('https://www.furaffinity.net/browse/$pageNumber');
      Uri currentUri = uri;

      final headers = {
        HttpHeaders.cookieHeader:
            await FaCookieHelper.appendCfClearanceToCookieHeader(cookieHeader),
        'User-Agent': FAHttp.userAgent,
        'Referer': 'https://www.furaffinity.net/browse/',
        'Content-Type': 'application/x-www-form-urlencoded',
      };

      final body = {
        'cat': getFilterValue('Category'),
        'atype': getFilterValue('Type'),
        'species': getFilterValue('Species'),
        'gender': getFilterValue('Gender'),
        'rating_general': getFilterValue('rating-general'),
        'rating_mature': getFilterValue('rating-mature'),
        'rating_adult': getFilterValue('rating-adult'),
        'perpage': '72',
        'btn': 'Next',
      };

      var resp = await FAHttp.post(uri, headers: headers, body: body);

      if (resp.isRedirect ||
          (resp.statusCode >= 300 && resp.statusCode < 400)) {
        final loc = resp.headers['location'];
        if (loc == null || loc.isEmpty) {
          throw Exception('Redirect without Location header');
        }
        final redirectUri = uri.resolve(loc);
        currentUri = redirectUri;
        resp = await FAHttp.get(
          redirectUri,
          headers: {
            HttpHeaders.cookieHeader:
                await FaCookieHelper.appendCfClearanceToCookieHeader(
                    cookieHeader),
            'User-Agent': FAHttp.userAgent,
            'Referer': uri.toString(),
          },
        );
      }

      final refreshedCf = FaCookieHelper.extractCfClearanceFromSetCookieHeader(
        resp.headers['set-cookie'],
      );
      if (refreshedCf != null && refreshedCf.isNotEmpty) {
        await FaCookieHelper.writeCfClearance(refreshedCf);
      }

      final isChallenge = FaCookieHelper.isCloudflareChallengePage(
        body: resp.body,
        statusCode: resp.statusCode,
      );
      if (isChallenge) {
        throw _CloudflareChallengeException(initialUrl: currentUri.toString());
      }

      if (resp.statusCode == 200) {
        final newImages = await parseHtml(resp.body);
        await _appendImages(
          newImages,
          previousMaxScrollExtent: previousMaxScrollExtent,
        );
      } else {
        setState(() => isLoading = false);
        throw Exception(
            'FAImageGrid: HTTP ${resp.statusCode} fetching images.');
      }
    } on _CloudflareChallengeException catch (e) {
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
        final recoveredImages = await parseHtml(recoveredHtml);
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
    final cookieNames = [
      'a',
      'b',
      'cc',
      'cf_clearance',
      'folder',
      'nodesc',
      'sz'
    ];
    final cookies = <String>[];
    for (var name in cookieNames) {
      final storageKey = 'fa_cookie_$name';
      final value = await _secureStorage.read(key: storageKey);
      if (value != null && value.isNotEmpty) {
        cookies.add('$name=$value');
      }
    }
    cookies.add(
      'sfw=${ContentRatingFilters.effectiveSfwCookieValue(globalSfwEnabled: _sfwEnabled, filters: widget.selectedFilters)}',
    );
    return cookies.join('; ');
  }

  String getFilterValue(String filterName) {
    return widget.selectedFilters[filterName] ?? '1';
  }

  /// Parses the browse page HTML for the thumbnail images
  Future<List<Map<String, dynamic>>> parseHtml(String html) async {
    final imageMetadata = await parseFaThumbnailHtml(html);
    kDebugPrint(
      '[Browse] HTML parser found ${imageMetadata.length} usable thumbnails.',
    );
    return imageMetadata;
  }

  /// Fetch post details (like /fav/ or /unfav/ links) for [uniqueNumber].
  /// Also updates _favoritedImages if the post page indicates it's already faved.
  Future<void> _fetchPostDetails(String uniqueNumber) async {
    final postUrl = 'https://www.furaffinity.net/view/$uniqueNumber/';
    try {
      final cookieHeader = await _getAllCookies();
      final response = await FAHttp.get(
        Uri.parse(postUrl),
        headers: {
          HttpHeaders.cookieHeader:
              await FaCookieHelper.appendCfClearanceToCookieHeader(
                  cookieHeader),
          'User-Agent': FAHttp.userAgent,
        },
      );
      if (response.statusCode == 200) {
        final doc = parse(response.body);
        final favDiv = doc.querySelector('div.fav');
        if (favDiv != null) {
          final anchors = favDiv.querySelectorAll('a');
          bool foundFav = false;
          bool foundUnfav = false;

          for (var aTag in anchors) {
            final href = aTag.attributes['href'] ?? '';
            if (href.contains('/fav/')) {
              _favUrls[uniqueNumber] = href.startsWith('http')
                  ? href
                  : 'https://www.furaffinity.net$href';
              foundFav = true;
            } else if (href.contains('/unfav/')) {
              _unfavUrls[uniqueNumber] = href.startsWith('http')
                  ? href
                  : 'https://www.furaffinity.net$href';
              foundUnfav = true;
            }
          }

          // If only an unfav link is present, user is already faved
          if (foundUnfav && !foundFav) {
            _favoritedImages.add(uniqueNumber);
          }
          // If only a fav link is present, user is not yet faved
          if (foundFav && !foundUnfav) {
            _favoritedImages.remove(uniqueNumber);
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching post details for $uniqueNumber => $e');
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
                  MaterialPageRoute(
                    builder: (context) => OpenPost(
                      imageUrl: image['url'],
                      uniqueNumber: image['uniqueNumber'],
                      skipInitialWatchCheck: true,
                    ),
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
                  MaterialPageRoute(
                    builder: (context) => OpenPost(
                      imageUrl: left['url'],
                      uniqueNumber: left['uniqueNumber'],
                      skipInitialWatchCheck: true,
                    ),
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
                  MaterialPageRoute(
                    builder: (context) => OpenPost(
                      imageUrl: right['url'],
                      uniqueNumber: right['uniqueNumber'],
                      skipInitialWatchCheck: true,
                    ),
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

class _CloudflareChallengeException implements Exception {
  final String? initialUrl;

  const _CloudflareChallengeException({this.initialUrl});
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
          ),
        ],
      ),
    );
  }
}
