// profilegallery.dart

import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:fanotifier/shared/widgets/fa_network_image.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:fanotifier/features/profile/domain/profile_gallery_repository.dart';
import 'package:fanotifier/features/submissions/presentation/submission_favorite_state_controller.dart';
import 'package:fanotifier/features/profile/domain/fa_folder.dart';
import 'package:fanotifier/shared/widgets/pulsating_loading_indicator.dart';
import 'package:fanotifier/shared/widgets/heart_animation_optimized.dart';
import 'package:fanotifier/shared/widgets/fa_thumbnail_display.dart';
import 'package:fanotifier/features/submissions/presentation/openpost.dart';

/// Callback used to report the list of folders to a parent widget.
typedef FoldersCallback = void Function(List<FaFolder>);

class ProfileGallerySliver extends StatefulWidget {
  final String username;
  /// This value is provided from the parent if a folder is pre-selected.
  final String? selectedFolderUrl;
  final FoldersCallback onFoldersParsed;
  final ValueListenable<bool> detailFetchesActive;

  const ProfileGallerySliver({
    super.key,
    required this.username,
    required this.onFoldersParsed,
    required this.detailFetchesActive,
    this.selectedFolderUrl,
  });

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
  int _detailFetchGeneration = 0;
  late bool _detailFetchesActive;

  // Set to track which indices are visible so it doesn’t queue repeatedly.
  final Set<int> _visibleTileIndices = {};
  final Map<String, ValueNotifier<int>> _tileRevisions =
      <String, ValueNotifier<int>>{};

  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _profileGalleryRepository = context.read<ProfileGalleryRepository>();
    _detailFetchesActive = widget.detailFetchesActive.value;
    widget.detailFetchesActive.addListener(_handleDetailFetchActivityChanged);

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
    if (oldWidget.detailFetchesActive != widget.detailFetchesActive) {
      oldWidget.detailFetchesActive
          .removeListener(_handleDetailFetchActivityChanged);
      widget.detailFetchesActive.addListener(_handleDetailFetchActivityChanged);
      _setDetailFetchesActive(widget.detailFetchesActive.value);
    }
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
    widget.detailFetchesActive
        .removeListener(_handleDetailFetchActivityChanged);
    for (final notifier in _tileRevisions.values) {
      notifier.dispose();
    }
    _tileRevisions.clear();
    super.dispose();
  }

  void _handleDetailFetchActivityChanged() {
    _setDetailFetchesActive(widget.detailFetchesActive.value);
  }

  void _setDetailFetchesActive(bool active) {
    if (_isDisposed || _detailFetchesActive == active) return;
    _detailFetchesActive = active;
    _detailFetchGeneration++;
    if (!active) {
      for (final index in _submissionQueue) {
        if (index >= 0 && index < _images.length) {
          _images[index]['detailFetchQueued'] = false;
        }
      }
      _submissionQueue.clear();
      return;
    }
    _queueVisibleDetailFetches();
    _processSubmissionQueue();
  }

  void _queueVisibleDetailFetches() {
    final visibleIndices = _visibleTileIndices.toList()..sort();
    for (final index in visibleIndices) {
      _queueDetailFetch(index);
    }
  }

  void _queueDetailFetch(int index) {
    if (!_detailFetchesActive ||
        index < 0 ||
        index >= _images.length ||
        !_visibleTileIndices.contains(index)) {
      return;
    }
    final item = _images[index];
    final hqUrl = item['hqUrl'] as String? ?? '';
    if (item['detailFetched'] == true || hqUrl.isNotEmpty) return;
    if (item['detailFetchQueued'] == true ||
        item['detailFetchInProgress'] == true) {
      return;
    }
    item['detailFetchQueued'] = true;
    _submissionQueue.add(index);
  }

  bool _isDetailFetchCancelled({
    required String uniqueNumber,
    required int fetchGeneration,
    required int detailFetchGeneration,
    required int visibilityGeneration,
  }) {
    if (_isDisposed ||
        !_detailFetchesActive ||
        fetchGeneration != _fetchGeneration ||
        detailFetchGeneration != _detailFetchGeneration) {
      return true;
    }
    final currentIndex = _images.indexWhere(
      (item) => _tileId(item) == uniqueNumber,
    );
    if (currentIndex < 0 || !_visibleTileIndices.contains(currentIndex)) {
      return true;
    }
    final item = _images[currentIndex];
    return (item['detailFetchVisibilityGeneration'] as int? ?? 0) !=
        visibilityGeneration;
  }

  String _tileId(Map<String, dynamic> item) =>
      item['uniqueNumber'] as String;

  ValueNotifier<int> _tileRevisionFor(Map<String, dynamic> item) {
    return _tileRevisions.putIfAbsent(
      _tileId(item),
      () => ValueNotifier<int>(0),
    );
  }

  void _notifyTile(int index) {
    if (index < 0 || index >= _images.length) return;
    final notifier = _tileRevisionFor(_images[index]);
    notifier.value++;
  }

  void _resetTileRevisions() {
    if (_tileRevisions.isEmpty) return;
    final staleNotifiers = _tileRevisions.values.toList(growable: false);
    _tileRevisions.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final notifier in staleNotifiers) {
        notifier.dispose();
      }
    });
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
    _resetTileRevisions();
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
      if (_isDisposed || !mounted || fetchGeneration != _fetchGeneration) return;

      _images.addAll(result.posts);
      widget.onFoldersParsed(result.folders);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_isDisposed || !mounted || fetchGeneration != _fetchGeneration) {
          return;
        }
        for (var post in result.posts) {
          faNetworkImageProvider(post['thumbnailUrl']).then((provider) {
            if (_isDisposed || !mounted || fetchGeneration != _fetchGeneration) {
              return;
            }
            precacheImage(provider, context);
          });
        }
      });

      setState(() {
        _nextPageUrl = result.nextPageUrl;
        _hasMore = (result.nextPageUrl != null);
        _isLoading = false;
      });
    } catch (e) {
      if (_isDisposed || !mounted || fetchGeneration != _fetchGeneration) {
        return;
      }
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading gallery: $e')),
      );
    }
  }

  // Process the submission queue with a concurrency limit.
  void _processSubmissionQueue() {
    if (_isDisposed || !_detailFetchesActive) return;

    while (_submissionQueue.isNotEmpty && _activeFetches < _maxConcurrentFetches) {
      final index = _submissionQueue.removeFirst();
      if (index < 0 ||
          index >= _images.length ||
          !_visibleTileIndices.contains(index)) {
        continue;
      }
      final queuedItem = _images[index];
      queuedItem['detailFetchQueued'] = false;
      final hqUrl = queuedItem['hqUrl'] as String? ?? '';
      if (queuedItem['detailFetched'] == true ||
          hqUrl.isNotEmpty ||
          queuedItem['detailFetchInProgress'] == true) {
        continue;
      }
      queuedItem['detailFetchInProgress'] = true;
      _activeFetches++;
      final uniqueNumber = _tileId(queuedItem);
      final postUrl = queuedItem['postUrl'] as String;
      final fetchGeneration = _fetchGeneration;
      final detailFetchGeneration = _detailFetchGeneration;
      final visibilityGeneration =
          queuedItem['detailFetchVisibilityGeneration'] as int? ?? 0;
      bool isCancelled() => _isDetailFetchCancelled(
            uniqueNumber: uniqueNumber,
            fetchGeneration: fetchGeneration,
            detailFetchGeneration: detailFetchGeneration,
            visibilityGeneration: visibilityGeneration,
          );
      _profileGalleryRepository
          .fetchSubmissionData(postUrl, isCancelled: isCancelled)
          .then((data) {
        if (_isDisposed ||
            fetchGeneration != _fetchGeneration) {
          return;
        }
        final currentIndex = _images.indexWhere(
          (item) => _tileId(item) == uniqueNumber,
        );
        if (currentIndex < 0) {
          return;
        }
        final item = _images[currentIndex];
        item['hqUrl'] = data.hqUrl;
        item['isFav'] = data.isFav;
        item['favUrl'] = data.favUrl;
        item['unfavUrl'] = data.unfavUrl;
        item['detailFetched'] = true;
        if (item['initialIsFav'] == null) {
          item['initialIsFav'] = data.isFav;
        }
        _notifyTile(currentIndex);
      }).catchError((err) {
        if (!isCancelled()) {
          debugPrint('Error fetching submission data: $err');
        }
      }).whenComplete(() {
        if (_isDisposed || fetchGeneration != _fetchGeneration) return;
        _activeFetches--;
        final currentIndex = _images.indexWhere(
          (item) => _tileId(item) == uniqueNumber,
        );
        if (currentIndex >= 0) {
          final item = _images[currentIndex];
          item['detailFetchInProgress'] = false;
          if (isCancelled()) {
            _queueDetailFetch(currentIndex);
          }
        }
        _processSubmissionQueue();
      });
    }
  }



  void _onTileVisibilityChanged(int index, bool isVisible) {
    if (index < 0 || index >= _images.length) return;
    if (isVisible) {
      if (_visibleTileIndices.contains(index)) return;
      _visibleTileIndices.add(index);
      _queueDetailFetch(index);
      _processSubmissionQueue();
    } else {
      _visibleTileIndices.remove(index);
      _submissionQueue.removeWhere((qIndex) => qIndex == index);
      final item = _images[index];
      item['detailFetchVisibilityGeneration'] =
          (item['detailFetchVisibilityGeneration'] as int? ?? 0) + 1;
      if (item['detailFetchInProgress'] != true) {
        item['detailFetchQueued'] = false;
      }
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
          return ValueListenableBuilder<int>(
            valueListenable: _tileRevisionFor(item),
            builder: (context, revision, child) {
              final aspect =
                  (item['width'] as double) / (item['height'] as double);
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
                  submissionId: item['uniqueNumber'] as String,
                  fallbackIsFavorite: isFav,
                  favUrl: item['favUrl'] as String?,
                  unfavUrl: item['unfavUrl'] as String?,
                  wasInitiallyFavorited: initialIsFav,
                  rating: item['rating'] as String?,
                  title: item['title'] as String?,
                  author: null,
                  onTap: () {
                    Navigator.push(
                      context,
                      OpenPost.route(
                        imageUrl: hqUrl != null && hqUrl.isNotEmpty
                            ? hqUrl
                            : thumbUrl,
                        uniqueNumber: item['uniqueNumber'] as String,
                      ),
                    );
                  },
                ),
              );
            },
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
  final String submissionId;
  final bool fallbackIsFavorite;
  final String? favUrl;
  final String? unfavUrl;
  final bool wasInitiallyFavorited;
  final String? rating;
  final String? title;
  final String? author;
  final VoidCallback onTap;
  const _FavImageTile({
    super.key,
    required this.width,
    required this.height,
    required this.aspectRatio,
    required this.thumbnailUrl,
    this.hqUrl,
    required this.submissionId,
    required this.fallbackIsFavorite,
    this.favUrl,
    this.unfavUrl,
    required this.wasInitiallyFavorited,
    required this.rating,
    required this.title,
    required this.author,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final isFavorite = context.select<SubmissionFavoriteStateController, bool>(
      (controller) => controller.valueFor(
        submissionId,
        fallbackIsFavorite,
      ),
    );
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
          onLongPress: () => _onLongPressToggle(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HeartAnimationOptimized(
                containerWidth: displayedWidth,
                containerHeight: displayedHeight,
                isFavorite: isFavorite,
                wasInitiallyFavorited: wasInitiallyFavorited,
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
  void _onLongPressToggle(BuildContext context) {
    context.read<SubmissionFavoriteStateController>().toggle(
          submissionId: submissionId,
          fallbackIsFavorite: fallbackIsFavorite,
          favUrl: favUrl,
          unfavUrl: unfavUrl,
        );
  }
}
