import 'package:fanotifier/features/submissions/domain/submission_document_models.dart';

class SubmissionUserActionsLoadResult {
  const SubmissionUserActionsLoadResult({
    required this.statusCode,
    this.actions,
  });

  final int statusCode;
  final SubmissionUserPageActions? actions;
}
