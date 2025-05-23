// profilegallery.dart

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as htmlDom;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../services/favorite_gallery_service.dart';
import '../widgets/PulsatingLoadingIndicator.dart';
import 'heart_animation_optimized.dart';
import 'openpost.dart';

/// Data class to store a folder's name and URL.
class FaFolder {
  final String name;
  final String url;
  FaFolder({required this.name, required this.url});
}

class _ParseResult {
  final List<Map<String, dynamic>> posts;
  final String? nextPageUrl;
  _ParseResult({required this.posts, this.nextPageUrl});
}

/// Callback used to report the list of folders to a parent widget.
typedef FoldersCallback = void Function(List<FaFolder>);

class ProfileGallerySliver extends StatefulWidget {
  final String username;
  /// This value is provided from the parent if a folder is pre-selected.
  final String? selectedFolderUrl;
  final FoldersCallback onFoldersParsed;

  const ProfileGallerySliver({
    Key? key,
    required this.username,
    required this.onFoldersParsed,
    this.selectedFolderUrl,
  }) : super(key: key);

  @override
  _ProfileGallerySliverState createState() => _ProfileGallerySliverState();
}

class _ProfileGallerySliverState extends State<ProfileGallerySliver> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  final List<Map<String, dynamic>> _images = [];
  bool _isLoading = false;
  bool _hasMore = true;
  String? _nextPageUrl;

  // Internal folder state variables.
  String _selectedFolderName = 'Main Gallery';
  String _selectedFolderUrl = '';

  // Concurrency management for fetching submission data (HQ URL, fav state).
  final Queue<int> _submissionQueue = Queue<int>();
  static const int _maxConcurrentFetches = 6;
  int _activeFetches = 0;

  // Set to track which indices are visible so it doesn’t queue repeatedly.
  final Set<int> _visibleTileIndices = {};

  bool _isDisposed = false;

  final FavoriteGalleryService _favoriteGalleryService = FavoriteGalleryService();

  @override
  void initState() {
    super.initState();

    if (widget.selectedFolderUrl != null && widget.selectedFolderUrl!.isNotEmpty) {
      _selectedFolderUrl = widget.selectedFolderUrl!;
      _selectedFolderName = '';
    } else {
      _selectedFolderUrl = 'https://www.furaffinity.net/gallery/${widget.username}/';
      _selectedFolderName = 'Main Gallery';
    }
    _nextPageUrl = _buildInitialUrl();
    _refresh();
  }

  @override
  void didUpdateWidget(ProfileGallerySliver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedFolderUrl != widget.selectedFolderUrl) {
      _selectedFolderUrl = (widget.selectedFolderUrl == null || widget.selectedFolderUrl!.isEmpty)
          ? 'https://www.furaffinity.net/gallery/${widget.username}/'
          : widget.selectedFolderUrl!.replaceAll(RegExp(r'/$'), '');
      _nextPageUrl = _buildInitialUrl();
      _refresh();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }


  String _buildInitialUrl() {
    if (_selectedFolderUrl.isNotEmpty) {
      return _selectedFolderUrl;
    } else {
      return 'https://www.furaffinity.net/gallery/${widget.username}/';
    }
  }


  void _onFolderSelected(FaFolder folder) {
    setState(() {
      _selectedFolderName = folder.name;
      _selectedFolderUrl = folder.url;
    });
    _nextPageUrl = _buildInitialUrl();
    _refresh();
  }

  Future<void> _refresh() async {
    if (_isDisposed) return;
    setState(() {
      _images.clear();
      _hasMore = true;
      _submissionQueue.clear();
      _activeFetches = 0;
      _visibleTileIndices.clear();
    });
    await _fetchPage();
  }

  Future<void> _fetchPage() async {
    if (_isDisposed) return;
    if (_isLoading || !_hasMore || _nextPageUrl == null) return;

    setState(() => _isLoading = true);

    try {
      final result = await _fetchImages(_nextPageUrl!);
      if (_isDisposed) return;

      final startIndex = _images.length;
      _images.addAll(result.posts);

      // Pre-cache thumbnail images
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (var post in result.posts) {
          precacheImage(
            CachedNetworkImageProvider(post['thumbnailUrl']),
            context,
          );
        }
      });

      setState(() {
        _nextPageUrl = result.nextPageUrl;
        _hasMore = (result.nextPageUrl != null);
        _isLoading = false;
      });
    } catch (e) {
      if (_isDisposed) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading gallery: $e')),
      );
    }
  }

  // Process the submission queue with a concurrency limit.
  void _processSubmissionQueue() {
    if (_isDisposed) return;

    while (_submissionQueue.isNotEmpty && _activeFetches < _maxConcurrentFetches) {
      final index = _submissionQueue.removeFirst();
      _activeFetches++;
      final postUrl = _images[index]['postUrl'] as String;
      _fetchSubmissionData(postUrl).then((data) {
        if (_isDisposed) return;
        setState(() {
          _images[index]['hqUrl'] = data.hqUrl;
          _images[index]['isFav'] = data.isFav;
          _images[index]['favUrl'] = data.favUrl;
          _images[index]['unfavUrl'] = data.unfavUrl;
          if (_images[index]['initialIsFav'] == null) {
            _images[index]['initialIsFav'] = data.isFav;
          }
        });
      }).catchError((err) {
        debugPrint('Error fetching submission data: $err');
      }).whenComplete(() {
        _activeFetches--;
        _processSubmissionQueue();
      });
    }
  }


  Future<String> _getSfwCookieValue() async {
    final prefs = await SharedPreferences.getInstance();
    final sfwEnabled = prefs.getBool('sfwEnabled') ?? true;
    return sfwEnabled ? '1' : '0';
  }


  Future<String> _buildCookieHeader() async {
    final sfwValue = await _getSfwCookieValue();
    final keys = ['a', 'b', 'cc', 'folder', 'nodesc', 'sz'];
    final parts = <String>[];
    for (final k in keys) {
      final val = await _secureStorage.read(key: 'fa_cookie_$k');
      if (val != null && val.isNotEmpty) {
        parts.add('$k=$val');
      }
    }
    parts.add('sfw=$sfwValue');
    return parts.join('; ');
  }


  Future<_ParseResult> _fetchImages(String url) async {
    debugPrint("Fetching URL: $url");
    final cookieHeader = await _buildCookieHeader();
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Cookie': cookieHeader,
        'User-Agent': 'Mozilla/5.0',
        'Referer': 'https://www.furaffinity.net',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to load images: ${response.statusCode}');
    }

    final decodedBody = utf8.decode(response.bodyBytes, allowMalformed: true);
    final parseRes = _parseHtml(decodedBody, url);

    for (var p in parseRes.posts) {
      p['hqUrl'] = null;
      p['isFav'] = false;
      p['initialIsFav'] = null;
      p['favUrl'] = '';
      p['unfavUrl'] = '';
      p['detailFetchQueued'] = false;
    }

    return parseRes;
  }

  _ParseResult _parseHtml(String html, String currentUrl) {
    final doc = html_parser.parse(html);
    final imageElements = doc.querySelectorAll('figure.t-image');

    // Determine next page URL.
    String? nextPageUrl;
    for (var form in doc.querySelectorAll('form')) {
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
    for (var elem in imageElements) {
      final postUrl = elem.querySelector('a')?.attributes['href'];
      final thumbUrl = elem.querySelector('img')?.attributes['src'];
      final dataWidth = elem.querySelector('img')?.attributes['data-width'];
      final dataHeight = elem.querySelector('img')?.attributes['data-height'];
      if (postUrl != null && thumbUrl != null && dataWidth != null && dataHeight != null) {
        final w = double.tryParse(dataWidth);
        final h = double.tryParse(dataHeight);
        if (w != null && h != null) {
          posts.add({
            'postUrl': postUrl,
            'uniqueNumber': _parseUniqueNumber(postUrl),
            'thumbnailUrl': thumbUrl.startsWith('//') ? 'https:$thumbUrl' : thumbUrl,
            'width': w,
            'height': h,
            'initialIsFav': null,
          });
        }
      }
    }

    // Parses folders from the page.
    _parseFolders(doc);

    return _ParseResult(posts: posts, nextPageUrl: nextPageUrl);
  }

  String _parseUniqueNumber(String postUrl) {
    final uri = Uri.parse(postUrl);
    if (uri.pathSegments.length >= 2 && uri.pathSegments[0] == 'view') {
      return uri.pathSegments[1];
    }
    return '';
  }

  void _parseFolders(htmlDom.Document doc) {
    final folderDiv = doc.querySelector('div.folder-list');
    final List<FaFolder> folders = [];
    if (folderDiv != null) {
      final ulElements = folderDiv.querySelectorAll('ul');
      for (var ul in ulElements) {
        final liElements = ul.querySelectorAll('li');
        for (var li in liElements) {
          var aElem = li.querySelector('a.dotted');
          if (aElem != null) {
            final href = aElem.attributes['href'] ?? '';
            final title = aElem.text.trim();
            final fullUrl =
            'https://www.furaffinity.net$href'.replaceAll(RegExp(r'/$'), '');
            folders.add(FaFolder(name: title, url: fullUrl));
          } else {
            var strongElem = li.querySelector('strong');
            if (strongElem != null) {
              final title = strongElem.text.trim();
              final url = (widget.selectedFolderUrl ?? '').replaceAll(RegExp(r'/$'), '');
              folders.add(FaFolder(name: title, url: url));
            }
          }
        }
      }
    }
    widget.onFoldersParsed(folders);
  }

  /// Fetch submission details (HQ image URL and favorite state).
  Future<_SubmissionData> _fetchSubmissionData(String postUrl) async {
    final absolute = Uri.parse('https://www.furaffinity.net').resolve(postUrl).toString();

    final cookieHeader = await _buildCookieHeader();
    final resp = await http.get(
      Uri.parse(absolute),
      headers: {
        'Cookie': cookieHeader,
        'User-Agent': 'Mozilla/5.0',
        'Referer': 'https://www.furaffinity.net',
      },
    );
    if (resp.statusCode != 200) {
      throw Exception('Submission page fetch failed: ${resp.statusCode}');
    }

    final doc = html_parser.parse(utf8.decode(resp.bodyBytes));

    // 1) Get HQ image URL.
    String hqUrl = '';
    final subArea = doc.querySelector('div.submission-area.submission-image');
    if (subArea != null) {
      final img = subArea.querySelector('img#submissionImg');
      if (img != null) {
        final fullview = img.attributes['data-fullview-src'];
        if (fullview != null && fullview.isNotEmpty) {
          hqUrl = fullview.startsWith('//') ? 'https:$fullview' : fullview;
        } else {
          final src = img.attributes['src'];
          if (src != null && src.isNotEmpty) {
            hqUrl = src.startsWith('//') ? 'https:$src' : src;
          }
        }
      }
    }
    // Fallback for classic style
    if (hqUrl.isEmpty) {
      final img = doc.querySelector('img#submissionImg');
      if (img != null) {
        final fullview = img.attributes['data-fullview-src'];
        if (fullview != null && fullview.isNotEmpty) {
          hqUrl = fullview.startsWith('//') ? 'https:$fullview' : fullview;
        } else {
          final src = img.attributes['src'];
          if (src != null && src.isNotEmpty) {
            hqUrl = src.startsWith('//') ? 'https:$src' : src;
          }
        }
      }
    }

    // 2) Get Fav/unfav information.
    bool isFav = false;
    String favUrl = '';
    String unfavUrl = '';
    final favDiv = doc.querySelector('div.fav');
    if (favDiv != null) {
      for (var aTag in favDiv.querySelectorAll('a')) {
        final href = aTag.attributes['href'] ?? '';
        final absoluteHref = href.startsWith('http')
            ? href
            : 'https://www.furaffinity.net$href';
        if (href.contains('/fav/')) {
          favUrl = absoluteHref;
        } else if (href.contains('/unfav/')) {
          unfavUrl = absoluteHref;
        }
      }
      if (unfavUrl.isNotEmpty && favUrl.isEmpty) {
        isFav = true;
      }
    }
    // Fallback for classic layout: search all links for fav/unfav.
    if (favUrl.isEmpty && unfavUrl.isEmpty) {
      final allLinks = doc.querySelectorAll('a');
      for (var aTag in allLinks) {
        final href = aTag.attributes['href'] ?? '';
        final text = aTag.text.trim().toLowerCase();
        if (href.contains('/fav/') && text.contains('add')) {
          favUrl = href.startsWith('http')
              ? href
              : 'https://www.furaffinity.net$href';
        } else if (href.contains('/unfav/') && text.contains('remove')) {
          unfavUrl = href.startsWith('http')
              ? href
              : 'https://www.furaffinity.net$href';
        }
      }
      if (unfavUrl.isNotEmpty && favUrl.isEmpty) {
        isFav = true;
      }
    }

    return _SubmissionData(
      hqUrl: hqUrl,
      isFav: isFav,
      favUrl: favUrl,
      unfavUrl: unfavUrl,
    );
  }


  // Fav toggle logic

  void _handleToggleFavorite(int index, bool isFav) async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a') ?? '';
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b') ?? '';

    if (cookieA.isEmpty || cookieB.isEmpty) {
      debugPrint('[DEBUG] Missing cookies for fav/unfav POST request.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Authentication cookies missing. Please log in again.')),
      );
      return;
    }

    setState(() {
      _images[index]['isFav'] = isFav;
    });

    final uniqueNumber = _images[index]['uniqueNumber'] as String;
    final favUrl = _images[index]['favUrl'] as String? ?? '';
    final unfavUrl = _images[index]['unfavUrl'] as String? ?? '';

    _favoriteGalleryService.toggleFavorite(
      uniqueNumber: uniqueNumber,
      isFav: isFav,
      favUrl: favUrl,
      unfavUrl: unfavUrl,
      cookieA: cookieA,
      cookieB: cookieB,
      onPostComplete: (num, finalState) {
        _refreshLinksAfterPost(num);
      },
    );
  }

  Future<void> _refreshLinksAfterPost(String uniqueNumber) async {
    if (_isDisposed) return;

    final idx = _images.indexWhere((p) => p['uniqueNumber'] == uniqueNumber);
    if (idx < 0) return;

    final postUrl = _images[idx]['postUrl'] as String;
    try {
      final data = await _fetchSubmissionData(postUrl);
      if (_isDisposed) return;
      setState(() {
        _images[idx]['isFav'] = data.isFav;
        _images[idx]['favUrl'] = data.favUrl;
        _images[idx]['unfavUrl'] = data.unfavUrl;
        if (_images[idx]['initialIsFav'] == null) {
          _images[idx]['initialIsFav'] = data.isFav;
        }
      });
    } catch (e) {
      debugPrint('Error refreshing links after post => $e');
    }
  }


  void _onTileVisibilityChanged(int index, bool isVisible) {
    if (index < 0 || index >= _images.length) return;
    if (isVisible) {
      if (_visibleTileIndices.contains(index)) return;
      _visibleTileIndices.add(index);
      if (_images[index]['detailFetchQueued'] == true) return;
      _images[index]['detailFetchQueued'] = true;
      _submissionQueue.add(index);
      _processSubmissionQueue();
    } else {
      _visibleTileIndices.remove(index);
      _submissionQueue.removeWhere((qIndex) => qIndex == index);
      _images[index]['detailFetchQueued'] = false;
    }
  }

  // Build UI

  @override
  Widget build(BuildContext context) {
    if (_images.isEmpty && _isLoading) {
      return SliverToBoxAdapter(
        child: SizedBox(
          height: 200,
          child: Center(child: PulsatingLoadingIndicator(size: 68.0, assetPath: 'assets/icons/fathemed.png')),
        ),
      );
    }
    if (_images.isEmpty && !_isLoading) {
      return SliverToBoxAdapter(
        child: SizedBox(
          height: 100,
          child: Center(
            child: Text('No images found.', style: TextStyle(color: Colors.white)),
          ),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.all(8.0),
      sliver: SliverMasonryGrid.count(
        crossAxisCount: 2,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        childCount: _images.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _images.length) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: CircularProgressIndicator(),
              ),
            );
          }
          if (index >= _images.length - 10 && !_isLoading && _hasMore && _nextPageUrl != null) {
            Future.microtask(() => _fetchPage());
          }
          final item = _images[index];
          final aspect = (item['width'] as double) / (item['height'] as double);
          final hqUrl = item['hqUrl'] as String?;
          final thumbUrl = item['thumbnailUrl'] as String;
          final isFav = item['isFav'] as bool? ?? false;
          final initialIsFav = item['initialIsFav'] as bool? ?? false;

          return VisibilityDetector(
            key: Key('visible-${item['uniqueNumber']}'),
            onVisibilityChanged: (info) {
              _onTileVisibilityChanged(index, info.visibleFraction > 0.2);
            },
            child: _FavImageTile(
              key: ValueKey(item['uniqueNumber']),
              width: item['width'] as double,
              height: item['height'] as double,
              aspectRatio: aspect,
              thumbnailUrl: thumbUrl,
              hqUrl: hqUrl,
              isFavorite: isFav,
              wasInitiallyFavorited: initialIsFav,
              onToggle: (val) => _handleToggleFavorite(index, val),
              onTap: () {
                final resolved = Uri.parse('https://www.furaffinity.net')
                    .resolve(item['postUrl']);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OpenPost(
                      imageUrl: hqUrl != null && hqUrl.isNotEmpty ? hqUrl : thumbUrl,
                      uniqueNumber: item['uniqueNumber'] as String,
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _SubmissionData {
  final String hqUrl;
  final bool isFav;
  final String favUrl;
  final String unfavUrl;
  _SubmissionData({
    required this.hqUrl,
    required this.isFav,
    required this.favUrl,
    required this.unfavUrl,
  });
}

class _FavImageTile extends StatelessWidget {
  final double width;
  final double height;
  final double aspectRatio;
  final String thumbnailUrl;
  final String? hqUrl;
  final bool isFavorite;
  final bool wasInitiallyFavorited;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;
  const _FavImageTile({
    Key? key,
    required this.width,
    required this.height,
    required this.aspectRatio,
    required this.thumbnailUrl,
    this.hqUrl,
    required this.isFavorite,
    required this.wasInitiallyFavorited,
    required this.onToggle,
    required this.onTap,
  }) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final displayedWidth = constraints.maxWidth;
        final displayedHeight = displayedWidth / aspectRatio;
        return GestureDetector(
          onTap: onTap,
          onLongPress: _onLongPressToggle,
          child: HeartAnimationOptimized(
            containerWidth: displayedWidth,
            containerHeight: displayedHeight,
            isFavorite: isFavorite,
            wasInitiallyFavorited: wasInitiallyFavorited,
            onToggle: (val) => onToggle(val),
            child: AspectRatio(
              aspectRatio: aspectRatio,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8.0),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: thumbnailUrl,
                      fit: BoxFit.cover,
                    ),
                    if (hqUrl != null && hqUrl!.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: hqUrl!,
                        fit: BoxFit.cover,
                        fadeInDuration: Duration.zero,
                        errorWidget: (context, url, error) {
                          debugPrint("Error loading image: $url, error: $error");
                          return const Icon(Icons.error);
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
  void _onLongPressToggle() {
    final newVal = !isFavorite;
    onToggle(newVal);
  }
}
