import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'package:fanotifier/features/submissions/domain/submission_management_models.dart';
import 'package:fanotifier/features/submissions/presentation/widgets/submission_folder_name_chip.dart';
import 'package:fanotifier/features/submissions/presentation/widgets/submission_management_styles.dart';
import 'package:fanotifier/shared/widgets/fa_network_image.dart';
import 'package:fanotifier/shared/widgets/fa_thumbnail_display.dart';

class SubmissionSelectionTile extends StatelessWidget {
  const SubmissionSelectionTile({
    super.key,
    required this.submission,
    required this.thumbnailCacheWidth,
    required this.selected,
    required this.showDetails,
    required this.folderColors,
    required this.enabled,
    required this.onToggle,
    required this.onPreview,
    required this.onOpen,
    required this.onFolder,
  });

  final FaManagedSubmission submission;
  final int thumbnailCacheWidth;
  final bool selected;
  final bool showDetails;
  final Map<String, Color> folderColors;
  final bool enabled;
  final VoidCallback onToggle;
  final VoidCallback onPreview;
  final VoidCallback onOpen;
  final ValueChanged<String> onFolder;

  @override
  Widget build(BuildContext context) {
    final aspect = submission.width / submission.height;
    final thumbnailCacheHeight = math
        .max(1, (thumbnailCacheWidth / aspect).ceil())
        .toInt();
    return Semantics(
      button: true,
      selected: selected,
      label: '${submission.title}, ${selected ? 'selected' : 'not selected'}',
      child: Material(
        color: managementCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Color(0xFF3A3A3A)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: aspect,
              child: InkWell(
                onTap: enabled ? onToggle : null,
                onLongPress: enabled ? onPreview : null,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    FaThumbnailOutline(
                      rating: submission.rating,
                      borderRadius: 10,
                      child: SizedBox.expand(
                        child: FaNetworkImage(
                          submission.thumbnailUri.toString(),
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.low,
                          cacheWidth: thumbnailCacheWidth,
                          cacheHeight: thumbnailCacheHeight,
                          excludeFromSemantics: true,
                          errorBuilder: (context, error, stackTrace) {
                            return const ColoredBox(
                              color: Color(0xFF2A2A2A),
                              child: Center(
                                child: Icon(Icons.broken_image_outlined),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    if (selected)
                      const ColoredBox(color: selectedSubmissionOverlay),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: SizedBox.square(
                        dimension: 40,
                        child: DecoratedBox(
                          decoration: const BoxDecoration(
                            color: submissionCheckboxBackground,
                            shape: BoxShape.circle,
                          ),
                          child: Checkbox(
                            value: selected,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            activeColor: managementAccent,
                            onChanged: enabled ? (_) => onToggle() : null,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (showDetails)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  InkWell(
                    onTap: enabled ? onOpen : null,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(9, 8, 9, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (submission.missingTags) ...[
                            const Tooltip(
                              message: 'This submission is missing tags',
                              child: Text('⚠️'),
                            ),
                            const SizedBox(width: 5),
                          ],
                          Expanded(
                            child: Text(
                              submission.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 9),
                    child: Divider(
                      height: 16,
                      thickness: 1,
                      color: Color(0xFF3A3A3A),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(9, 0, 9, 10),
                    child: submission.assignedFolders.isEmpty
                        ? const Text(
                            'No folders',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          )
                        : Wrap(
                            spacing: 5,
                            runSpacing: 5,
                            children: [
                              for (final folder
                                  in submission.assignedFolders)
                                FolderNameChip(
                                  name: folder,
                                  color: folderColors[folder] ??
                                      fallbackFolderColor,
                                  onTap: enabled
                                      ? () => onFolder(folder)
                                      : null,
                                ),
                            ],
                          ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
