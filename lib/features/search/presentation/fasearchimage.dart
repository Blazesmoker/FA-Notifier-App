// lib/fasearchimage.dart
import 'package:material_ui/material_ui.dart';
import 'package:fanotifier/shared/widgets/fa_network_image.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:fanotifier/features/search/domain/search_repository.dart';
import 'package:fanotifier/features/search/presentation/search_image_controller.dart';
import 'package:fanotifier/features/submissions/presentation/submission_favorite_state_controller.dart';
import 'package:fanotifier/shared/fa/fa_system_message_parser.dart';
import 'package:fanotifier/shared/widgets/pulsating_loading_indicator.dart';
import 'package:fanotifier/shared/widgets/heart_animation.dart';
import 'package:fanotifier/shared/widgets/fa_thumbnail_display.dart';
import 'package:fanotifier/shared/widgets/fa_unavailable_screen.dart';
import 'package:fanotifier/features/auth/presentation/cloudflare_check_screen.dart';
import 'package:fanotifier/features/submissions/presentation/openpost.dart';

import '../../auth/domain/cloudflare_check_result.dart';

class FASearchImage extends StatefulWidget {
  final Map<String, String> selectedFilters;
  final String searchQuery;

  const FASearchImage({
    required this.selectedFilters,
    required this.searchQuery,
    super.key,
  });

  @override
  FASearchImageState createState() => FASearchImageState();
}

class FASearchImageState extends State<FASearchImage> {
  late final SearchImageController _controller;

  bool get isLoading => _controller.isLoading;
  bool get _isError => _controller.isError;
  String? get _errorMessage => _controller.errorMessage;
  List<List<Map<String, dynamic>>> get imageRows => _controller.imageRows;
  ScrollController get _scrollController => _controller.scrollController;

  @override
  void initState() {
    super.initState();
    _controller = SearchImageController(
      selectedFilters: widget.selectedFilters,
      searchQuery: widget.searchQuery,
      isMounted: () => mounted,
      notifyView: () {
        if (mounted) setState(() {});
      },
      showCloudflareCheck: _showCloudflareDialog,
      repository: context.read<SearchRepository>(),
    );
    _controller.start();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> scrollToTop({bool animate = true}) async {
    await _controller.scrollToTop(animate: animate);
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
    await _controller.refresh(
      selectedFilters: widget.selectedFilters,
      searchQuery: widget.searchQuery,
    );
  }

  Future<CloudflareCheckResult?> _showCloudflareDialog({
    String? initialUrl,
  }) async {
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

  bool _handleScrollNotification(ScrollNotification notification) {
    return _controller.handleScrollNotification(notification);
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

    if (imageRows.isEmpty && !isLoading && _isError) {
      return RefreshIndicator(
        color: const Color(0xFFE09321),
        backgroundColor: Colors.black,
        onRefresh: _refreshImages,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            SizedBox(height: screenHeight * 0.25),
            const Center(child: Text('Network error. Pull to retry.')),
            if (errorMessage != null) const SizedBox(height: 8),
            if (errorMessage != null)
              Text(
                errorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
              ),
          ],
        ),
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
          child: imageRows.isEmpty && isLoading
              ? Center(
                  child: PulsatingLoadingIndicator(
                    size: 88.0,
                    assetPath: 'assets/icons/fathemed.png',
                  ),
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
                      child: rowImages.length == 1
                          ? _buildSingleImage(rowImages[0], maxHeight)
                          : _buildDoubleImage(
                              rowImages[0],
                              rowImages[1],
                              maxHeight,
                            ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget _buildSingleImage(Map<String, dynamic> image, double maxHeight) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final aspectRatio = image['width'] / image['height'];
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
            child: _FavSearchTile(
              item: image,
              width: width,
              height: height,
              sfwEnabled: _controller.sfwEnabled,
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
      Map<String, dynamic> left, Map<String, dynamic> right, double maxHeight) {
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FavSearchTile(
              item: left,
              width: wL,
              height: h,
              sfwEnabled: _controller.sfwEnabled,
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
            _FavSearchTile(
              item: right,
              width: wR,
              height: h,
              sfwEnabled: _controller.sfwEnabled,
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

class _FavSearchTile extends StatefulWidget {
  final Map<String, dynamic> item;
  final double width;
  final double height;
  final bool sfwEnabled;
  final VoidCallback onTap;

  const _FavSearchTile({
    required this.item,
    required this.width,
    required this.height,
    required this.sfwEnabled,
    required this.onTap,
  });

  @override
  State<_FavSearchTile> createState() => _FavSearchTileState();
}

class _FavSearchTileState extends State<_FavSearchTile> {
  @override
  Widget build(BuildContext context) {
    final imageUrl = widget.item['url'] as String;
    final uniqueNumber = widget.item['uniqueNumber'] as String;
    final fallbackIsFavorite = widget.item['isFav'] as bool? ?? false;
    final isFavorite = context.select<SubmissionFavoriteStateController, bool>(
      (controller) => controller.valueFor(uniqueNumber, fallbackIsFavorite),
    );
    final String? rating = widget.item['rating'] as String?;
    final String? title = widget.item['title'] as String?;
    final String? author = widget.item['author'] as String?;
    final String? authorProfileUrl =
        widget.item['authorProfileUrl'] as String?;

    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: () {
        context.read<SubmissionFavoriteStateController>().toggle(
              submissionId: uniqueNumber,
              fallbackIsFavorite: fallbackIsFavorite,
              favUrl: widget.item['favUrl'] as String?,
              unfavUrl: widget.item['unfavUrl'] as String?,
              sfwEnabled: widget.sfwEnabled,
            );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HeartAnimationWidget(
            isFavorite: isFavorite,
            containerWidth: widget.width,
            containerHeight: widget.height,
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
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return const ColoredBox(color: Color(0xFF2C2C2C));
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
            title: title,
            author: author,
            authorProfileUrl: authorProfileUrl,
          ),
        ],
      ),
    );
  }
}
