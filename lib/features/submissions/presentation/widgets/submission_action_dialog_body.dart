import 'package:material_ui/material_ui.dart';

import 'package:fanotifier/features/submissions/domain/submission_management_models.dart';
import 'package:fanotifier/features/submissions/presentation/widgets/submission_folder_name_chip.dart';
import 'package:fanotifier/features/submissions/presentation/widgets/submission_management_shrinkable_text.dart';
import 'package:fanotifier/features/submissions/presentation/widgets/submission_management_styles.dart';
import 'package:fanotifier/shared/widgets/fa_network_image.dart';

class SubmissionActionDialogBody extends StatelessWidget {
  const SubmissionActionDialogBody({
    super.key,
    required this.submissions,
    required this.folderColors,
    required this.description,
    this.controls,
    this.warning,
  });

  final List<FaManagedSubmission> submissions;
  final Map<String, Color> folderColors;
  final String description;
  final Widget? controls;
  final String? warning;

  @override
  Widget build(BuildContext context) {
    final maxListHeight = MediaQuery.sizeOf(context).height * 0.32;
    final desiredListHeight = submissions.length * 92.0;
    final listHeight = desiredListHeight < 112
        ? 112.0
        : desiredListHeight > maxListHeight
            ? maxListHeight
            : desiredListHeight;
    return SizedBox(
      width: double.maxFinite,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(description, style: const TextStyle(color: Colors.white70)),
          if (controls != null) ...[
            const SizedBox(height: 14),
            controls!,
          ],
          const SizedBox(height: 14),
          Text(
            '${submissions.length} selected',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: listHeight,
            child: _SelectedSubmissionsList(
              submissions: submissions,
              folderColors: folderColors,
            ),
          ),
          if (warning != null) ...[
            const SizedBox(height: 12),
            Text(
              warning!,
              style: const TextStyle(
                color: managementAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SelectedSubmissionsList extends StatelessWidget {
  const _SelectedSubmissionsList({
    required this.submissions,
    required this.folderColors,
  });

  final List<FaManagedSubmission> submissions;
  final Map<String, Color> folderColors;

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      child: ListView.separated(
        primary: false,
        itemCount: submissions.length,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final submission = submissions[index];
          return Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: managementCard,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF3A3A3A)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: FaNetworkImage(
                    submission.thumbnailUri.toString(),
                    width: 54,
                    height: 54,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return const ColoredBox(
                        color: Color(0xFF2A2A2A),
                        child: SizedBox(
                          width: 54,
                          height: 54,
                          child: Icon(Icons.broken_image_outlined),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SubmissionManagementShrinkableText(
                        submission.title,
                        maxLines: 2,
                        minFontSize: 9,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '#${submission.id}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                      if (submission.assignedFolders.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            for (final folder in submission.assignedFolders)
                              FolderNameChip(
                                name: folder,
                                color: folderColors[folder] ?? Colors.grey,
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
