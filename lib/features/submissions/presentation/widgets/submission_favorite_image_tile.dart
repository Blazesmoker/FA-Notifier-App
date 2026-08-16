import 'package:material_ui/material_ui.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'package:fanotifier/shared/widgets/fa_network_image.dart';
import 'package:fanotifier/shared/widgets/fa_thumbnail_display.dart';
import 'package:fanotifier/shared/widgets/heart_animation_optimized.dart';

class SubmissionFavoriteImageTile extends StatelessWidget {
  const SubmissionFavoriteImageTile({
    super.key,
    required this.item,
    required this.width,
    required this.height,
    required this.selectionMode,
    required this.isSelected,
    required this.onToggleSelection,
    required this.onOpenSubmission,
    required this.onToggleFavorite,
    required this.onVisibilityChanged,
  });

  final Map<String, dynamic> item;
  final double width;
  final double height;
  final bool selectionMode;
  final bool isSelected;
  final Function(String uniqueNumber) onToggleSelection;
  final Function(Map<String, dynamic> item) onOpenSubmission;
  final Function(Map<String, dynamic> item, bool newVal) onToggleFavorite;
  final Function(int flatListIndex, bool isVisible) onVisibilityChanged;

  @override
  Widget build(BuildContext context) {
    final thumbnailUrl = item['thumbnailUrl'] as String;
    final hqUrl = item['hqUrl'] as String? ?? '';
    final bool isFav = item['isFav'] as bool? ?? false;
    final bool wasInitiallyFav = item['initialIsFav'] as bool? ?? false;
    final uniqueNumber = item['uniqueNumber'] as String;
    final int flatIndex = item['flatIndex'] as int? ?? -1;
    final displayUrl = hqUrl.isNotEmpty ? hqUrl : thumbnailUrl;
    final String? rating = item['rating'] as String?;
    final String? title = item['title'] as String?;
    final String? author = item['author'] as String?;
    final String? authorProfileUrl = item['authorProfileUrl'] as String?;

    return VisibilityDetector(
      key: Key('visible-$uniqueNumber'),
      onVisibilityChanged: (info) {
        onVisibilityChanged(flatIndex, info.visibleFraction > 0.2);
      },
      child: GestureDetector(
        onTap: () {
          if (selectionMode) {
            onToggleSelection(uniqueNumber);
          } else {
            onOpenSubmission(item);
          }
        },
        onLongPress: () {
          onToggleFavorite(item, !isFav);
        },
        child: SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: width,
                height: height,
                child: HeartAnimationOptimized(
                  isFavorite: isFav,
                  wasInitiallyFavorited: wasInitiallyFav,
                  containerWidth: width,
                  containerHeight: height,
                  onToggle: (val) => onToggleFavorite(item, val),
                  child: FaThumbnailOutline(
                    rating: rating,
                    borderRadius: 8.0,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8.0),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          const ColoredBox(color: Color(0xFF2C2C2C)),
                          Stack(
                            fit: StackFit.expand,
                            children: [
                              FaNetworkImage(
                                thumbnailUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (ctx, err, stack) => Container(
                                  color: Colors.grey[300],
                                  child: const Icon(
                                    Icons.error,
                                    color: Colors.red,
                                  ),
                                ),
                              ),
                              _FadeInNetworkImage(
                                imageUrl: displayUrl,
                                fit: BoxFit.cover,
                                duration: const Duration(milliseconds: 300),
                                errorBuilder: (ctx, err, stack) => Container(
                                  color: Colors.grey[300],
                                  child: const Icon(
                                    Icons.error,
                                    color: Colors.red,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (selectionMode)
                            Container(
                              color: isSelected
                                  ? Colors.black54
                                  : Colors.black26,
                              child: Center(
                                child: Icon(
                                  isSelected
                                      ? Icons.check_circle
                                      : Icons.radio_button_unchecked,
                                  color: Colors.white,
                                  size: 30,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              FaThumbnailCaption(
                maxWidth: width,
                title: title,
                author: author,
                authorProfileUrl: authorProfileUrl,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FadeInNetworkImage extends StatefulWidget {
  const _FadeInNetworkImage({
    required this.imageUrl,
    required this.fit,
    required this.duration,
    required this.errorBuilder,
  });

  final String imageUrl;
  final BoxFit fit;
  final Duration duration;
  final Widget Function(BuildContext, Object, StackTrace?) errorBuilder;

  @override
  State<_FadeInNetworkImage> createState() => _FadeInNetworkImageState();
}

class _FadeInNetworkImageState extends State<_FadeInNetworkImage> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    return FaNetworkImage(
      widget.imageUrl,
      fit: widget.fit,
      frameBuilder: (context, child, frame, _) {
        if (frame != null && !_visible) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _visible = true);
            }
          });
        }

        return AnimatedOpacity(
          opacity: _visible ? 1.0 : 0.0,
          duration: widget.duration,
          curve: Curves.easeOut,
          child: child,
        );
      },
      errorBuilder: widget.errorBuilder,
    );
  }
}
