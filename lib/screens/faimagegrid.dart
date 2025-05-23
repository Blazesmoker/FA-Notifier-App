// lib/fa_image_grid.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:html/parser.dart';
import 'package:http/http.dart' as http;
import 'dart:math';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/PulsatingLoadingIndicator.dart';
import 'openpost.dart';
import '../services/favorite_service.dart';
import '../widgets/heart_animation.dart';

class FAImageGrid extends StatefulWidget {
  final Map<String, String> selectedFilters;
  const FAImageGrid({required this.selectedFilters, Key? key}) : super(key: key);

  @override
  _FAImageGridState createState() => _FAImageGridState();
}

class _FAImageGridState extends State<FAImageGrid> {
  int currentPage = 1;
  bool isLoading = false;
  bool hasMore = true;

  /// Each image is a Map with:
  ///   - 'url': thumbnail URL
  ///   - 'width': double
  ///   - 'height': double
  ///   - 'uniqueNumber': string
  ///
  List<Map<String, dynamic>> images = [];
  List<List<Map<String, dynamic>>> imageRows = [];
  List<Map<String, dynamic>> normalImagesQueue = [];

  final Set<String> imageUrls = <String>{}; // For de-duping
  final ScrollController _scrollController = ScrollController();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();


  final Set<String> _favoritedImages = {};


  final Map<String, String> _favUrls = {};
  final Map<String, String> _unfavUrls = {};


  final FavoriteService _favoriteService = FavoriteService();


  bool _sfwEnabled = true;

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

  void _scrollListener() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.4 &&
        !isLoading &&
        hasMore) {
      currentPage++;
      _fetchImages(currentPage);
    }
  }

  Future<void> _refreshImages() async {
    setState(() {
      images.clear();
      imageUrls.clear();
      imageRows.clear();
      normalImagesQueue.clear();
      currentPage = 1;
      hasMore = true;
      _favoritedImages.clear();
      _favUrls.clear();
      _unfavUrls.clear();
    });
    await _fetchImages(currentPage, isRefresh: true);
  }

  Future<void> _fetchImages(int pageNumber, {bool isRefresh = false}) async {
    if (isLoading || !hasMore) return;
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
        hasMore = true;
      }

      final cookieHeader = await _getAllCookies();

      final response = await http.post(
        Uri.parse('https://www.furaffinity.net/browse/$pageNumber'),
        headers: {
          'Cookie': cookieHeader,
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
          'Referer': 'https://www.furaffinity.net',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'cat': getFilterValue('Category'),
          'atype': getFilterValue('Type'),
          'species': getFilterValue('Species'),
          'gender': getFilterValue('Gender'),
          'rating_general': getFilterValue('rating-general'),
          'rating_mature': getFilterValue('rating-mature'),
          'rating_adult': getFilterValue('rating-adult'),
          'perpage': '48',
          'btn': 'Next',
        },


      );

      if (response.statusCode == 200) {
        final newImages = await parseHtml(response.body);
        if (newImages.isEmpty) {
          setState(() {
            hasMore = false;
          });
        }

        /// Filter out duplicates
        final filtered = newImages.where((img) => !imageUrls.contains(img['url'])).toList();

        for (var img in filtered) {
          imageUrls.add(img['url']);
        }

        setState(() {
          images.addAll(filtered);
          _processImagesIntoRows(filtered);
          _preloadImagesImmediately(filtered);
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
        throw Exception('FAImageGrid: HTTP ${response.statusCode} fetching images.');
      }
    } catch (e) {
      setState(() => isLoading = false);
      debugPrint('FAImageGrid: Error fetching images => $e');
    }
  }


  Future<String> _getAllCookies() async {
    List<String> cookieNames = [
      'a',
      'b',
      'cc',
      'folder',
      'nodesc',
      'sz',
    ];
    List<String> cookies = [];
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

  String getFilterValue(String filterName) {
    return widget.selectedFilters[filterName] ?? '1';
  }

  /// Parses the browse page HTML for the thumbnail images
  Future<List<Map<String, dynamic>>> parseHtml(String html) async {
    final document = parse(html);
    final imageElements = document.querySelectorAll('img[src^="//t.furaffinity.net/"]');

    final List<Map<String, dynamic>> imageMetadata = [];

    for (var element in imageElements) {
      final thumbnailUrl = element.attributes['src'];
      final dataWidth = element.attributes['data-width'];
      final dataHeight = element.attributes['data-height'];

      if (thumbnailUrl != null && dataWidth != null && dataHeight != null) {
        final width = double.tryParse(dataWidth);
        final height = double.tryParse(dataHeight);

        if (width != null && height != null) {
          final match = RegExp(r'/(\d+)@').firstMatch(thumbnailUrl);
          final un = match != null
              ? match.group(1)!
              : DateTime.now().millisecondsSinceEpoch.toString();

          imageMetadata.add({
            'url': 'https:$thumbnailUrl',
            'width': width,
            'height': height,
            'uniqueNumber': un,
          });
        }
      }
    }

    return imageMetadata;
  }

  bool isWideImage(Map<String, dynamic> image) {
    final double width = image['width'];
    final double height = image['height'];
    final double aspectRatio = width / height;
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
      imageRows.add([
        normalImagesQueue.removeAt(0),
        normalImagesQueue.removeAt(0),
      ]);
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

  /// Fetch post details (like /fav/ or /unfav/ links) for [uniqueNumber].
  /// Also updates _favoritedImages if the post page indicates it's already faved.
  Future<void> _fetchPostDetails(String uniqueNumber) async {
    final postUrl = 'https://www.furaffinity.net/view/$uniqueNumber/';
    try {
      final cookieHeader = await _getAllCookies();
      final response = await http.get(
        Uri.parse(postUrl),
        headers: {
          'Cookie': cookieHeader,
          'User-Agent': 'Mozilla/5.0 (compatible; YourApp/1.0)',
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

    bool hasFavUrl =
        _favUrls.containsKey(uniqueNumber) && _favUrls[uniqueNumber]!.isNotEmpty;
    bool hasUnfavUrl = _unfavUrls.containsKey(uniqueNumber) &&
        _unfavUrls[uniqueNumber]!.isNotEmpty;
    if (!hasFavUrl && !hasUnfavUrl) {
      await _fetchPostDetails(uniqueNumber);
      hasFavUrl =
          _favUrls.containsKey(uniqueNumber) && _favUrls[uniqueNumber]!.isNotEmpty;
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


    final urlToUse = wantFavorite ? _favUrls[uniqueNumber] : _unfavUrls[uniqueNumber];
    if (urlToUse == null || urlToUse.isEmpty) {
      debugPrint('DEBUG: No URL found for fav/unfav operation on $uniqueNumber.');
      return;
    }


    if (wantFavorite) {
      _favoritedImages.add(uniqueNumber);
    } else {
      _favoritedImages.remove(uniqueNumber);
    }
    setState(() {});


    final success = await _favoriteService.executePostWithRetry(urlToUse);
    if (success) {
      await _refetchFavLinks(uniqueNumber); // re-parse the page to see updated state
      setState(() {});
    } else {

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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
        child: imageRows.isEmpty && isLoading
            ? const Center(child: PulsatingLoadingIndicator(size: 88.0, assetPath: 'assets/icons/fathemed.png'))
            : ListView.builder(
          controller: _scrollController,
          itemCount: imageRows.length + (isLoading ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == imageRows.length) {
              return const Padding(
                padding: EdgeInsets.all(16.0),
                child: Center(child: PulsatingLoadingIndicator(size: 58.0, assetPath: 'assets/icons/fathemed.png')),
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
    );
  }

  Widget _buildImageRow(List<Map<String, dynamic>> rowImages, double maxHeight) {
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
            margin: const EdgeInsets.symmetric(
              horizontal: 4.0,
              vertical: 2.0,
            ),
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

    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: () {
        setState(() => _localFav = !_localFav);
      },
      child: HeartAnimationWidget(
        isFavorite: _localFav,
        containerWidth: widget.width,
        containerHeight: widget.height,

        onDebounceComplete: (finalVal) {
          widget.onToggle(finalVal);
        },
        debounceDuration: const Duration(seconds: 3),
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
    );
  }
}
