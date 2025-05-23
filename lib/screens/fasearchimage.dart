// lib/fasearchimage.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/PulsatingLoadingIndicator.dart';
import 'openpost.dart';
import '../services/favorite_service.dart';
import '../widgets/heart_animation.dart';

class FASearchImage extends StatefulWidget {
  final Map<String, String> selectedFilters;
  final String searchQuery;

  const FASearchImage({
    required this.selectedFilters,
    required this.searchQuery,
    Key? key,
  }) : super(key: key);

  @override
  _FASearchImageState createState() => _FASearchImageState();
}

class _FASearchImageState extends State<FASearchImage> {
  int currentPage = 1;
  bool isLoading = false;
  List<Map<String, dynamic>> images = [];
  List<List<Map<String, dynamic>>> imageRows = [];
  List<Map<String, dynamic>> normalImagesQueue = [];
  final Set<String> imageUrls = <String>{};
  final ScrollController _scrollController = ScrollController();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final FavoriteService _favoriteService = FavoriteService();


  final Set<String> _favoritedImages = {};


  final Map<String, String> _favUrls = {};
  final Map<String, String> _unfavUrls = {};


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
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
      String storageKey = 'fa_cookie_$name';
      String? value = await _secureStorage.read(key: storageKey);
      if (value != null && value.isNotEmpty) {
        cookies.add('$name=$value');
      }
    }


    cookies.add('sfw=${_sfwEnabled ? '1' : '0'}');

    String cookieHeader = cookies.join('; ');

    return cookieHeader;
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

      String cookieHeader = await _getAllCookies();

      final newImages = await fetchImagesWithFilters(pageNumber, cookieHeader);
      List<Map<String, dynamic>> filteredImages =
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


      for (int i = 0; i < filteredImages.length; i++) {
        _prefetchItemDetails(images.length - filteredImages.length + i);
      }
    } catch (e) {
      debugPrint('Error fetching images: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  /// UPDATED: This function now first does a preview GET request to check if the search page is classic.
  /// In classic style it adds the 'perpage' field.
  Future<List<Map<String, dynamic>>> fetchImagesWithFilters(
      int pageNumber, String cookieHeader) async {
    // Check if the search page is classic by doing a GET request.
    bool isClassic = false;
    try {
      final previewResponse = await http.get(
        Uri.parse('https://www.furaffinity.net/search/?q=${widget.searchQuery}'),
        headers: {
          'Cookie': cookieHeader,
          'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36',
        },
      );
      if (previewResponse.statusCode == 200) {
        var previewDoc = html_parser.parse(previewResponse.body);
        isClassic = previewDoc
            .querySelector('body')
            ?.attributes['data-static-path']
            ?.contains('classic') ??
            false;
      }
    } catch (e) {
      print("Error checking search style: $e");
    }

    Map<String, String> postBody = {
      'page': pageNumber.toString(),
      'q': widget.searchQuery,
      'order-by': widget.selectedFilters['order-by'] ?? 'relevancy',
      'order-direction': widget.selectedFilters['order-direction'] ?? 'desc',
      'range': widget.selectedFilters['range'] ?? '5years',
      'mode': widget.selectedFilters['mode'] ?? 'extended',
      'rating-general': widget.selectedFilters['rating-general'] ?? '1',
      'rating-mature': widget.selectedFilters['rating-mature'] ?? '1',
      'rating-adult': widget.selectedFilters['rating-adult'] ?? '1',
      'type-art': widget.selectedFilters['type-art'] ?? '1',
      'type-music': widget.selectedFilters['type-music'] ?? '1',
      'type-flash': widget.selectedFilters['type-flash'] ?? '1',
      'type-story': widget.selectedFilters['type-story'] ?? '1',
      'type-photo': widget.selectedFilters['type-photo'] ?? '1',
      'type-poetry': widget.selectedFilters['type-poetry'] ?? '1',
      'do_search': 'Search',
    };

    // In classic style, add the perpage field.
    if (isClassic) {
      postBody['perpage'] = widget.selectedFilters['perpage'] ?? '72';
    }

    if (widget.selectedFilters['range'] == 'manual') {
      postBody['range_from'] = widget.selectedFilters['range_from'] ?? '';
      postBody['range_to'] = widget.selectedFilters['range_to'] ?? '';
    }

    final response = await http.post(
      Uri.parse('https://www.furaffinity.net/search/'),
      headers: {
        'Cookie': cookieHeader,
        'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36',
        'Referer': 'https://www.furaffinity.net/browse/',
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
        'Accept-Encoding': 'gzip, deflate, br, zstd',
        'Accept-Language': 'ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7',
        'Cache-Control': 'max-age=0',
        'DNT': '1',
        'Priority': 'u=0, i',
        'Upgrade-Insecure-Requests': '1',
        'Sec-CH-UA': '"Chromium";v="130", "Google Chrome";v="130", "Not?A_Brand";v="99"',
        'Sec-CH-UA-Mobile': '?0',
        'Sec-CH-UA-Platform': '"Windows"',
        'Sec-Fetch-Dest': 'document',
        'Sec-Fetch-Mode': 'navigate',
        'Sec-Fetch-Site': 'same-origin',
        'Sec-Fetch-User': '?1',
      },
      body: postBody,
    );






    if (response.statusCode == 200) {
      print('Response body: ${response.body.substring(0, min(2500, response.body.length))}');
      return await parseHtml(response.body);
    } else {
      throw Exception('Failed to load images: ${response.statusCode}');
    }
  }

  Future<List<Map<String, dynamic>>> parseHtml(String html) async {
    var document = html_parser.parse(html);
    var figureElements = document.querySelectorAll('figure.t-image');

    List<Map<String, dynamic>> imageMetadata = [];

    for (var figure in figureElements) {
      var aTag = figure.querySelector('a');
      var imgElement = figure.querySelector('img[src^="//t.furaffinity.net/"]');

      if (aTag != null && imgElement != null) {
        final String? postUrl = aTag.attributes['href'];
        final String? thumbnailUrl = imgElement.attributes['src'];
        final String? dataWidth = imgElement.attributes['data-width'];
        final String? dataHeight = imgElement.attributes['data-height'];

        if (postUrl != null && thumbnailUrl != null && dataWidth != null && dataHeight != null) {
          double? width = double.tryParse(dataWidth);
          double? height = double.tryParse(dataHeight);

          if (width != null && height != null) {
            final RegExp regex = RegExp(r'/view/(\d+)/');
            final RegExpMatch? match = regex.firstMatch(postUrl);
            final String uniqueNumber = match != null && match.groupCount >= 1
                ? match.group(1)!
                : 'Unknown';

            imageMetadata.add({
              'url': 'https:$thumbnailUrl',
              'width': width,
              'height': height,
              'postUrl': postUrl,
              'uniqueNumber': uniqueNumber,
            });
          }
        }
      }
    }

    return imageMetadata;
  }

  bool isWideImage(Map<String, dynamic> image) {
    double width = image['width'];
    double height = image['height'];
    double aspectRatio = width / height;
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


  Future<void> _prefetchItemDetails(int index) async {
    if (index < 0 || index >= images.length) return;

    final postUrl = images[index]['postUrl'] ?? '';
    if (postUrl.isEmpty) return;

    final details = await _fetchPostDetails(postUrl);
    if (details != null && mounted) {
      final uniqueNumber = images[index]['uniqueNumber'];
      setState(() {
        _favUrls[uniqueNumber] = details['favUrl']!;
        _unfavUrls[uniqueNumber] = details['unfavUrl']!;

        if ((details['unfavUrl'] ?? '').isNotEmpty) {
          _favoritedImages.add(uniqueNumber);
        }
      });
    }
  }


  Future<Map<String, String>?> _fetchPostDetails(String postUrl) async {
    final absolute = postUrl.startsWith('http')
        ? postUrl
        : 'https://www.furaffinity.net$postUrl';
    final cookie = await _getAllCookies();
    if (cookie.isEmpty) return null;

    try {
      final response = await http.get(
        Uri.parse(absolute),
        headers: {
          'Cookie': cookie,
          'User-Agent': 'Mozilla/5.0 (compatible; YourApp/1.0)',
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
    bool hasFav = _favUrls.containsKey(uniqueNumber) && _favUrls[uniqueNumber]!.isNotEmpty;
    bool hasUnfav = _unfavUrls.containsKey(uniqueNumber) && _unfavUrls[uniqueNumber]!.isNotEmpty;

    if (!hasFav && !hasUnfav) {
      final idx = images.indexWhere((e) => e['uniqueNumber'] == uniqueNumber);
      if (idx != -1) {
        await _prefetchItemDetails(idx);
        hasFav = _favUrls[uniqueNumber]!.isNotEmpty;
        hasUnfav = _unfavUrls[uniqueNumber]!.isNotEmpty;
      }
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
    } else {
      debugPrint('DEBUG: Successfully ${wantFavorite ? 'favored' : 'unfavored'} $uniqueNumber.');
      final idx = images.indexWhere((e) => e['uniqueNumber'] == uniqueNumber);
      if (idx != -1) {
        await _prefetchItemDetails(idx);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    double screenHeight = MediaQuery.of(context).size.height;
    double maxHeight = screenHeight * 0.4;

    return RefreshIndicator(
      onRefresh: _refreshImages,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
        child: imageRows.isEmpty && isLoading
            ? Center(child: PulsatingLoadingIndicator(size: 88.0, assetPath: 'assets/icons/fathemed.png'))
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
        double aspectRatio = image['width'] / image['height'];
        double rowWidth = constraints.maxWidth - 16.0;
        double width = rowWidth;
        double height = width / aspectRatio;

        if (height > maxHeight) {
          double scalingFactor = maxHeight / height;
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
              onFinalFavState: (finalVal) => _toggleFavorite(image['uniqueNumber'], finalVal),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OpenPost(
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

  Widget _buildDoubleImage(Map<String, dynamic> left, Map<String, dynamic> right, double maxHeight) {
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
          children: [
            _FavSearchTile(
              item: left,
              width: wL,
              height: h,
              isFavorited: _favoritedImages.contains(left['uniqueNumber']),
              onFinalFavState: (finalVal) => _toggleFavorite(left['uniqueNumber'], finalVal),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OpenPost(
                      imageUrl: left['url'],
                      uniqueNumber: left['uniqueNumber'],
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
              onFinalFavState: (finalVal) => _toggleFavorite(right['uniqueNumber'], finalVal),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OpenPost(
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
    final uniqueNumber = widget.item['uniqueNumber'] as String;

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
          widget.onFinalFavState(finalVal);
        },
        debounceDuration: const Duration(seconds: 3),
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
