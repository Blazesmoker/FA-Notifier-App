import 'package:material_ui/material_ui.dart';
import 'package:fanotifier/features/submissions/domain/submission_management_models.dart';
import 'submission_action_dialog_body.dart';
import 'submission_management_shrinkable_text.dart';
import 'submission_management_styles.dart';

Future<String?> showAssignExistingSubmissionFolderDialog({
  required BuildContext context,
  required FaSubmissionManagementPage page,
  required List<FaManagedSubmission> selected,
  required Map<String, Color> Function() folderColors,
}) async {
  String? selectedFolderId = page.selectedFolderId;
  if (selectedFolderId != null &&
      !page.folders.any((folder) => folder.id == selectedFolderId)) {
    selectedFolderId = null;
  }
  return await showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            scrollable: true,
            title: const Text('Assign to Existing Folder'),
            content: SubmissionActionDialogBody(
              submissions: selected,
              folderColors: folderColors(),
              description:
                  'Assign the selected submissions to an existing folder.',
              controls: DropdownButtonFormField<String>(
                key: ValueKey(selectedFolderId),
                initialValue: selectedFolderId,
                isExpanded: true,
                hint: const SubmissionManagementShrinkableText(
                  '-- select folder --',
                ),
                items: [
                  for (final folder in page.folders)
                    DropdownMenuItem<String>(
                      value: folder.id,
                      child: SubmissionManagementShrinkableText(
                        folder.label,
                        maxLines: 2,
                      ),
                    ),
                ],
                onChanged: (value) {
                  setDialogState(() => selectedFolderId = value);
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: selectedFolderId == null
                    ? null
                    : () => Navigator.of(dialogContext).pop(selectedFolderId),
                style: TextButton.styleFrom(foregroundColor: managementAccent),
                child: const Text('Assign to Folder'),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<String?> showAssignNewSubmissionFolderDialog({
  required BuildContext context,
  required FaSubmissionManagementPage page,
  required List<FaManagedSubmission> selected,
  required Map<String, Color> Function() folderColors,
}) async {
  var folderName = '';
  return await showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            scrollable: true,
            title: const Text('Assign to New Folder'),
            content: SubmissionActionDialogBody(
              submissions: selected,
              folderColors: folderColors(),
              description:
                  'Create a new folder and assign the selected submissions to it.',
              controls: TextField(
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  label: SubmissionManagementShrinkableText('Folder'),
                  hint: SubmissionManagementShrinkableText(
                    'Enter a new folder name',
                  ),
                ),
                onChanged: (value) {
                  folderName = value;
                  setDialogState(() {});
                },
                onSubmitted: (value) {
                  final trimmed = value.trim();
                  if (trimmed.isNotEmpty) {
                    Navigator.of(dialogContext).pop(trimmed);
                  }
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: folderName.trim().isEmpty
                    ? null
                    : () => Navigator.of(dialogContext).pop(folderName.trim()),
                style: TextButton.styleFrom(foregroundColor: managementAccent),
                child: const Text('Create New Folder'),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<bool> showUnassignSubmissionFolderDialog({
  required BuildContext context,
  required FaSubmissionManagementPage page,
  required List<FaManagedSubmission> selected,
  required Map<String, Color> Function() folderColors,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          scrollable: true,
          title: const Text('Unassign From Folder(s)'),
          content: SubmissionActionDialogBody(
            submissions: selected,
            folderColors: folderColors(),
            description:
                'Remove the selected submissions from all folders they are currently assigned to.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(foregroundColor: managementAccent),
              child: const Text('Unassign from Folders'),
            ),
          ],
        ),
      ) ??
      false;
}

Future<SubmissionManagementActionType?> showMoveSubmissionsDialog({
  required BuildContext context,
  required FaSubmissionManagementPage page,
  required List<FaManagedSubmission> selected,
  required Map<String, Color> Function() folderColors,
}) async {
  return await showDialog<SubmissionManagementActionType>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      scrollable: true,
      title: const Text('Move to Gallery or Scraps'),
      content: SubmissionActionDialogBody(
        submissions: selected,
        folderColors: folderColors(),
        description: 'Move the selected submissions to your Gallery or Scraps.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed:
              page.actions.containsKey(
                SubmissionManagementActionType.moveToScraps,
              )
              ? () => Navigator.of(
                  dialogContext,
                ).pop(SubmissionManagementActionType.moveToScraps)
              : null,
          style: TextButton.styleFrom(foregroundColor: managementAccent),
          child: const Text('Move to Scraps'),
        ),
        TextButton(
          onPressed:
              page.actions.containsKey(
                SubmissionManagementActionType.moveToGallery,
              )
              ? () => Navigator.of(
                  dialogContext,
                ).pop(SubmissionManagementActionType.moveToGallery)
              : null,
          style: TextButton.styleFrom(foregroundColor: managementAccent),
          child: const Text('Move to Gallery'),
        ),
      ],
    ),
  );
}

Future<bool> showDeleteSubmissionsDialog({
  required BuildContext context,
  required FaSubmissionManagementPage page,
  required List<FaManagedSubmission> selected,
  required Map<String, Color> Function() folderColors,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          scrollable: true,
          title: Text(
            'Permanently delete ${selected.length} submission${selected.length == 1 ? '' : 's'}?',
          ),
          content: SubmissionActionDialogBody(
            submissions: selected,
            folderColors: folderColors(),
            description:
                'This cannot be undone. Only the submissions shown below will be sent to Fur Affinity for deletion.',
            warning:
                'When removing multiple submissions the page may time out. Progress may still be made. The app will reload the page and keep only any submissions that still remain selected; it will never repeat the request automatically.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete Submissions'),
            ),
          ],
        ),
      ) ??
      false;
}
