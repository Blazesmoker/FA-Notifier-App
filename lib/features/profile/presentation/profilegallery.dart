// profilegallery.dart

import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:FANotifier/shared/widgets/fa_network_image.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:FANotifier/features/profile/domain/profile_gallery_repository.dart';
import 'package:FANotifier/features/profile/domain/profile_gallery_favorite_repository.dart';
import 'package:FANotifier/features/profile/domain/fa_folder.dart';
import 'package:FANotifier/shared/widgets/PulsatingLoadingIndicator.dart';
import 'package:FANotifier/shared/widgets/heart_animation_optimized.dart';
import 'package:FANotifier/shared/widgets/fa_thumbnail_display.dart';
import 'package:FANotifier/features/submissions/presentation/openpost.dart';

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
  ProfileGallerySliverState createState() => ProfileGallerySliverState();
}

class ProfileGallerySliverState extends State<ProfileGallerySliver> {
  late final ProfileGalleryRepository _profileGalleryRepository;

  final List<Map<String, dynamic>> _images = [];
  bool _isLoading = false;
  bool _hasMore = true;
  String? _nextPageUrl;
  int _fetchGeneration = 0;

  String _selectedFolderUrl = '';

  // Concurrency management for fetching submission data (HQ URL, fav state).
  final Queue<int> _submissionQueue = Queue<int>();
  static const int _maxConcurrentFetches = 6;
  int _activeFetches = 0;

  // Set to track which indices are visible so it doesn’t queue repeatedly.
  final Set<int> _visibleTileIndices = {};

  bool _isDisposed = false;

  late final ProfileGalleryFavoriteRepository _favoriteRepository;

  @override
  void initState() {
    super.initState();
    _profileGalleryRepository = context.read<ProfileGalleryRepository>();
    _favoriteRepository = context.read<ProfileGalleryFavoriteRepository>();

    if (widget.selectedFolderUrl != null && widget.selectedFolderUrl!.isNotEmpty) {
      _selectedFolderUrl = widget.selectedFolderUrl!;
    } else {
      _selectedFolderUrl =
          _profileGalleryRepository.buildDefaultGalleryUrl(widget.username);
    }
    _nextPageUrl = _buildInitialUrl();
    unawaited(refresh());
  }

  @override
  void didUpdateWidget(ProfileGallerySliver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.username != widget.username ||
        oldWidget.selectedFolderUrl != widget.selectedFolderUrl) {
      _selectedFolderUrl = (widget.selectedFolderUrl == null || widget.selectedFolderUrl!.isEmpty)
          ? _profileGalleryRepository.buildDefaultGalleryUrl(widget.username)
          : _profileGalleryRepository
              .normalizeFolderUrl(widget.selectedFolderUrl!);
      _nextPageUrl = _buildInitialUrl();
      unawaited(refresh());
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }


  String _buildInitialUrl() {
    return _profileGalleryRepository.buildInitialGalleryUrl(
      widget.username,
      _selectedFolderUrl,
    );
  }

  Future<void> refresh() async {
    if (_isDisposed) return;
    _fetchGeneration++;
    setState(() {
      _images.clear();
      _hasMore = true;
      _isLoading = false;
      _nextPageUrl = _buildInitialUrl();
      _submissionQueue.clear();
      _activeFetches = 0;
      _visibleTileIndices.clear();
    });
    await _fetchPage();
  }

  Future<void> _fetchPage() async {
    if (_isDisposed) return;
    if (_isLoading || !_hasMore || _nextPageUrl == null) return;

    final fetchGeneration = _fetchGeneration;
    setState(() => _isLoading = true);

    try {
      final result = await _profileGalleryRepository.fetchGalleryPage(
        url: _nextPageUrl!,
        selectedFolderUrl: widget.selectedFolderUrl,
      );
      if (_isDisposed || fetchGeneration != _fetchGeneration) return;

      _images.addAll(result.posts);
      widget.onFoldersParsed(result.folders);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_isDisposed || fetchGeneration != _fetchGeneration) return;
        for (var post in result.posts) {
          faNetworkImageProvider(post['thumbnailUrl']).then((provider) {
            if (!_isDisposed && fetchGeneration == _fetchGeneration) {
              precacheImage(provider, context);
            }
          });
        }
      });

      setState(() {
        _nextPageUrl = result.nextPageUrl;
        _hasMore = (result.nextPageUrl != null);
        _isLoading = false;
      });
    } catch (e) {
      if (_isDisposed || fetchGeneration != _fetchGeneration) return;
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
      final fetchGeneration = _fetchGeneration;
      _profileGalleryRepository.fetchSubmissionData(postUrl).then((data) {
        if (_isDisposed || fetchGeneration != _fetchGeneration) return;
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
        if (_isDisposed || fetchGeneration != _fetchGeneration) return;
        _activeFetches--;
        _processSubmissionQueue();
      });
    }
  }


  // Fav toggle logic

  void _handleToggleFavorite(int index, bool isFav) async {
    if (!await _favoriteRepository.hasAuthCookies()) {
      debugPrint('[DEBUG] Missing cookies for fav/unfav POST request.');
      if (!mounted) return;
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

    _favoriteRepository.toggleFavorite(
      uniqueNumber: uniqueNumber,
      isFav: isFav,
      favUrl: favUrl,
      unfavUrl: unfavUrl,
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
    final fetchGeneration = _fetchGeneration;
    try {
      final data =
          await _profileGalleryRepository.fetchSubmissionData(postUrl);
      if (_isDisposed || fetchGeneration != _fetchGeneration) return;
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
              rating: item['rating'] as String?,
              title: item['title'] as String?,
              author: null,
              onToggle: (val) => _handleToggleFavorite(index, val),
              onTap: () {
                Navigator.push(
                  context,
                  OpenPost.route(
                    imageUrl:
                        hqUrl != null && hqUrl.isNotEmpty ? hqUrl : thumbUrl,
                    uniqueNumber: item['uniqueNumber'] as String,
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

class _FavImageTile extends StatelessWidget {
  final double width;
  final double height;
  final double aspectRatio;
  final String thumbnailUrl;
  final String? hqUrl;
  final bool isFavorite;
  final bool wasInitiallyFavorited;
  final String? rating;
  final String? title;
  final String? author;
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
    required this.rating,
    required this.title,
    required this.author,
    required this.onToggle,
    required this.onTap,
  }) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final displayedWidth = constraints.maxWidth;
        final displayedHeight = displayedWidth / aspectRatio;
        final imageStack = ClipRRect(
          borderRadius: BorderRadius.circular(8.0),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Color(0xFF2C2C2C)),
              FaNetworkImage(
                thumbnailUrl,
                fit: BoxFit.cover,
              ),
              if (hqUrl != null && hqUrl!.isNotEmpty)
                FaNetworkImage(
                  hqUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    debugPrint("Error loading image: $hqUrl, error: $error");
                    return const Icon(Icons.error);
                  },
                ),

            ],
          ),
        );

        return GestureDetector(
          onTap: onTap,
          onLongPress: _onLongPressToggle,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HeartAnimationOptimized(
                containerWidth: displayedWidth,
                containerHeight: displayedHeight,
                isFavorite: isFavorite,
                wasInitiallyFavorited: wasInitiallyFavorited,
                onToggle: (val) => onToggle(val),
                child: SizedBox(
                  width: displayedWidth,
                  height: displayedHeight,
                  child: FaThumbnailOutline(
                    rating: rating,
                    borderRadius: 8.0,
                    child: imageStack,
                  ),
                ),
              ),
              FaThumbnailCaption(
                maxWidth: displayedWidth,
                title: title,
                author: author,
              ),
            ],
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
