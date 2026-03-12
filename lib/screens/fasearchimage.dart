// lib/fasearchimage.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/fa_cookie_helper.dart';
import '../services/fa_http.dart';
import '../services/favorite_service.dart';
import '../services/fa_thumbnail_processing.dart';
import '../utils/app_logging.dart';
import '../utils/content_rating_filters.dart';
import '../widgets/PulsatingLoadingIndicator.dart';
import '../widgets/heart_animation.dart';
import '../widgets/fa_thumbnail_display.dart';
import 'cloudflare_check_screen.dart';
import 'openpost.dart';

class FASearchImage extends StatefulWidget {
  final Map<String, String> selectedFilters;
  final String searchQuery;

  const FASearchImage({
    required this.selectedFilters,
    required this.searchQuery,
    Key? key,
  }) : super(key: key);

  @override
  FASearchImageState createState() => FASearchImageState();
}

class FASearchImageState extends State<FASearchImage> {
  static const double _nextPageLeadScreens = 2.5;

  int currentPage = 1;
  bool isLoading = false;
  bool hasMore = true;
  List<Map<String, dynamic>> images = [];
  List<List<Map<String, dynamic>>> imageRows = [];
  List<Map<String, dynamic>> normalImagesQueue = [];
  final Set<String> imageUrls = <String>{};
  final ScrollController _scrollController = ScrollController();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    iOptions: IOSOptions(
      accountName: 'flutter_secure_storage_service',
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );
  final FavoriteService _favoriteService = FavoriteService();

  final Set<String> _favoritedImages = {};
  final Map<String, String> _favUrls = {};
  final Map<String, String> _unfavUrls = {};

  bool _sfwEnabled = true;
  late final Future<void> _sfwLoadFuture;

  int _detailsEpoch = 0;
  final Map<String, Future<void>> _detailsInFlight = {};
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

  @override
  void didUpdateWidget(covariant FASearchImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedFilters != widget.selectedFilters ||
        oldWidget.searchQuery != widget.searchQuery) {
      _refreshImages();
    }
  }

  Future<void> _refreshImages() async {
    _detailsEpoch++;
    _detailsInFlight.clear();

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
    });
    await _fetchImages(currentPage, isRefresh: true);
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

  Uri _buildSearchUri(int pageNumber) {
    final filters = widget.selectedFilters;
    final baseQ = widget.searchQuery.trim();

    final genderQ = _buildGenderQuery(
      filters,
      useOr: (filters['mode'] ?? 'extended') == 'any',
    );

    final needsExtended = genderQ.contains('|') || genderQ.contains('"');
    final q = [baseQ, genderQ].where((s) => s.isNotEmpty).join(' ').trim();

    final queryParams = {
      'page': pageNumber.toString(),
      'q': q,
      'order-by': filters['order-by'] ?? 'relevancy',
      'order-direction': filters['order-direction'] ?? 'desc',
      'range': filters['range'] ?? '5years',
      'mode': needsExtended ? 'extended' : (filters['mode'] ?? 'extended'),
      'rating-general': filters['rating-general'] ?? '1',
      'rating-mature': filters['rating-mature'] ?? '1',
      'rating-adult': filters['rating-adult'] ?? '1',
      'type-art': filters['type-art'] ?? '1',
      'type-music': filters['type-music'] ?? '1',
      'type-flash': filters['type-flash'] ?? '1',
      'type-story': filters['type-story'] ?? '1',
      'type-photo': filters['type-photo'] ?? '1',
      'type-poetry': filters['type-poetry'] ?? '1',
      'perpage': filters['perpage'] ?? '72',
    };

    if (filters['range'] == 'manual') {
      queryParams['range_from'] = filters['range_from'] ?? '';
      queryParams['range_to'] = filters['range_to'] ?? '';
    }

    return Uri.https('www.furaffinity.net', '/search/', queryParams);
  }

  // Background WebView-based fetching has been removed.

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

    if (!mounted) return;

    setState(() {
      hasMore = newImages.isNotEmpty && filteredImages.isNotEmpty;
      images.addAll(filteredImages);
      imageRows.addAll(appendedRows);
      normalImagesQueue = nextQueue;
      _pendingNextPageFetch = false;
      _isNextPageFetchQueued = false;
      isLoading = false;
    });

    _scheduleNextPageTrigger(previousMaxScrollExtent: previousMaxScrollExtent);
  }

  Future<void> _fetchImages(
    int pageNumber, {
    bool isRefresh = false,
    int remainingCloudflareRecoveries = 2,
  }) async {
    if (isLoading || !hasMore) return;
    kDebugPrint('[Search] Fetching page $pageNumber${isRefresh ? ' (refresh)' : ''}');
    final previousMaxScrollExtent = isRefresh || !_scrollController.hasClients
        ? 0.0
        : _scrollController.position.maxScrollExtent;

    final shouldRebuildImmediately = isRefresh || imageRows.isEmpty;
    if (shouldRebuildImmediately) {
      setState(() {
        isLoading = true;
      });
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

      final newImages = await fetchImagesWithFilters(
        pageNumber,
        await _getAllCookies(),
      );
      await _appendImages(
        newImages,
        previousMaxScrollExtent: previousMaxScrollExtent,
      );
    } on _CloudflareChallengeException catch (e) {
      kDebugPrint('Cloudflare challenge detected while fetching search images.');
      if (mounted) {
        setState(() {
          _pendingNextPageFetch = false;
          _isNextPageFetchQueued = false;
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
      return;
    } catch (e) {
      kDebugPrint('Error fetching images: $e');
      setState(() {
        _pendingNextPageFetch = false;
        _isNextPageFetchQueued = false;
        isLoading = false;
      });
      _nextPageTriggerOffset = _scrollController.hasClients
          ? _scrollController.position.pixels + 1
          : double.infinity;
    }
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

  String _buildGenderQuery(Map<String, String> f, {required bool useOr}) {
    const map = {
      'male': 'male',
      'female': 'female',
      'trans_male': '"trans male"',
      'trans_female': '"trans female"',
      'intersex': 'intersex',
      'non_binary': '"non binary"',
    };

    final selected = <String>[];
    map.forEach((k, term) {
      if (f['gender-$k'] == '1') selected.add(term);
    });
    if (selected.isEmpty) return '';

    final glue = useOr ? ' | ' : ' ';
    return selected.join(glue);
  }

  Future<List<Map<String, dynamic>>> fetchImagesWithFilters(
      int pageNumber, String cookieHeader) async {
    final uri = _buildSearchUri(pageNumber);

    final response = await FAHttp.get(
      uri,
      headers: {
        HttpHeaders.cookieHeader:
            await FaCookieHelper.appendCfClearanceToCookieHeader(cookieHeader),
        'User-Agent': FAHttp.userAgent,
        'Referer': 'https://www.furaffinity.net/search/',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
      },
    );

    final refreshedCf = FaCookieHelper.extractCfClearanceFromSetCookieHeader(
      response.headers['set-cookie'],
    );
    if (refreshedCf != null && refreshedCf.isNotEmpty) {
      await FaCookieHelper.writeCfClearance(refreshedCf);
    }

    final isChallenge = FaCookieHelper.isCloudflareChallengePage(
      body: response.body,
      statusCode: response.statusCode,
    );
    if (isChallenge) {
      throw _CloudflareChallengeException(initialUrl: uri.toString());
    }

    if (response.statusCode == 200) {
      return await parseHtml(response.body);
    } else {
      throw Exception('Failed to load images: ${response.statusCode}');
    }
  }

  Future<List<Map<String, dynamic>>> parseHtml(String html) async {
    final imageMetadata = await parseFaThumbnailHtml(html);
    kDebugPrint(
      '[Search] HTML parser found ${imageMetadata.length} usable thumbnails.',
    );
    return imageMetadata;
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

  Future<void> _ensurePostDetails({
    required String uniqueNumber,
    required String postUrl,
  }) async {
    if (uniqueNumber.isEmpty || postUrl.isEmpty) return;

    final hasFav = _favUrls[uniqueNumber]?.isNotEmpty == true;
    final hasUnfav = _unfavUrls[uniqueNumber]?.isNotEmpty == true;
    if (hasFav || hasUnfav) return;

    final existing = _detailsInFlight[uniqueNumber];
    if (existing != null) {
      await existing;
      return;
    }

    final int epoch = _detailsEpoch;

    final future = () async {
      final details = await _fetchPostDetails(postUrl);
      if (!mounted) return;
      if (epoch != _detailsEpoch) return;
      if (details == null) return;

      final favUrl = details['favUrl'] ?? '';
      final unfavUrl = details['unfavUrl'] ?? '';

      setState(() {
        _favUrls[uniqueNumber] = favUrl;
        _unfavUrls[uniqueNumber] = unfavUrl;

        if (unfavUrl.isNotEmpty && favUrl.isEmpty) {
          _favoritedImages.add(uniqueNumber);
        } else if (favUrl.isNotEmpty && unfavUrl.isEmpty) {
          _favoritedImages.remove(uniqueNumber);
        } else if (unfavUrl.isNotEmpty) {
          _favoritedImages.add(uniqueNumber);
        }
      });
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
    final absolute = postUrl.startsWith('http')
        ? postUrl
        : 'https://www.furaffinity.net$postUrl';
    final cookie = await _getAllCookies();
    if (cookie.isEmpty) return null;

    try {
      final response = await FAHttp.get(
        Uri.parse(absolute),
        headers: {
          HttpHeaders.cookieHeader:
              await FaCookieHelper.appendCfClearanceToCookieHeader(cookie),
          'User-Agent': FAHttp.userAgent,
        },
      );

      if (response.statusCode != 200) return null;

      final doc = html_parser.parse(response.body);

      String? favUrl;
      String? unfavUrl;

      final favDiv = doc.querySelector('div.fav');
      if (favDiv != null) {
        final favLinks = favDiv.querySelectorAll('a');
        for (var aTag in favLinks) {
          final href = aTag.attributes['href'];
          if (href == null) continue;

          if (href.contains('/fav/')) {
            favUrl = href.startsWith('http')
                ? href
                : 'https://www.furaffinity.net$href';
          } else if (href.contains('/unfav/')) {
            unfavUrl = href.startsWith('http')
                ? href
                : 'https://www.furaffinity.net$href';
          }
        }
      }

      if ((favUrl == null || favUrl.isEmpty) &&
          (unfavUrl == null || unfavUrl.isEmpty)) {
        debugPrint('DEBUG: No fav/unfav URLs found for post: $postUrl');
      }

      return {
        'favUrl': favUrl ?? '',
        'unfavUrl': unfavUrl ?? '',
      };
    } catch (e) {
      debugPrint('Error fetching post details for $postUrl: $e');
      return null;
    }
  }

  Future<void> _toggleFavorite(String uniqueNumber, bool wantFavorite) async {
    final idx = images.indexWhere((e) => e['uniqueNumber'] == uniqueNumber);
    if (idx == -1) return;

    final postUrl = (images[idx]['postUrl'] ?? '') as String;
    if (postUrl.isEmpty) return;

    await _ensurePostDetails(uniqueNumber: uniqueNumber, postUrl: postUrl);

    final hasFav = _favUrls[uniqueNumber]?.isNotEmpty == true;
    final hasUnfav = _unfavUrls[uniqueNumber]?.isNotEmpty == true;

    if (!hasFav && !hasUnfav) {
      debugPrint('DEBUG: No fav/unfav URLs found for $uniqueNumber');
      return;
    }

    final isCurrentlyFav = _favoritedImages.contains(uniqueNumber);

    if (wantFavorite && isCurrentlyFav) {
      debugPrint('Already favored; skipping POST for $uniqueNumber');
      return;
    }
    if (!wantFavorite && !isCurrentlyFav) {
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

    setState(() {
      if (wantFavorite) {
        _favoritedImages.add(uniqueNumber);
      } else {
        _favoritedImages.remove(uniqueNumber);
      }
    });

    final success = await _favoriteService.executePostWithRetry(urlToUse);
    if (!success) {
      setState(() {
        if (wantFavorite) {
          _favoritedImages.remove(uniqueNumber);
        } else {
          _favoritedImages.add(uniqueNumber);
        }
      });
      debugPrint(
          'DEBUG: Failed to ${wantFavorite ? 'fav' : 'unfav'} $uniqueNumber.');
      return;
    }

    debugPrint(
        'DEBUG: Successfully ${wantFavorite ? 'favored' : 'unfavored'} $uniqueNumber.');

    _favUrls[uniqueNumber] = '';
    _unfavUrls[uniqueNumber] = '';
    await _ensurePostDetails(uniqueNumber: uniqueNumber, postUrl: postUrl);
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
          child: imageRows.isEmpty && isLoading
              ? Center(
                  child: PulsatingLoadingIndicator(
                    size: 88.0,
                    assetPath: 'assets/icons/fathemed.png',
                  ),
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
                      child: rowImages.length == 1
                          ? _buildSingleImage(rowImages[0], maxHeight)
                          : _buildDoubleImage(
                              rowImages[0],
                              rowImages[1],
                              maxHeight,
                            ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget _buildSingleImage(Map<String, dynamic> image, double maxHeight) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final aspectRatio = image['width'] / image['height'];
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
            child: _FavSearchTile(
              item: image,
              width: width,
              height: height,
              isFavorited: _favoritedImages.contains(image['uniqueNumber']),
              onFinalFavState: (finalVal) =>
                  _toggleFavorite(image['uniqueNumber'], finalVal),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OpenPost(
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
      Map<String, dynamic> left, Map<String, dynamic> right, double maxHeight) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const margin = 4.0;
        final rowWidth = constraints.maxWidth - margin;
        final aspect1 = left['width'] / left['height'];
        final aspect2 = right['width'] / right['height'];
        final ratio = aspect2 / aspect1;

        double wL = rowWidth / (1 + ratio);
        double wR = rowWidth - wL;
        double h = wL / aspect1;
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
            _FavSearchTile(
              item: left,
              width: wL,
              height: h,
              isFavorited: _favoritedImages.contains(left['uniqueNumber']),
              onFinalFavState: (finalVal) =>
                  _toggleFavorite(left['uniqueNumber'], finalVal),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OpenPost(
                      imageUrl: left['url'],
                      uniqueNumber: left['uniqueNumber'],
                      skipInitialWatchCheck: true,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: margin),
            _FavSearchTile(
              item: right,
              width: wR,
              height: h,
              isFavorited: _favoritedImages.contains(right['uniqueNumber']),
              onFinalFavState: (finalVal) =>
                  _toggleFavorite(right['uniqueNumber'], finalVal),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OpenPost(
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

class _FavSearchTile extends StatefulWidget {
  final Map<String, dynamic> item;
  final double width;
  final double height;
  final bool isFavorited;
  final ValueChanged<bool> onFinalFavState;
  final VoidCallback onTap;

  const _FavSearchTile({
    Key? key,
    required this.item,
    required this.width,
    required this.height,
    required this.isFavorited,
    required this.onFinalFavState,
    required this.onTap,
  }) : super(key: key);

  @override
  State<_FavSearchTile> createState() => _FavSearchTileState();
}

class _FavSearchTileState extends State<_FavSearchTile> {
  late bool _localFav;

  @override
  void initState() {
    super.initState();
    _localFav = widget.isFavorited;
  }

  @override
  void didUpdateWidget(covariant _FavSearchTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isFavorited != widget.isFavorited) {
      setState(() => _localFav = widget.isFavorited);
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = widget.item['url'] as String;
    final String? rating = widget.item['rating'] as String?;
    final String? title = widget.item['title'] as String?;
    final String? author = widget.item['author'] as String?;

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
              widget.onFinalFavState(finalVal);
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
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      width: widget.width,
                      height: widget.height,
                      color: Colors.grey[300],
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
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
