import 'package:material_ui/material_ui.dart';

import 'package:fanotifier/features/submissions/domain/submission_management_models.dart';
import 'package:fanotifier/features/submissions/presentation/widgets/submission_management_styles.dart';
import 'package:fanotifier/shared/widgets/fa_thumbnail_display.dart';

class SubmissionImagePreview extends StatelessWidget {
  const SubmissionImagePreview({
    super.key,
    required this.submission,
    required this.imageProvider,
    required this.animation,
    required this.onDismiss,
  });

  final FaManagedSubmission submission;
  final ImageProvider imageProvider;
  final Animation<double> animation;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final aspect = submission.width / submission.height;
    return SafeArea(
      child: SizedBox.expand(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onDismiss,
          child: Padding(
            padding: const EdgeInsets.all(submissionPreviewScreenPadding),
            child: LayoutBuilder(
              builder: (context, constraints) {
                var previewWidth = constraints.maxWidth;
                var previewHeight = previewWidth / aspect;
                if (previewHeight > constraints.maxHeight) {
                  previewHeight = constraints.maxHeight;
                  previewWidth = previewHeight * aspect;
                }
                return Center(
                  child: AnimatedBuilder(
                    animation: animation,
                    child: SizedBox(
                      width: previewWidth,
                      height: previewHeight,
                      child: Semantics(
                        image: true,
                        label: '${submission.title} preview. Tap to close.',
                        child: FaThumbnailOutline(
                          rating: submission.rating,
                          borderRadius: submissionPreviewBorderRadius,
                          child: SizedBox.expand(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(
                                submissionPreviewBorderRadius,
                              ),
                              child: ColoredBox(
                                color: managementCard,
                                child: Image(
                                  image: imageProvider,
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.medium,
                                  excludeFromSemantics: true,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Center(
                                      child: Icon(
                                        Icons.broken_image_outlined,
                                        color: Colors.white70,
                                        size: 40,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    builder: (context, child) {
                      final progress = Curves.easeOutCubic.transform(
                        animation.value,
                      );
                      final scale = submissionPreviewInitialScale +
                          ((1.0 - submissionPreviewInitialScale) * progress);
                      return Transform.scale(scale: scale, child: child);
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
