import 'package:FANotifier/features/upload/domain/submission_template.dart';

enum UploadClearFormStatus {
  unavailable,
  cleared,
  failed,
}

class UploadClearFormResult {
  const UploadClearFormResult(this.status);

  final UploadClearFormStatus status;
}

enum UploadFinalizeFieldsReadStatus {
  unavailable,
  read,
  failed,
}

class UploadFinalizeFieldsReadResult {
  const UploadFinalizeFieldsReadResult({
    required this.status,
    this.fields,
  });

  final UploadFinalizeFieldsReadStatus status;
  final SubmissionTemplateFields? fields;
}

enum UploadTemplateApplyStatus {
  applied,
  partiallyApplied,
  failed,
}

class UploadTemplateApplyResult {
  const UploadTemplateApplyResult({
    required this.status,
    this.failedFields = const <String>[],
  });

  final UploadTemplateApplyStatus status;
  final List<String> failedFields;
}
