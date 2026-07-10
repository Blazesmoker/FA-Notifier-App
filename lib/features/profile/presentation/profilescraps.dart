import 'package:flutter/material.dart';
import 'package:FANotifier/shared/widgets/fa_network_image.dart';
import 'dart:async';
import 'package:FANotifier/features/profile/data/profile_image_row_layout.dart';
import 'package:FANotifier/features/profile/data/profile_scraps_service.dart';
import 'package:FANotifier/shared/widgets/PulsatingLoadingIndicator.dart';
import 'package:FANotifier/features/submissions/presentation/openpost.dart';
import 'package:FANotifier/features/submissions/data/favorite_service.dart';
import 'package:FANotifier/shared/widgets/heart_animation.dart';
import 'package:FANotifier/shared/widgets/fa_thumbnail_display.dart';

class ProfileScrapsSliver extends StatefulWidget {
  final String username;

  const ProfileScrapsSliver({required this.username, Key? key}) : super(key: key);

  @override
  ProfileScrapsSliverState createState() => ProfileScrapsSliverState();
}

class ProfileScrapsSliverState extends State<ProfileScrapsSliver> {
  String? _nextPageUrl;
  bool _isLoading = false;
  bool _hasMore = true;
  int _fetchGeneration = 0;


  final List<Map<String, dynamic>> _images = [];

  final List<List<Map<String, dynamic>>> _imageRows = [];
  final List<Map<String, dynamic>> _normalImagesQueue = [];

  final ProfileScrapsService _profileScrapsService = ProfileScrapsService();

  // Favorite functionality
  final Set<String> _favoritedImages = {};
  final Map<String, String> _favUrls = {};
  final Map<String, String> _unfavUrls = {};
  final FavoriteService _favoriteService = FavoriteService();

  @override
  void initState() {
    super.initState();
    _nextPageUrl =
        _profileScrapsService.buildInitialScrapsPageUrl(widget.username);
    unawaited(_fetchImages());
  }

  @override
  void didUpdateWidget(ProfileScrapsSliver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.username != widget.username) {
      unawaited(refresh());
    }
  }

  Future<void> refresh() async {
    if (!mounted) return;
    _fetchGeneration++;
    setState(() {
      _nextPageUrl =
          _profileScrapsService.buildInitialScrapsPageUrl(widget.username);
      _isLoading = false;
      _hasMore = true;
      _images.clear();
      _imageRows.clear();
      _normalImagesQueue.clear();
      _favoritedImages.clear();
      _favUrls.clear();
      _unfavUrls.clear();
    });
    await _fetchImages();
  }

  Future<void> _fetchImages() async {
    if (!mounted || _isLoading || _nextPageUrl == null) return;
    final fetchGeneration = _fetchGeneration;
    setState(() => _isLoading = true);

    try {
      final result = await _profileScrapsService.fetchScrapsPage(_nextPageUrl!);
      if (!mounted || fetchGeneration != _fetchGeneration) return;
      setState(() {
        _images.addAll(result.posts);
        appendProfileImagesIntoRows(
          newImages: result.posts,
          imageRows: _imageRows,
          normalImagesQueue: _normalImagesQueue,
        );
        _preloadImagesImmediately(result.posts);

        _nextPageUrl = result.nextPageUrl;
        _hasMore = result.nextPageUrl != null;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted || fetchGeneration != _fetchGeneration) return;
      setState(() => _isLoading = false);
      debugPrint("Error fetching scraps: $e");
    }
  }

  void _preloadImagesImmediately(List<Map<String, dynamic>> fetchedImages) {
    for (var image in fetchedImages) {
      faNetworkImageProvider(image['url']).then((provider) {
        if (mounted) precacheImage(provider, context);
      });
    }
  }

  // Favorite logic
  Future<void> _fetchPostDetails(String uniqueNumber) async {
    try {
      final links =
          await _profileScrapsService.fetchPostFavoriteLinks(uniqueNumber);
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
          crossAxisAlignment: CrossAxisAlignment.start,
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
    final String? rating = im['rating'] as String?;
    final String? title = im['title'] as String?;
    final String? author = null;

    return _FavImageTileScrapsSliver(
      width: width,
      height: height,
      imageUrl: imageUrl,
      isFav: isFav,
      rating: rating,
      title: title,
      author: author,
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
  final String? rating;
  final String? title;
  final String? author;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;

  const _FavImageTileScrapsSliver({
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
      color: const Color(0xFF2C2C2C),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: () => setState(() => _localFav = !_localFav),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HeartAnimationWidget(
            isFavorite: _localFav,
            containerWidth: widget.width,
            containerHeight: widget.height,
            onDebounceComplete: (finalVal) => widget.onToggle(finalVal),
            debounceDuration: const Duration(seconds: 2),
            child: FaThumbnailOutline(
              rating: widget.rating,
              borderRadius: 8,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: widget.width,
                  height: widget.height,
                  color: const Color(0xFF2C2C2C),
                  child: FaNetworkImage(
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
