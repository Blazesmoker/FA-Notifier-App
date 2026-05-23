import 'dart:async';
import 'package:flutter/material.dart';
import 'package:FANotifier/features/profile/data/profile_favorites_service.dart';
import 'package:FANotifier/features/profile/data/profile_image_row_layout.dart';
import 'package:FANotifier/shared/widgets/PulsatingLoadingIndicator.dart';
import 'package:FANotifier/features/submissions/presentation/openpost.dart';
import 'package:FANotifier/features/submissions/data/favorite_service.dart';
import 'package:FANotifier/shared/widgets/heart_animation.dart';
import 'package:FANotifier/shared/widgets/fa_thumbnail_display.dart';

class ProfileFavsSliver extends StatefulWidget {
  final String username;

  const ProfileFavsSliver({required this.username, Key? key}) : super(key: key);

  @override
  _ProfileFavsSliverState createState() => _ProfileFavsSliverState();
}

class _ProfileFavsSliverState extends State<ProfileFavsSliver> {
  String? _nextPageUrl;
  bool _isLoading = false;
  bool _hasMore = true;


  final List<Map<String, dynamic>> _images = [];

  final List<List<Map<String, dynamic>>> _imageRows = [];

  final List<Map<String, dynamic>> _normalImagesQueue = [];

  final ProfileFavoritesService _profileFavoritesService =
      ProfileFavoritesService();


  final Set<String> _favoritedImages = {};
  final Map<String, String> _favUrls = {};
  final Map<String, String> _unfavUrls = {};
  final FavoriteService _favoriteService = FavoriteService();

  @override
  void initState() {
    super.initState();

    _nextPageUrl = 'https://www.furaffinity.net/favorites/${widget.username}/';
    _fetchImages();
  }


  /// Fetches a page of favorite images.
  Future<void> _fetchImages() async {
    if (_isLoading || _nextPageUrl == null) return;
    setState(() => _isLoading = true);

    try {
      final parseResult =
          await _profileFavoritesService.fetchFavoritesPage(_nextPageUrl!);
      setState(() {
        _images.addAll(parseResult.posts);
        appendProfileImagesIntoRows(
          newImages: parseResult.posts,
          imageRows: _imageRows,
          normalImagesQueue: _normalImagesQueue,
        );
        _preloadImagesImmediately(parseResult.posts);
        _nextPageUrl = parseResult.nextPageUrl;
        _hasMore = parseResult.nextPageUrl != null;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint("Error fetching favorites: $e");
    }
  }

  /// Preload some images to improve scrolling smoothness.
  void _preloadImagesImmediately(List<Map<String, dynamic>> images) {
    for (var image in images) {
      precacheImage(NetworkImage(image['url']), context);
    }
  }



  /// Fetch the /fav/ or /unfav/ links for a given post.
  Future<void> _fetchPostDetails(String uniqueNumber) async {
    try {
      final links =
          await _profileFavoritesService.fetchPostFavoriteLinks(uniqueNumber);
      if (links != null) {
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
    } catch (e) {
      debugPrint('Error fetching post details for $uniqueNumber: $e');
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
    if (wantFavorite == isCurrentlyFav) return;
    final urlToUse = wantFavorite ? _favUrls[uniqueNumber] : _unfavUrls[uniqueNumber];
    if (urlToUse == null || urlToUse.isEmpty) {
      debugPrint('No URL found for fav/unfav on $uniqueNumber');
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
      await _refetchFavLinks(uniqueNumber);
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



  /// Builds one row (one or two images) with padding.
  Widget _buildRow(List<Map<String, dynamic>> rowImages) {
    final maxRowHeight = MediaQuery.of(context).size.height * 0.4;
    Widget rowWidget;
    if (rowImages.length == 1) {
      rowWidget = _buildSingleImage(rowImages[0], maxRowHeight);
    } else {
      rowWidget = _buildDoubleImage(rowImages[0], rowImages[1], maxRowHeight);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0.0, vertical: 2.0),
      child: rowWidget,
    );
  }

  Widget _buildDoubleImage(Map<String, dynamic> im1, Map<String, dynamic> im2, double maxHeight) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
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
    return _FavImageTileFavs(
      width: width,
      height: height,
      imageUrl: imageUrl,
      isFav: isFav,
      rating: im['rating'] as String?,
      title: im['title'] as String?,
      author: im['author'] as String?,
      onToggle: (val) => _toggleFavorite(uniqueNumber, val),
      onTap: () {
        Navigator.push(
          context,
          OpenPost.route(
            imageUrl: imageUrl,
            uniqueNumber: uniqueNumber,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // If no images yet, show a placeholder.
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
              'No favorites found.',
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
              // When nearing the bottom, fetch more images.
              if (index == _imageRows.length - 1 && _hasMore && !_isLoading) {
                Future.microtask(_fetchImages);
              }
              return _buildRow(_imageRows[index]);
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

/// A widget that displays a favorite image tile with rounded corners and debounced favorite toggling using HeartAnimationWidget.

class _FavImageTileFavs extends StatefulWidget {
  final double width;
  final double height;
  final String imageUrl;
  final bool isFav;
  final String? rating;
  final String? title;
  final String? author;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;

  const _FavImageTileFavs({
    Key? key,
    required this.width,
    required this.height,
    required this.imageUrl,
    required this.isFav,
    required this.rating,
    required this.title,
    required this.author,
    required this.onToggle,
    required this.onTap,
  }) : super(key: key);

  @override
  State<_FavImageTileFavs> createState() => _FavImageTileFavsState();
}

class _FavImageTileFavsState extends State<_FavImageTileFavs> {
  late bool _localFav;

  @override
  void initState() {
    super.initState();
    _localFav = widget.isFav;
  }

  @override
  void didUpdateWidget(covariant _FavImageTileFavs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isFav != widget.isFav) {
      setState(() {
        _localFav = widget.isFav;
      });
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
      onLongPress: () => setState(() {
        _localFav = !_localFav;
      }),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HeartAnimationWidget(
            isFavorite: _localFav,
            containerWidth: widget.width,
            containerHeight: widget.height,
            onDebounceComplete: (finalVal) => widget.onToggle(finalVal),
            debounceDuration: const Duration(seconds: 3),
            child: FaThumbnailOutline(
              rating: widget.rating,
              borderRadius: 8,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  widget.imageUrl,
                  width: widget.width,
                  height: widget.height,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) {
                      return child;
                    }
                    return _buildPlaceholder(widget.width, widget.height);
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
            title: widget.title,
            author: widget.author,
          ),
        ],
      ),
    );
  }
}
