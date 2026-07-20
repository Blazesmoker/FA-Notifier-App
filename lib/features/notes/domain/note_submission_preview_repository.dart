import 'package:fanotifier/features/notes/domain/note_submission_preview.dart';

abstract interface class NoteSubmissionPreviewRepository {
  Future<NoteSubmissionPreview?> loadPreview(
    String submissionUrl, {
    required Future<bool> Function() confirmNsfw,
  });
}
