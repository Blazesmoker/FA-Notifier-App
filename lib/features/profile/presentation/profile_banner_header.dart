import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fanotifier/shared/widgets/fa_network_image.dart';
import 'package:flutter/material.dart';

class ProfileBannerHeader extends StatefulWidget {
  const ProfileBannerHeader({
    super.key,
    required this.imageUrl,
    required this.mediaRevision,
    required this.expandedHeight,
  });

  final String imageUrl;
  final int mediaRevision;
  final double expandedHeight;

  @override
  State<ProfileBannerHeader> createState() => _ProfileBannerHeaderState();
}

class _ProfileBannerHeaderState extends State<ProfileBannerHeader> {
  static const Size _bannerSize = Size(1850.0, 300.0);
  static const double _blurSigma = 20.0;
  static const double _seamOverlap = 2.0;
  static final ui.ImageFilter _ambientBlurFilter = ui.ImageFilter.blur(
    sigmaX: _blurSigma,
    sigmaY: _blurSigma,
    tileMode: ui.TileMode.mirror,
  );

  late Future<ImageProvider> _imageProviderFuture;

  @override
  void initState() {
    super.initState();
    _resolveImageProvider();
  }

  @override
  void didUpdateWidget(covariant ProfileBannerHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.mediaRevision != widget.mediaRevision) {
      _resolveImageProvider();
    }
  }

  void _resolveImageProvider() {
    _imageProviderFuture = faNetworkImageProvider(widget.imageUrl);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double topInset = MediaQuery.viewPaddingOf(context).top;
        final double viewportHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : widget.expandedHeight + topInset;
        final double canvasWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final double canvasHeight = math.max(
          widget.expandedHeight + topInset,
          viewportHeight,
        );
        final double collapsedHeight = math.min(
          canvasHeight,
          kToolbarHeight + topInset,
        );
        final double collapseRange = canvasHeight - collapsedHeight;
        final double collapseProgress = collapseRange <= 0.0
            ? 0.0
            : ((canvasHeight - viewportHeight) / collapseRange)
                .clamp(0.0, 1.0)
                .toDouble();

        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.bottomCenter,
            minWidth: canvasWidth,
            maxWidth: canvasWidth,
            minHeight: canvasHeight,
            maxHeight: canvasHeight,
            child: RepaintBoundary(
              child: SizedBox(
                width: canvasWidth,
                height: canvasHeight,
                child: FutureBuilder<ImageProvider>(
                  future: _imageProviderFuture,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const ColoredBox(color: Colors.grey);
                    }
                    final ImageProvider? imageProvider = snapshot.data;
                    if (imageProvider == null) {
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    }
                    return _buildBanner(
                      imageProvider,
                      Size(canvasWidth, canvasHeight),
                      collapseProgress,
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBanner(
    ImageProvider imageProvider,
    Size canvasSize,
    double collapseProgress,
  ) {
    if (canvasSize.isEmpty) {
      return const SizedBox.shrink();
    }

    final FittedSizes fittedSizes = applyBoxFit(
      BoxFit.contain,
      _bannerSize,
      canvasSize,
    );
    final double ambientHeight = math.max(
      0.0,
      canvasSize.height - fittedSizes.destination.height,
    );
    final double ambientLayerHeight = math.min(
      canvasSize.height,
      ambientHeight + _seamOverlap,
    );
    final double initialZoomScale = math.max(
      canvasSize.width / fittedSizes.destination.width,
      canvasSize.height / fittedSizes.destination.height,
    );
    final double bannerScale = initialZoomScale -
        ((initialZoomScale - 1.0) * collapseProgress);
    double alignmentX = -1.0;
    if (widget.imageUrl.contains('fa-banner')) {
      alignmentX += 30.0 / canvasSize.width * 2.0;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        if (ambientHeight > 0.0)
          Positioned(
            top: 0.0,
            left: 0.0,
            right: 0.0,
            height: ambientLayerHeight,
            child: ClipRect(
              child: ImageFiltered(
                imageFilter: _ambientBlurFilter,
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.diagonal3Values(1.0, -1.0, 1.0),
                  child: Image(
                    image: imageProvider,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.low,
                    gaplessPlayback: true,
                    errorBuilder: (context, error, stackTrace) {
                      return const ColoredBox(color: Colors.grey);
                    },
                  ),
                ),
              ),
            ),
          ),
        Positioned.fill(
          child: Image(
            image: imageProvider,
            fit: BoxFit.contain,
            alignment: Alignment.bottomCenter,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) {
                return Transform(
                  alignment: Alignment(alignmentX, 1.0),
                  transform: Matrix4.diagonal3Values(
                    bannerScale,
                    bannerScale,
                    1.0,
                  ),
                  child: child,
                );
              }
              return const Center(
                child: CircularProgressIndicator(),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return const ColoredBox(color: Colors.grey);
            },
          ),
        ),
      ],
    );
  }
}
