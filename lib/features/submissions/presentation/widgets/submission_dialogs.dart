import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fanotifier/features/submissions/domain/submission_document_models.dart';
import 'package:fanotifier/shared/widgets/fa_network_image.dart';

Widget buildSubmissionInfoDialog({
  required BuildContext dialogContext,
  required String? category,
  required String? type,
  required String? species,
  required String? gender,
  required String? size,
  required String? fileSize,
  required List<SubmissionFolderLink> folders,
}) {
  return AlertDialog(
    title: const Text('Post Information'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (category != null)
            Text(
              'Category: $category',
              style: const TextStyle(fontSize: 16),
            ),
          if (category != null) const SizedBox(height: 8),
          if (type != null)
            Text(
              'Sub-Category: $type',
              style: const TextStyle(fontSize: 16),
            ),
          const SizedBox(height: 8),
          if (species != null)
            Text(
              'Species: $species',
              style: const TextStyle(fontSize: 16),
            ),
          const SizedBox(height: 8),
          if (gender != null)
            Text(
              'Gender: $gender',
              style: const TextStyle(fontSize: 16),
            ),
          const SizedBox(height: 8),
          if (size != null)
            Text(
              'Size: $size',
              style: const TextStyle(fontSize: 16),
            ),
          const SizedBox(height: 8),
          if (fileSize != null)
            Text(
              'File Size: $fileSize',
              style: const TextStyle(fontSize: 16),
            ),
          if (folders.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Folders',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            for (final folder in folders)
              Semantics(
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () =>
                      Navigator.of(dialogContext).pop(folder),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        folder.name,
                        style: const TextStyle(
                          color: Color(0xFFE09321),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(dialogContext).pop(),
        child: const Text('Close'),
      ),
    ],
  );
}

Widget buildSubmissionEditDialog({
  required BuildContext context,
}) {
  return AlertDialog(
    title: const Text('Edit Submission'),
    content: const Text('What do you want to do?'),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop('info'),
        child: const Text(
          'Edit Submission Info',
          style: TextStyle(color: Color(0xFFE09321)),
        ),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop('thumbnail'),
        child: const Text(
          'Update Thumbnail',
          style: TextStyle(color: Color(0xFFE09321)),
        ),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop('file'),
        child: const Text(
          'Update Source File',
          style: TextStyle(color: Color(0xFFE09321)),
        ),
      ),
    ],
  );
}

Widget buildSubmissionDeleteDialog({
  required BuildContext dialogContext,
  required String? fullViewImageUrl,
  required String? currentUsername,
  required TextEditingController passwordController,
  required FocusNode passwordFocusNode,
  required void Function(BuildContext) submitDeletion,
}) {
  return AlertDialog(
    title: const Text('Confirm Deletion'),
    content: AutofillGroup(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'The following submission is going to be removed from your gallery:',
            ),
            const SizedBox(height: 8),
            if (fullViewImageUrl != null)
              FaNetworkImage(
                fullViewImageUrl,
                height: 150,
              ),
            const SizedBox(height: 8),
            const Text(
              'This procedure is irreversible.\n\nPlease enter your account password below as a confirmation.',
            ),
            const SizedBox(height: 8),
            // Hidden username field so Android autofill recognises a credential pair
            if (currentUsername != null)
              SizedBox(
                height: 0,
                child: Opacity(
                  opacity: 0,
                  child: TextField(
                    autofillHints: const [AutofillHints.username],
                    controller:
                        TextEditingController(text: currentUsername),
                    readOnly: true,
                    enableInteractiveSelection: false,
                    focusNode: _AlwaysDisabledFocusNode(),
                  ),
                ),
              ),
            TextField(
              controller: passwordController,
              focusNode: passwordFocusNode,
              obscureText: true,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Password',
              ),
              onSubmitted: (_) => submitDeletion(dialogContext),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () {
          TextInput.finishAutofillContext(shouldSave: false);
          Navigator.of(dialogContext).pop();
        },
        child: const Text('Close'),
      ),
      ElevatedButton(
        onPressed: () => submitDeletion(dialogContext),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red,
        ),
        child: const Text('Confirm Deletion'),
      ),
    ],
  );
}

class _AlwaysDisabledFocusNode extends FocusNode {
  @override
  bool get hasFocus => false;
}
