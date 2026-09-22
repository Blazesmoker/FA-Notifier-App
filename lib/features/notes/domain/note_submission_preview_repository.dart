import 'package:fanotifier/features/notes/domain/note_submission_preview.dart';

class NotePreviewException implements Exception {
  const NotePreviewException(this.message);

  final String message;
}

abstract interface class NoteSubmissionPreviewRepository {
  Future<NoteSubmissionPreview?> loadPreview(
    String submissionUrl, {
    required Future<bool> Function() confirmNsfw,
  });
}
