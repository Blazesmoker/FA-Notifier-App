import 'package:material_ui/material_ui.dart';
import 'package:fanotifier/shared/widgets/fa_network_image.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:fanotifier/features/profile/presentation/profile_image_row_layout.dart';
import 'package:fanotifier/features/profile/domain/profile_scraps_repository.dart';
import 'package:fanotifier/shared/widgets/pulsating_loading_indicator.dart';
import 'package:fanotifier/features/submissions/presentation/openpost.dart';
import 'package:fanotifier/features/submissions/domain/submission_favorite_repository.dart';
import 'package:fanotifier/features/submissions/domain/submission_management_models.dart';
import 'package:fanotifier/features/submissions/domain/submission_management_repository.dart';
import 'package:fanotifier/shared/widgets/heart_animation.dart';
import 'package:fanotifier/shared/widgets/fa_thumbnail_display.dart';

const double _profileSelectionBorderWidth = 2.0;

class ProfileScrapsSliver extends StatefulWidget {
  final String username;
  final bool selectionMode;
  final ValueChanged<int> onSelectionCountChanged;

  const ProfileScrapsSliver({
    required this.username,
    required this.selectionMode,
    required this.onSelectionCountChanged,
    super.key,
  });

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

  late final ProfileScrapsRepository _profileScrapsRepository;

  // Favorite functionality
  final Set<String> _favoritedImages = {};
  final Map<String, String> _favUrls = {};
  final Map<String, String> _unfavUrls = {};
  final Set<String> _selectedSubmissionIds = {};
  late final SubmissionFavoriteRepository _favoriteRepository;
  late final SubmissionManagementRepository _managementRepository;

  int get selectedCount => _selectedSubmissionIds.length;

  @override
  void initState() {
    super.initState();
    _profileScrapsRepository = context.read<ProfileScrapsRepository>();
    _favoriteRepository = context.read<SubmissionFavoriteRepository>();
    _managementRepository = context.read<SubmissionManagementRepository>();
    _nextPageUrl =
        _profileScrapsRepository.buildInitialScrapsPageUrl(widget.username);
    unawaited(_fetchImages());
  }

  @override
  void didUpdateWidget(ProfileScrapsSliver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectionMode && !widget.selectionMode) {
      _selectedSubmissionIds.clear();
    }
    if (oldWidget.username != widget.username) {
      unawaited(refresh());
    }
  }

  void clearSelection() {
    if (_selectedSubmissionIds.isEmpty) return;
    setState(_selectedSubmissionIds.clear);
    widget.onSelectionCountChanged(0);
  }

  void toggleAllDisplayedSelection() {
    final displayedIds = _images
        .map((image) => image['uniqueNumber'])
        .whereType<String>()
        .where((id) => RegExp(r'^\d+$').hasMatch(id))
        .toSet();
    if (displayedIds.isEmpty) return;
    setState(() {
      if (_selectedSubmissionIds.containsAll(displayedIds)) {
        _selectedSubmissionIds.removeAll(displayedIds);
      } else {
        _selectedSubmissionIds.addAll(displayedIds);
      }
    });
    widget.onSelectionCountChanged(_selectedSubmissionIds.length);
  }

  Future<FaContentManagementResult> moveSelectedToGallery() {
    return _managementRepository.moveProfileScrapsToGallery(
      Set<String>.unmodifiable(_selectedSubmissionIds),
    );
  }

  void _toggleSelection(String submissionId) {
    if (!RegExp(r'^\d+$').hasMatch(submissionId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This scrap cannot be selected. Refresh and try again.'),
        ),
      );
      return;
    }
    setState(() {
      if (!_selectedSubmissionIds.add(submissionId)) {
        _selectedSubmissionIds.remove(submissionId);
      }
    });
    widget.onSelectionCountChanged(_selectedSubmissionIds.length);
  }

  Future<void> refresh() async {
    if (!mounted) return;
    _fetchGeneration++;
    final selectionChanged = _selectedSubmissionIds.isNotEmpty;
    setState(() {
      _nextPageUrl =
          _profileScrapsRepository.buildInitialScrapsPageUrl(widget.username);
      _isLoading = false;
      _hasMore = true;
      _images.clear();
      _imageRows.clear();
      _normalImagesQueue.clear();
      _favoritedImages.clear();
      _favUrls.clear();
      _unfavUrls.clear();
      _selectedSubmissionIds.clear();
    });
    if (selectionChanged) widget.onSelectionCountChanged(0);
    await _fetchImages();
  }

  Future<void> _fetchImages() async {
    if (!mounted || _isLoading || _nextPageUrl == null) return;
    final fetchGeneration = _fetchGeneration;
    setState(() => _isLoading = true);

    try {
      final result =
          await _profileScrapsRepository.fetchScrapsPage(_nextPageUrl!);
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
      final links = await _favoriteRepository.fetchLinksForSubmissionId(
        submissionId: uniqueNumber,
        cookieHeaderProvider: _profileScrapsRepository.buildCookieHeader,
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

    final success = await _favoriteRepository.executePostWithRetry(urlToUse);
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
      key: ValueKey<String>('profile-scrap-$uniqueNumber'),
      width: width,
      height: height,
      imageUrl: imageUrl,
      isFav: isFav,
      rating: rating,
      title: title,
      author: author,
      selectionMode: widget.selectionMode,
      isSelected: _selectedSubmissionIds.contains(uniqueNumber),
      onSelectionToggle: () => _toggleSelection(uniqueNumber),
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
  final bool selectionMode;
  final bool isSelected;
  final VoidCallback onSelectionToggle;

  const _FavImageTileScrapsSliver({
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
    final image = Stack(
      children: [
        HeartAnimationWidget(
          isFavorite: _localFav,
          containerWidth: widget.width,
          containerHeight: widget.height,
          onDebounceComplete: (finalVal) => widget.onToggle(finalVal),
          debounceDuration: const Duration(seconds: 2),
          child: thumbnail,
        ),
        Positioned.fill(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            decoration: BoxDecoration(
              color: widget.selectionMode
                  ? widget.isSelected
                      ? Colors.black54
                      : Colors.black26
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: widget.selectionMode && widget.isSelected
                    ? const Color(0xFFE09321)
                    : Colors.transparent,
                width: _profileSelectionBorderWidth,
              ),
            ),
          ),
        ),
        if (widget.selectionMode)
          Positioned.fill(
            child: Center(
              child: Icon(
                widget.isSelected
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                color: widget.isSelected
                    ? const Color(0xFFE09321)
                    : Colors.white,
                size: 30,
              ),
            ),
          ),
      ],
    );
    return Semantics(
      button: true,
      selected: widget.selectionMode ? widget.isSelected : null,
      label: widget.selectionMode
          ? '${widget.title ?? 'Scrap'}, ${widget.isSelected ? 'selected' : 'not selected'}'
          : widget.title,
      child: GestureDetector(
        onTap:
            widget.selectionMode ? widget.onSelectionToggle : widget.onTap,
        onLongPress: widget.selectionMode
            ? widget.onSelectionToggle
            : () => setState(() => _localFav = !_localFav),
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
