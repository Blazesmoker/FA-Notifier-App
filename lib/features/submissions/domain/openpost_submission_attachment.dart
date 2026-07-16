enum OpenPostSubmissionAttachmentKind { music, text }

class OpenPostSubmissionAttachment {
  const OpenPostSubmissionAttachment({
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

  final OpenPostSubmissionAttachmentKind kind;
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
      kind == OpenPostSubmissionAttachmentKind.music &&
      playbackUrl != null &&
      (extension == 'mp3' || extension == 'wav');

  bool get supportsPreview =>
      kind == OpenPostSubmissionAttachmentKind.text &&
      (extension == 'odt' || viewerUrl != null);

  bool get usesReaderPresentation =>
      kind == OpenPostSubmissionAttachmentKind.text &&
      (extension == 'txt' || extension == 'rtf' || extension == 'pdf');

  bool get usesDarkReaderColors =>
      kind == OpenPostSubmissionAttachmentKind.text &&
      (extension == 'txt' || extension == 'rtf');

  bool get expandsPreviewToContent =>
      kind == OpenPostSubmissionAttachmentKind.text &&
      (extension == 'txt' || extension == 'rtf');

  bool get supportsDocumentZoom =>
      kind == OpenPostSubmissionAttachmentKind.text &&
      (extension == 'pdf' ||
          extension == 'docx' ||
          extension == 'odt');
}
