enum SubmissionAttachmentKind { music, text }

class SubmissionAttachment {
  const SubmissionAttachment({
    required this.kind,
    required this.extension,
    required this.contentUrl,
    required this.downloadUrl,
    required this.fileName,
    required this.title,
    required this.artist,
    required this.thumbnailUrl,
    required this.viewerUrl,
    required this.playbackUrl,
  });

  final SubmissionAttachmentKind kind;
  final String extension;
  final String contentUrl;
  final String? downloadUrl;
  final String fileName;
  final String? title;
  final String? artist;
  final String? thumbnailUrl;
  final String? viewerUrl;
  final String? playbackUrl;

  bool get supportsPlayback =>
      kind == SubmissionAttachmentKind.music &&
      playbackUrl != null &&
      (extension == 'mp3' || extension == 'wav');

  bool get supportsPreview =>
      kind == SubmissionAttachmentKind.text &&
      (extension == 'odt' || viewerUrl != null);

  bool get usesReaderPresentation =>
      kind == SubmissionAttachmentKind.text &&
      (extension == 'txt' || extension == 'rtf' || extension == 'pdf');

  bool get usesDarkReaderColors =>
      kind == SubmissionAttachmentKind.text &&
      (extension == 'txt' || extension == 'rtf');

  bool get expandsPreviewToContent =>
      kind == SubmissionAttachmentKind.text &&
      (extension == 'txt' || extension == 'rtf');

  bool get supportsDocumentZoom =>
      kind == SubmissionAttachmentKind.text &&
      (extension == 'pdf' ||
          extension == 'docx' ||
          extension == 'odt');
}
