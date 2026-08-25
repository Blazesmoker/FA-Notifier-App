import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:fanotifier/shared/widgets/fa_network_image.dart';
import 'package:provider/provider.dart';
import 'package:fanotifier/features/profile/domain/profile_favorites_repository.dart';
import 'package:fanotifier/features/profile/presentation/profile_image_row_layout.dart';
import 'package:fanotifier/shared/widgets/pulsating_loading_indicator.dart';
import 'package:fanotifier/features/submissions/presentation/openpost.dart';
import 'package:fanotifier/features/submissions/domain/submission_favorite_repository.dart';
import 'package:fanotifier/features/submissions/domain/submission_management_models.dart';
import 'package:fanotifier/shared/widgets/heart_animation.dart';
import 'package:fanotifier/shared/widgets/fa_thumbnail_display.dart';

const double _profileSelectionBorderWidth = 2.0;

class ProfileFavsSliver extends StatefulWidget {
  final String username;
  final bool selectionMode;
  final ValueChanged<int> onSelectionCountChanged;

  const ProfileFavsSliver({
    required this.username,
    required this.selectionMode,
    required this.onSelectionCountChanged,
    super.key,
  });

  @override
  ProfileFavsSliverState createState() => ProfileFavsSliverState();
}

class ProfileFavsSliverState extends State<ProfileFavsSliver> {
  String? _nextPageUrl;
  bool _isLoading = false;
  bool _hasMore = true;
  int _fetchGeneration = 0;


  final List<Map<String, dynamic>> _images = [];

  final List<List<Map<String, dynamic>>> _imageRows = [];

  final List<Map<String, dynamic>> _normalImagesQueue = [];

  late final ProfileFavoritesRepository _profileFavoritesRepository;


  final Set<String> _favoritedImages = {};
  final Map<String, String> _favUrls = {};
  final Map<String, String> _unfavUrls = {};
  final Set<String> _selectedFavoriteIds = {};
  late final SubmissionFavoriteRepository _favoriteRepository;

  int get selectedCount => _selectedFavoriteIds.length;

  @override
  void initState() {
    super.initState();
    _profileFavoritesRepository =
        context.read<ProfileFavoritesRepository>();
    _favoriteRepository = context.read<SubmissionFavoriteRepository>();

    _nextPageUrl = _profileFavoritesRepository.buildInitialFavoritesPageUrl(
      widget.username,
    );
    unawaited(_fetchImages());
  }

  @override
  void didUpdateWidget(ProfileFavsSliver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectionMode && !widget.selectionMode) {
      _selectedFavoriteIds.clear();
    }
    if (oldWidget.username != widget.username) {
      unawaited(refresh());
    }
  }

  void clearSelection() {
    if (_selectedFavoriteIds.isEmpty) return;
    setState(_selectedFavoriteIds.clear);
    widget.onSelectionCountChanged(0);
  }

  void toggleAllDisplayedSelection() {
    final displayedIds = _images
        .map((image) => image['favoriteId'])
        .whereType<String>()
        .where((id) => RegExp(r'^\d+$').hasMatch(id))
        .toSet();
    if (displayedIds.isEmpty) return;
    setState(() {
      if (_selectedFavoriteIds.containsAll(displayedIds)) {
        _selectedFavoriteIds.removeAll(displayedIds);
      } else {
        _selectedFavoriteIds.addAll(displayedIds);
      }
    });
    widget.onSelectionCountChanged(_selectedFavoriteIds.length);
  }

  Future<FaContentManagementResult> removeSelectedFavorites() {
    return _favoriteRepository.removeFavorites(
      Set<String>.unmodifiable(_selectedFavoriteIds),
    );
  }

  void _toggleSelection(String? favoriteId) {
    if (favoriteId == null || !RegExp(r'^\d+$').hasMatch(favoriteId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This favorite cannot be selected. Refresh and try again.'),
        ),
      );
      return;
    }
    setState(() {
      if (!_selectedFavoriteIds.add(favoriteId)) {
        _selectedFavoriteIds.remove(favoriteId);
      }
    });
    widget.onSelectionCountChanged(_selectedFavoriteIds.length);
  }

  Future<void> refresh() async {
    if (!mounted) return;
    _fetchGeneration++;
    final selectionChanged = _selectedFavoriteIds.isNotEmpty;
    setState(() {
      _nextPageUrl = _profileFavoritesRepository.buildInitialFavoritesPageUrl(
        widget.username,
      );
      _isLoading = false;
      _hasMore = true;
      _images.clear();
      _imageRows.clear();
      _normalImagesQueue.clear();
      _favoritedImages.clear();
      _favUrls.clear();
      _unfavUrls.clear();
      _selectedFavoriteIds.clear();
    });
    if (selectionChanged) widget.onSelectionCountChanged(0);
    await _fetchImages();
  }

  Future<void> _fetchImages() async {
    if (!mounted || _isLoading || _nextPageUrl == null) return;
    final fetchGeneration = _fetchGeneration;
    setState(() => _isLoading = true);

    try {
      final parseResult =
          await _profileFavoritesRepository.fetchFavoritesPage(_nextPageUrl!);
      if (!mounted || fetchGeneration != _fetchGeneration) return;
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
      if (!mounted || fetchGeneration != _fetchGeneration) return;
      setState(() => _isLoading = false);
      debugPrint("Error fetching favorites: $e");
    }
  }

  /// Preload some images to improve scrolling smoothness.
  void _preloadImagesImmediately(List<Map<String, dynamic>> images) {
    for (var image in images) {
      faNetworkImageProvider(image['url']).then((provider) {
        if (mounted) precacheImage(provider, context);
      });
    }
  }



  /// Fetch the /fav/ or /unfav/ links for a given post.
  Future<void> _fetchPostDetails(String uniqueNumber) async {
    try {
      final links = await _favoriteRepository.fetchLinksForSubmissionId(
        submissionId: uniqueNumber,
        cookieHeaderProvider: _profileFavoritesRepository.buildCookieHeader,
      );
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
    final success = await _favoriteRepository.executePostWithRetry(urlToUse);
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
    final favoriteId = im['favoriteId'] as String?;
    return _FavImageTileFavs(
      key: ValueKey<String>(
        'profile-favorite-${favoriteId ?? uniqueNumber}',
      ),
      width: width,
      height: height,
      imageUrl: imageUrl,
      isFav: isFav,
      rating: im['rating'] as String?,
      title: im['title'] as String?,
      author: im['author'] as String?,
      selectionMode: widget.selectionMode,
      isSelected: favoriteId != null &&
          _selectedFavoriteIds.contains(favoriteId),
      onSelectionToggle: () => _toggleSelection(favoriteId),
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
  final bool selectionMode;
  final bool isSelected;
  final VoidCallback onSelectionToggle;

  const _FavImageTileFavs({
    super.key,
    required this.width,
    required this.height,
    required this.imageUrl,
    required this.isFav,
    required this.rating,
    required this.title,
    required this.author,
    required this.onToggle,
    required this.onTap,
    required this.selectionMode,
    required this.isSelected,
    required this.onSelectionToggle,
  });

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
      color: const Color(0xFF2C2C2C),
    );
  }

  @override
  Widget build(BuildContext context) {
    final thumbnail = FaThumbnailOutline(
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
              if (loadingProgress == null) return child;
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
    );
    final image = widget.selectionMode
        ? Stack(
            children: [
              thumbnail,
              Positioned.fill(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(
                      alpha: widget.isSelected ? 0.38 : 0.08,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: widget.isSelected
                          ? const Color(0xFFE09321)
                          : Colors.transparent,
                      width: _profileSelectionBorderWidth,
                    ),
                  ),
                ),
              ),
              if (widget.isSelected)
                const Positioned.fill(
                  child: Center(
                    child: Icon(
                      Icons.check_circle,
                      color: Color(0xFFE09321),
                      size: 28,
                    ),
                  ),
                ),
            ],
          )
        : HeartAnimationWidget(
            isFavorite: _localFav,
            containerWidth: widget.width,
            containerHeight: widget.height,
            onDebounceComplete: (finalVal) => widget.onToggle(finalVal),
            debounceDuration: const Duration(seconds: 3),
            child: thumbnail,
          );
    return Semantics(
      button: true,
      selected: widget.selectionMode ? widget.isSelected : null,
      label: widget.selectionMode
          ? '${widget.title ?? 'Favorite'}, ${widget.isSelected ? 'selected' : 'not selected'}'
          : widget.title,
      child: GestureDetector(
        onTap:
            widget.selectionMode ? widget.onSelectionToggle : widget.onTap,
        onLongPress: widget.selectionMode
            ? widget.onSelectionToggle
            : () => setState(() {
                  _localFav = !_localFav;
                }),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            image,
            FaThumbnailCaption(
              maxWidth: widget.width,
              title: widget.title,
              author: widget.author,
            ),
          ],
        ),
      ),
    );
  }
}
