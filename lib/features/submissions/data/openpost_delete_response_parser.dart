import 'package:html/parser.dart' as html_parser;

import 'package:FANotifier/features/submissions/domain/openpost_delete_models.dart';

OpenPostDeleteConfirmationData? parseOpenPostDeleteConfirmation(
  String htmlBody,
) {
  final document = html_parser.parse(htmlBody);
  final confirmValue =
      document.querySelector('button[name="confirm"]')?.attributes['value'];
  final deleteSubmissionsSubmitValue = document
      .querySelector('input[name="delete_submissions_submit"]')
      ?.attributes['value'];
  final submissionIdValue = document
      .querySelector('input[name="submission_ids[]"]')
      ?.attributes['value'];

  if (confirmValue == null ||
      deleteSubmissionsSubmitValue == null ||
      submissionIdValue == null) {
    return null;
  }

  return OpenPostDeleteConfirmationData(
    confirmValue: confirmValue,
    deleteSubmissionsSubmitValue: deleteSubmissionsSubmitValue,
    submissionIdValue: submissionIdValue,
  );
}

bool isOpenPostDeletionConfirmed(String htmlBody) {
  final document = html_parser.parse(htmlBody);
  final bodyText = document.body?.text.trim() ?? '';
  return bodyText.isEmpty ||
      bodyText.toLowerCase().contains('there are no submissions to list');
}
