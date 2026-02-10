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
import '../services/fa_thumbnail_parser.dart';
import '../widgets/PulsatingLoadingIndicator.dart';
import '../widgets/heart_animation.dart';
import '../widgets/fa_thumbnail_display.dart';
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
  int currentPage = 1;
  bool isLoading = false;
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

  int _detailsEpoch = 0;
  final Map<String, Future<void>> _detailsInFlight = {};

  @override
  void initState() {
    super.initState();
    _loadSfwEnabled();
    _fetchImages(currentPage);
    _scrollController.addListener(_scrollListener);
  }

  Future<void> _loadSfwEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _sfwEnabled = prefs.getBool('sfwEnabled') ?? true;
    });
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
      _favoritedImages.clear();
      _favUrls.clear();
      _unfavUrls.clear();
    });
    await _fetchImages(currentPage, isRefresh: true);
  }

  Future<String> _getAllCookies() async {
    final cookieNames = ['a', 'b', 'cc', 'cf_clearance', 'folder', 'nodesc', 'sz'];
    final cookies = <String>[];

    for (var name in cookieNames) {
      final storageKey = 'fa_cookie_$name';
      final value = await _secureStorage.read(key: storageKey);
      if (value != null && value.isNotEmpty) {
        cookies.add('$name=$value');
      }
    }

    cookies.add('sfw=${_sfwEnabled ? '1' : '0'}');
    return cookies.join('; ');
  }

  Future<void> _fetchImages(int pageNumber, {bool isRefresh = false}) async {
    setState(() {
      isLoading = true;
    });
    try {
      if (isRefresh) {
        images.clear();
        imageUrls.clear();
        imageRows.clear();
        normalImagesQueue.clear();
        currentPage = 1;
      }

      final cookieHeader = await _getAllCookies();

      final newImages = await fetchImagesWithFilters(pageNumber, cookieHeader);
      final filteredImages =
      newImages.where((image) => !imageUrls.contains(image['url'])).toList();

      for (var image in filteredImages) {
        imageUrls.add(image['url']);
      }

      setState(() {
        images.addAll(filteredImages);
        _processImagesIntoRows(filteredImages);
        _preloadImagesImmediately(filteredImages);
        isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching images: $e');
      setState(() {
        isLoading = false;
      });
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
    final filters = widget.selectedFilters;
    final baseQ = (widget.searchQuery).trim();

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

    final uri = Uri.https('www.furaffinity.net', '/search/', queryParams);

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

    if (response.statusCode == 200) {
      return await parseHtml(response.body);
    } else {
      throw Exception('Failed to load images: ${response.statusCode}');
    }
  }

  Future<List<Map<String, dynamic>>> parseHtml(String html) async {
    final document = html_parser.parse(html);
    final figures = FaThumbnailParser.selectThumbnailFigures(document);
    final imageMetadata = <Map<String, dynamic>>[];

    for (final fig in figures) {
      final data = FaThumbnailParser.extract(fig);
      if (data == null) continue;
      imageMetadata.add({
        'url': data['thumbnailUrl'],
        'width': data['width'],
        'height': data['height'],
        'postUrl': data['postUrl'],
        'uniqueNumber': data['uniqueNumber'],
        'rating': data['rating'],
        'title': data['title'],
        'author': data['author'],
      });
    }

    return imageMetadata;
  }

  bool isWideImage(Map<String, dynamic> image) {
    final width = image['width'];
    final height = image['height'];
    final aspectRatio = width / height;
    return aspectRatio > 1.5;
  }

  void _processImagesIntoRows(List<Map<String, dynamic>> newImages) {
    for (var image in newImages) {
      if (isWideImage(image)) {
        if (normalImagesQueue.isNotEmpty) {
          imageRows.add([normalImagesQueue.removeAt(0), image]);
        } else {
          imageRows.add([image]);
        }
      } else {
        normalImagesQueue.add(image);
      }
    }

    while (normalImagesQueue.length >= 2) {
      imageRows.add([normalImagesQueue.removeAt(0), normalImagesQueue.removeAt(0)]);
    }

    if (normalImagesQueue.isNotEmpty) {
      imageRows.add([normalImagesQueue.removeAt(0)]);
    }
  }

  void _preloadImagesImmediately(List<Map<String, dynamic>> fetchedImages) {
    for (var image in fetchedImages) {
      precacheImage(NetworkImage(image['url']), context);
    }
  }

  void _scrollListener() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.4 &&
        !isLoading) {
      currentPage++;
      _fetchImages(currentPage);
    }
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
    final absolute =
    postUrl.startsWith('http') ? postUrl : 'https://www.furaffinity.net$postUrl';
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

    final urlToUse = wantFavorite ? _favUrls[uniqueNumber] : _unfavUrls[uniqueNumber];
    if (urlToUse == null || urlToUse.isEmpty) {
      debugPrint('DEBUG: No URL found for fav/unfav operation on $uniqueNumber.');
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
      debugPrint('DEBUG: Failed to ${wantFavorite ? 'fav' : 'unfav'} $uniqueNumber.');
      return;
    }

    debugPrint('DEBUG: Successfully ${wantFavorite ? 'favored' : 'unfavored'} $uniqueNumber.');

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
          controller: _scrollController,
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
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: rowImages.length == 1
                  ? _buildSingleImage(rowImages[0], maxHeight)
                  : _buildDoubleImage(rowImages[0], rowImages[1], maxHeight),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSingleImage(Map<String, dynamic> image, double maxHeight) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final aspectRatio = image['width'] / image['height'];
        final rowWidth = constraints.maxWidth - 16.0;
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
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8.0),
                    child: Image.network(
                      imageUrl,
                      width: widget.width,
                      height: widget.height,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return buildEmptyPlaceholder(widget.width, widget.height);
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return buildEmptyPlaceholder(widget.width, widget.height);
                      },
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: AnimatedOpacity(
                      opacity: _localFav ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(Icons.favorite, color: Colors.redAccent, size: 24),
                    ),
                  ),
                ],
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

  Widget buildEmptyPlaceholder(double width, double height) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(8.0),
      ),
    );
  }
}
