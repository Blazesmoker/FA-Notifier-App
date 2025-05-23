import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:html/parser.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:collection';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/PulsatingLoadingIndicator.dart';
import 'openpost.dart';
import '../services/favorite_service.dart';
import '../widgets/heart_animation.dart';


class _ParseResult {
  final List<Map<String, dynamic>> posts;
  final String? nextPageUrl;
  _ParseResult({required this.posts, this.nextPageUrl});
}

class ProfileScrapsSliver extends StatefulWidget {
  final String username;

  const ProfileScrapsSliver({required this.username, Key? key}) : super(key: key);

  @override
  _ProfileScrapsSliverState createState() => _ProfileScrapsSliverState();
}

class _ProfileScrapsSliverState extends State<ProfileScrapsSliver> {
  String? _nextPageUrl;
  bool _isLoading = false;
  bool _hasMore = true;


  final List<Map<String, dynamic>> _images = [];

  final List<List<Map<String, dynamic>>> _imageRows = [];
  final List<Map<String, dynamic>> _normalImagesQueue = [];

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  // Favorite functionality
  final Set<String> _favoritedImages = {};
  final Map<String, String> _favUrls = {};
  final Map<String, String> _unfavUrls = {};
  final FavoriteService _favoriteService = FavoriteService();

  @override
  void initState() {
    super.initState();
    // Set the initial URL for scraps pagination:
    _nextPageUrl = 'https://www.furaffinity.net/scraps/${widget.username}/';
    _fetchImages();
  }


  Future<String> _getSfwCookieValue() async {
    final prefs = await SharedPreferences.getInstance();
    final sfwEnabled = prefs.getBool('sfwEnabled') ?? true;
    return sfwEnabled ? '1' : '0';
  }


  Future<String> _getAllCookies() async {
    final cookieNames = [
      'a',
      'b',
      'cc',
      'folder',
      'nodesc',
      'sz',
      'sfw',
    ];
    final cookies = <String>[];
    for (final name in cookieNames) {
      if (name == 'sfw') {
        final sfwValue = await _getSfwCookieValue();
        cookies.add('sfw=$sfwValue');
      } else {
        final storageKey = 'fa_cookie_$name';
        final value = await _secureStorage.read(key: storageKey);
        if (value != null && value.isNotEmpty) {
          cookies.add('$name=$value');
        }
      }
    }
    return cookies.join('; ');
  }

  Future<void> _fetchImages() async {
    if (_isLoading || _nextPageUrl == null) return;
    setState(() => _isLoading = true);

    try {
      final result = await _fetchScrapsPage(_nextPageUrl!);
      setState(() {
        _images.addAll(result.posts);
        _processImagesIntoRows(result.posts);
        _preloadImagesImmediately(result.posts);

        _nextPageUrl = result.nextPageUrl;
        _hasMore = result.nextPageUrl != null;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint("Error fetching scraps: $e");
    }
  }

  Future<_ParseResult> _fetchScrapsPage(String url) async {
    final cookieHeader = await _getAllCookies();
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Cookie': cookieHeader,
        'User-Agent': 'Mozilla/5.0',
        'Referer': 'https://www.furaffinity.net',
      },
    );
    if (response.statusCode != 200) {
      throw Exception("Failed to load scraps: ${response.statusCode}");
    }

    final decodedBody = utf8.decode(response.bodyBytes, allowMalformed: true);
    return _parseScrapsHtml(decodedBody, url);
  }

  _ParseResult _parseScrapsHtml(String html, String currentUrl) {
    final document = parse(html);
    final imageElements = document.querySelectorAll('figure.t-image');

    // Determine next page
    String? nextPageUrl;
    for (var form in document.querySelectorAll('form')) {
      var button = form.querySelector('button[type="submit"]');
      if (button != null && button.text.trim().toLowerCase() == 'next') {
        final action = form.attributes['action'];
        if (action != null && action.isNotEmpty) {
          final nextUri = Uri.parse(currentUrl).resolve(action);
          nextPageUrl = nextUri.toString();
          break;
        }
      }
    }

    final posts = <Map<String, dynamic>>[];
    for (var element in imageElements) {
      final thumbUrl = element.querySelector('img')?.attributes['src'];
      final wStr = element.querySelector('img')?.attributes['data-width'];
      final hStr = element.querySelector('img')?.attributes['data-height'];
      if (thumbUrl != null && wStr != null && hStr != null) {
        final w = double.tryParse(wStr);
        final h = double.tryParse(hStr);
        if (w != null && h != null) {
          final match = RegExp(r'/(\d+)@').firstMatch(thumbUrl);
          final un = match != null
              ? match.group(1)!
              : DateTime.now().millisecondsSinceEpoch.toString();

          posts.add({
            'url': 'https:$thumbUrl',
            'width': w,
            'height': h,
            'uniqueNumber': un,
          });
        }
      }
    }
    return _ParseResult(posts: posts, nextPageUrl: nextPageUrl);
  }

  // Build row data
  bool _isWideImage(Map<String, dynamic> img) {
    final w = img['width'] as double;
    final h = img['height'] as double;
    return (w / h) > 1.5;
  }

  void _processImagesIntoRows(List<Map<String, dynamic>> newImages) {
    for (var image in newImages) {
      if (_isWideImage(image)) {
        if (_normalImagesQueue.isNotEmpty) {
          _imageRows.add([_normalImagesQueue.removeAt(0), image]);
        } else {
          _imageRows.add([image]);
        }
      } else {
        _normalImagesQueue.add(image);
      }
    }
    while (_normalImagesQueue.length >= 2) {
      _imageRows.add([
        _normalImagesQueue.removeAt(0),
        _normalImagesQueue.removeAt(0),
      ]);
    }
    if (_normalImagesQueue.isNotEmpty) {
      _imageRows.add([_normalImagesQueue.removeAt(0)]);
    }
  }

  void _preloadImagesImmediately(List<Map<String, dynamic>> fetchedImages) {
    for (var image in fetchedImages) {
      precacheImage(NetworkImage(image['url']), context);
    }
  }

  // Favorite logic
  Future<void> _fetchPostDetails(String uniqueNumber) async {
    final postUrl = 'https://www.furaffinity.net/view/$uniqueNumber/';
    try {
      final cookieHeader = await _getAllCookies();
      final response = await http.get(
        Uri.parse(postUrl),
        headers: {
          'Cookie': cookieHeader,
          'User-Agent': 'Mozilla/5.0',
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

          if (foundUnfav && !foundFav) {
            _favoritedImages.add(uniqueNumber);
          }
          if (foundFav && !foundUnfav) {
            _favoritedImages.remove(uniqueNumber);
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching post details for $uniqueNumber => $e');
    }
  }

  Future<void> _refetchFavLinks(String uniqueNumber) async {
    _favUrls[uniqueNumber] = '';
    _unfavUrls[uniqueNumber] = '';
    await _fetchPostDetails(uniqueNumber);
  }

  Future<void> _toggleFavorite(String uniqueNumber, bool wantFavorite) async {
    bool hasFavUrl = _favUrls[uniqueNumber]?.isNotEmpty ?? false;
    bool hasUnfavUrl = _unfavUrls[uniqueNumber]?.isNotEmpty ?? false;


    if (!hasFavUrl && !hasUnfavUrl) {
      await _fetchPostDetails(uniqueNumber);
      hasFavUrl = _favUrls[uniqueNumber]?.isNotEmpty ?? false;
      hasUnfavUrl = _unfavUrls[uniqueNumber]?.isNotEmpty ?? false;
    }

    final isCurrentlyFav = _favoritedImages.contains(uniqueNumber);
    if (wantFavorite == isCurrentlyFav) {

      return;
    }

    final urlToUse = wantFavorite ? _favUrls[uniqueNumber] : _unfavUrls[uniqueNumber];
    if (urlToUse == null || urlToUse.isEmpty) {
      debugPrint('No URL found for fav/unfav on $uniqueNumber');
      return;
    }

    // Optimistic update
    if (wantFavorite) {
      _favoritedImages.add(uniqueNumber);
    } else {
      _favoritedImages.remove(uniqueNumber);
    }
    setState(() {});

    final success = await _favoriteService.executePostWithRetry(urlToUse);
    if (success) {
      await _refetchFavLinks(uniqueNumber);
      setState(() {});
    } else {
      // revert
      if (wantFavorite) {
        _favoritedImages.remove(uniqueNumber);
      } else {
        _favoritedImages.add(uniqueNumber);
      }
      setState(() {});
    }
  }

  // Helpers for building UI
  Widget _buildRow(List<Map<String, dynamic>> rowImages) {
    final maxRowHeight = MediaQuery.of(context).size.height * 0.4;
    Widget rowWidget;
    if (rowImages.length == 1) {
      rowWidget = _buildSingleImage(rowImages[0], maxRowHeight);
    } else {
      rowWidget = _buildDoubleImage(rowImages[0], rowImages[1], maxRowHeight);
    }
    // Wrap each row with the same horizontal and vertical padding.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0.0, vertical: 2.0),
      child: rowWidget,
    );
  }

  Widget _buildDoubleImage(Map<String, dynamic> im1, Map<String, dynamic> im2, double maxHeight) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        // Subtract the 4.0 pixel gap from the available width
        final rowWidth = constraints.maxWidth - 4.0;
        final aspect1 = (im1['width'] as double) / (im1['height'] as double);
        final aspect2 = (im2['width'] as double) / (im2['height'] as double);

        final ratio = aspect2 / aspect1;
        double w1 = rowWidth / (1 + ratio);
        double w2 = rowWidth - w1;
        double h = w1 / aspect1;
        if (h > maxHeight) {
          final scale = maxHeight / h;
          w1 *= scale;
          w2 *= scale;
          h = maxHeight;
        }
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildImageContainer(im1, w1, h),
            const SizedBox(width: 4.0),
            _buildImageContainer(im2, w2, h),
          ],
        );
      },
    );
  }

  Widget _buildSingleImage(Map<String, dynamic> im, double maxHeight) {
    final aspect = (im['width'] as double) / (im['height'] as double);
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final rowWidth = constraints.maxWidth;
        double w = rowWidth;
        double h = w / aspect;
        if (h > maxHeight) {
          final scale = maxHeight / h;
          w *= scale;
          h = maxHeight;
        }
        return _buildImageContainer(im, w, h);
      },
    );
  }

  Widget _buildImageContainer(Map<String, dynamic> im, double width, double height) {
    final imageUrl = im['url'] as String;
    final uniqueNumber = im['uniqueNumber'] as String;
    final isFav = _favoritedImages.contains(uniqueNumber);

    return _FavImageTileScrapsSliver(
      width: width,
      height: height,
      imageUrl: imageUrl,
      isFav: isFav,
      onToggle: (val) => _toggleFavorite(uniqueNumber, val),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (ctx) => OpenPost(
              imageUrl: imageUrl,
              uniqueNumber: uniqueNumber,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_images.isEmpty && _isLoading) {
      return SliverToBoxAdapter(
        child: SizedBox(
          height: 150,
          child: Center(child: PulsatingLoadingIndicator(size: 68.0, assetPath: 'assets/icons/fathemed.png')),
        ),
      );
    }
    if (_images.isEmpty && !_isLoading) {
      return SliverToBoxAdapter(
        child: SizedBox(
          height: 100,
          child: Center(
            child: Text(
              'No scraps found.',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ),
        ),
      );
    }


    return SliverPadding(
      padding: const EdgeInsets.all(8.0),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
              (ctx, index) {
            if (index < _imageRows.length) {
              if (index == _imageRows.length - 1 && _hasMore && !_isLoading) {
                // Attempt to fetch more when nearing the bottom.
                Future.microtask(_fetchImages);
              }
              final rowImages = _imageRows[index];
              return _buildRow(rowImages);
            } else {
              // Bottom loading indicator.
              return Padding(
                padding: const EdgeInsets.all(16.0),
                child: Center(child: CircularProgressIndicator()),
              );
            }
          },
          childCount: _imageRows.length + (_hasMore ? 1 : 0),
        ),
      ),
    );
  }
}

class _FavImageTileScrapsSliver extends StatefulWidget {
  final double width;
  final double height;
  final String imageUrl;
  final bool isFav;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;

  const _FavImageTileScrapsSliver({
    Key? key,
    required this.width,
    required this.height,
    required this.imageUrl,
    required this.isFav,
    required this.onToggle,
    required this.onTap,
  }) : super(key: key);

  @override
  State<_FavImageTileScrapsSliver> createState() => _FavImageTileScrapsSliverState();
}

class _FavImageTileScrapsSliverState extends State<_FavImageTileScrapsSliver> {
  late bool _localFav;

  @override
  void initState() {
    super.initState();
    _localFav = widget.isFav;
  }

  @override
  void didUpdateWidget(covariant _FavImageTileScrapsSliver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isFav != widget.isFav) {
      setState(() => _localFav = widget.isFav);
    }
  }

  Widget _buildPlaceholder(double width, double height) {
    return Container(
      width: width,
      height: height,
      color: Colors.grey[300],
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: () => setState(() => _localFav = !_localFav),
      child: HeartAnimationWidget(
        isFavorite: _localFav,
        containerWidth: widget.width,
        containerHeight: widget.height,
        onDebounceComplete: (finalVal) => widget.onToggle(finalVal),
        debounceDuration: const Duration(seconds: 2),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(
            imageUrl: widget.imageUrl,
            width: widget.width,
            height: widget.height,
            fit: BoxFit.cover,
            placeholder: (ctx, url) => _buildPlaceholder(widget.width, widget.height),
            errorWidget: (ctx, url, err) => Container(
              width: widget.width,
              height: widget.height,
              color: Colors.grey,
              alignment: Alignment.center,
              child: const Icon(Icons.error, color: Colors.red),
            ),
          ),
        ),
      ),
    );
  }
}
