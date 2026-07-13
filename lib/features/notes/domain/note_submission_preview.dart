import 'dart:typed_data';

class NoteSubmissionPreview {
  const NoteSubmissionPreview({
    required this.submissionUrl,
    required this.imageUrl,
    required this.imageBytes,
    required this.extension,
  });

  final String submissionUrl;
  final String imageUrl;
  final Uint8List imageBytes;
  final String extension;
}
