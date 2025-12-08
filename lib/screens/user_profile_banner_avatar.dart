import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class AnimatedBanner extends StatelessWidget {
  const AnimatedBanner({
    Key? key,
    required this.constraints,
    required this.scrollController,
    required this.bannerUrl,
    required this.bannerScaleStart,
    required this.bannerScaleEnd,
  }) : super(key: key);

  final BoxConstraints constraints;
  final ScrollController scrollController;
  final String? bannerUrl;
  final double bannerScaleStart;
  final double bannerScaleEnd;

  @override
  Widget build(BuildContext context) {
    double alignmentX = -1.0;
    if (bannerUrl?.contains('fa-banner') ?? false) {
      double shiftFraction = 30.0 / constraints.maxWidth * 2;
      alignmentX += shiftFraction;
    }

    return AnimatedBuilder(
      animation: scrollController,
      builder: (context, child) {
        double offset = scrollController.hasClients ? scrollController.offset : 0.0;

        double newScale;
        if (offset <= bannerScaleStart) {
          newScale = 1.0;
        } else if (offset >= bannerScaleEnd) {
          newScale = 1.0;
        } else {
          double scaleFraction = (offset - bannerScaleStart) / (bannerScaleEnd - bannerScaleStart);
          newScale = 1.0 - (0.2 * scaleFraction);
        }

        return Transform.scale(
          scale: newScale.clamp(1.0, 1.0),
          alignment: Alignment(alignmentX, 0),
          child: child,
        );
      },
      child: CachedNetworkImage(
        imageUrl: bannerUrl ??
            'https://d.furaffinity.net/media/banners/modern/fa-banner-summer.jpg',
        fit: BoxFit.cover,
        alignment: Alignment(alignmentX, 0),
        placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
        errorWidget: (context, url, error) => Container(color: Colors.grey),
      ),
    );
  }
}

class AnimatedAvatar extends StatelessWidget {
  const AnimatedAvatar({
    Key? key,
    required this.scrollController,
    required this.avatarUrl,
    required this.avatarFadeStart,
    required this.avatarFadeEnd,
    required this.avatarScaleStart,
    required this.avatarScaleEnd,
  }) : super(key: key);

  final ScrollController scrollController;
  final String? avatarUrl;
  final double avatarFadeStart;
  final double avatarFadeEnd;
  final double avatarScaleStart;
  final double avatarScaleEnd;

  @override
  Widget build(BuildContext context) {
    const double avatarLeft = 16.0;
    const double avatarSize = 90.0;

    return AnimatedBuilder(
      animation: scrollController,
      builder: (context, child) {
        double offset = scrollController.hasClients ? scrollController.offset : 0.0;

        double newOpacity;
        if (offset <= avatarFadeStart) {
          newOpacity = 1.0;
        } else if (offset >= avatarFadeEnd) {
          newOpacity = 0.0;
        } else {
          newOpacity = 1.0 - ((offset - avatarFadeStart) / (avatarFadeEnd - avatarFadeStart));
        }

        double newScale;
        if (offset <= avatarScaleStart) {
          newScale = 1.0;
        } else if (offset >= avatarScaleEnd) {
          newScale = 0.2;
        } else {
          double scaleFraction = (offset - avatarScaleStart) / (avatarScaleEnd - avatarScaleStart);
          newScale = 1.0 - (0.8 * scaleFraction);
        }

        return Positioned(
          bottom: -avatarSize / 1.5,
          left: avatarLeft,
          child: Transform.scale(
            scale: newScale.clamp(0.2, 1.0),
            child: Opacity(
              opacity: newOpacity.clamp(0.0, 1.0),
              child: child,
            ),
          ),
        );
      },
      child: GestureDetector(
        onTap: () {},
        child: CachedNetworkImage(
          imageUrl: avatarUrl ?? '',
          width: avatarSize,
          height: avatarSize,
          filterQuality: FilterQuality.low,
          fit: BoxFit.cover,
          placeholder: (context, url) => SizedBox(
            width: avatarSize / 2,
            height: avatarSize / 2,
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2.0),
            ),
          ),
          errorWidget: (context, url, error) => Image.asset(
            'assets/images/defaultpic.gif',
            width: avatarSize,
            height: avatarSize,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}

