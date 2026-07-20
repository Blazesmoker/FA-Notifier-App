import 'package:flutter/material.dart';
import 'package:fanotifier/shared/widgets/fa_network_image.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:fanotifier/features/browse/domain/browse_repository.dart';
import 'package:fanotifier/features/browse/presentation/browse_image_grid_controller.dart';
import 'package:fanotifier/features/submissions/domain/submission_favorite_repository.dart';
import 'package:fanotifier/shared/fa/fa_system_message_parser.dart';
import 'package:fanotifier/shared/widgets/pulsating_loading_indicator.dart';
import 'package:fanotifier/shared/widgets/heart_animation.dart';
import 'package:fanotifier/shared/widgets/fa_thumbnail_display.dart';
import 'package:fanotifier/shared/widgets/fa_unavailable_screen.dart';
import 'package:fanotifier/features/auth/presentation/cloudflare_check_screen.dart';
import 'package:fanotifier/features/submissions/presentation/openpost.dart';

import '../../auth/domain/cloudflare_check_result.dart';

class FAImageGrid extends StatefulWidget {
  final Map<String, String> selectedFilters;
  const FAImageGrid({required this.selectedFilters, super.key})
      ;

  @override
  FAImageGridState createState() => FAImageGridState();
}

class FAImageGridState extends State<FAImageGrid> {
  late final BrowseImageGridController _controller;

  int get currentPage => _controller.currentPage;
  bool get isLoading => _controller.isLoading;
  bool get hasMore => _controller.hasMore;
  bool get _isError => _controller.isError;
  String? get _errorMessage => _controller.errorMessage;
  List<Map<String, dynamic>> get images => _controller.images;
  List<List<Map<String, dynamic>>> get imageRows => _controller.imageRows;
  List<Map<String, dynamic>> get normalImagesQueue =>
      _controller.normalImagesQueue;
  Set<String> get imageUrls => _controller.imageUrls;
  Set<String> get _favoritedImages => _controller.favoritedImages;
  ScrollController get _scrollController => _controller.scrollController;

  @override
  void initState() {
    super.initState();
    _controller = BrowseImageGridController(
      selectedFilters: widget.selectedFilters,
      onCloudflareChallenge: (initialUrl) =>
          _showCloudflareDialog(initialUrl: initialUrl),
      repository: context.read<BrowseRepository>(),
      favoriteRepository: context.read<SubmissionFavoriteRepository>(),
    );
    _controller.addListener(_handleControllerChanged);
    _controller.initialize();
  }

  void _handleControllerChanged() {
    if (mounted) setState(() {});
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
    _controller.removeListener(_handleControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  Future<void> scrollToTop({bool animate = true}) =>
      _controller.scrollToTop(animate: animate);

  Future<void> _refreshImages() async {
    await _controller.refresh(widget.selectedFilters);
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    return _controller.handleScrollNotification(notification);
  }

  Future<CloudflareCheckResult?> _showCloudflareDialog({
    String? initialUrl,
  }) async {
    if (!mounted) return null;
    return showDialog<CloudflareCheckResult>(
      context: context,
      barrierDismissible: false,
      useSafeArea: false,
      builder: (_) => CloudflareCheckScreen(
        initialUrl: initialUrl ?? 'https://www.furaffinity.net/',
        returnPageHtml: true,
      ),
    );
  }

  Future<void> _toggleFavorite(String uniqueNumber, bool wantFavorite) async {
    await _controller.toggleFavorite(uniqueNumber, wantFavorite);
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = screenHeight * 0.4;
    final errorMessage = _errorMessage;

    if (!isLoading &&
        errorMessage != null &&
        isFaMaintenanceOrUnavailableText(errorMessage)) {
      return FaUnavailableScreen(
        message: errorMessage,
        onRefresh: _refreshImages,
      );
    }

    return RefreshIndicator(
      color: const Color(0xFFE09321),
      backgroundColor: Colors.black,
      onRefresh: _refreshImages,
      child: NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
          child: imageRows.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(height: screenHeight * 0.25),
                    if (isLoading)
                      const Center(
                        child: PulsatingLoadingIndicator(
                          size: 88.0,
                          assetPath: 'assets/icons/fathemed.png',
                        ),
                      )
                    else
                      Center(
                        child: Text(
                          _isError
                              ? 'Network error. Pull to retry.'
                              : 'No results. Pull to refresh.',
                        ),
                      ),
                    if (!isLoading && _errorMessage != null)
                      const SizedBox(height: 8),
                    if (!isLoading && _errorMessage != null)
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12),
                      ),
                  ],
                )
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics()),
                  controller: _scrollController,
                  scrollCacheExtent:
                      ScrollCacheExtent.pixels(screenHeight * 1.5),
                  itemCount: imageRows.length + (isLoading ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == imageRows.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Center(
                          child: PulsatingLoadingIndicator(
                            size: 58.0,
                            assetPath: 'assets/icons/fathemed.png',
                          ),
                        ),
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
      ),
    );
  }

  Widget _buildImageRow(
      List<Map<String, dynamic>> rowImages, double maxHeight) {
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
            margin: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
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
                  OpenPost.route(
                    imageUrl: image['url'],
                    uniqueNumber: image['uniqueNumber'],
                    skipInitialWatchCheck: true,
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
          crossAxisAlignment: CrossAxisAlignment.start,
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
                  OpenPost.route(
                    imageUrl: left['url'],
                    uniqueNumber: left['uniqueNumber'],
                    skipInitialWatchCheck: true,
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
                  OpenPost.route(
                    imageUrl: right['url'],
                    uniqueNumber: right['uniqueNumber'],
                    skipInitialWatchCheck: true,
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
    required this.image,
    required this.width,
    required this.height,
    required this.isFav,
    required this.onToggle,
    required this.onTap,
  });

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
    final String? rating = widget.image['rating'] as String?;
    final String? title = widget.image['title'] as String?;
    final String? author = widget.image['author'] as String?;
    final String? authorProfileUrl = widget.image['authorProfileUrl'] as String?;

    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: () {
        setState(() => _localFav = !_localFav);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HeartAnimationWidget(
            isFavorite: _localFav,
            containerWidth: widget.width,
            containerHeight: widget.height,
            onDebounceComplete: (finalVal) {
              widget.onToggle(finalVal);
            },
            debounceDuration: const Duration(seconds: 3),
            child: FaThumbnailOutline(
              rating: rating,
              borderRadius: 8.0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8.0),
                child: Container(
                  width: widget.width,
                  height: widget.height,
                  color: const Color(0xFF2C2C2C),
                  child: FaNetworkImage(
                    imageUrl,
                    width: widget.width,
                    height: widget.height,
                    fit: BoxFit.cover,
                    loadingBuilder: (ctx, child, progress) {
                      if (progress == null) return child;
                      return const ColoredBox(color: Color(0xFF2C2C2C));
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
            ),
          ),
          FaThumbnailCaption(
            maxWidth: widget.width,
            title: title,
            author: author,
            authorProfileUrl: authorProfileUrl,
          ),
        ],
      ),
    );
  }
}
