import 'package:html/dom.dart' as dom;

import 'package:fanotifier/features/submissions/data/openpost_submission_url.dart';
import 'package:fanotifier/features/submissions/domain/openpost_submission_attachment.dart';

const Set<String> _musicExtensions = <String>{'mp3', 'wav', 'mid'};
const Set<String> _textExtensions = <String>{
  'pdf',
  'rtf',
  'txt',
  'doc',
  'docx',
  'odt',
};
const Set<String> _documentViewerExtensions = <String>{
  'pdf',
  'rtf',
  'txt',
  'docx',
};

OpenPostSubmissionAttachment? parseOpenPostSubmissionAttachment(
  dom.Document document,
) {
  final metadata = document.querySelector(
    'script[data-content-type][data-content-extension][data-content-url]',
  );
  if (metadata == null) return null;

  final extension = metadata.attributes['data-content-extension']
          ?.trim()
          .toLowerCase()
          .replaceFirst(RegExp(r'^\.'), '') ??
      '';
  if (extension.isEmpty) return null;

  final kind = _attachmentKind(
    metadata.attributes['data-content-type'],
    extension,
  );
  if (kind == null) return null;

  final downloadUrl = _downloadUrl(document);
  final metadataContentUrl = normalizeOpenPostSubmissionUrl(
    metadata.attributes['data-content-url'],
  );
  final audioUrl = normalizeOpenPostSubmissionUrl(
    document
        .querySelector(
          '#c-musicPlayer_inner[src], .submission-music audio[src]',
        )
        ?.attributes['src'],
  );
  final contentUrl = metadataContentUrl ?? audioUrl ?? downloadUrl;
  if (contentUrl == null) return null;

  final uploadId = metadata.attributes['data-content-id']?.trim();

  return OpenPostSubmissionAttachment(
    kind: kind,
    extension: extension,
    contentUrl: contentUrl,
    downloadUrl: downloadUrl,
    fileName: _attachmentFileName(
      downloadUrl ?? contentUrl,
      extension: extension,
      fallbackTitle: metadata.attributes['data-artwork-title'],
    ),
    title: _trimmed(metadata.attributes['data-artwork-title']),
    artist: _trimmed(metadata.attributes['data-artist-name']),
    thumbnailUrl: normalizeOpenPostSubmissionUrl(
      metadata.attributes['data-thumbnail-src'],
    ),
    viewerUrl: _viewerUrl(extension, uploadId),
    playbackUrl: kind == OpenPostSubmissionAttachmentKind.music
        ? audioUrl ?? metadataContentUrl ?? downloadUrl
        : null,
  );
}

OpenPostSubmissionAttachmentKind? _attachmentKind(
  String? contentType,
  String extension,
) {
  switch (contentType?.trim().toLowerCase()) {
    case 'music':
      return _musicExtensions.contains(extension)
          ? OpenPostSubmissionAttachmentKind.music
          : null;
    case 'text':
      return _textExtensions.contains(extension)
          ? OpenPostSubmissionAttachmentKind.text
          : null;
  }
  if (_musicExtensions.contains(extension)) {
    return OpenPostSubmissionAttachmentKind.music;
  }
  if (_textExtensions.contains(extension)) {
    return OpenPostSubmissionAttachmentKind.text;
  }
  return null;
}

String? _downloadUrl(dom.Document document) {
  for (final anchor in document.querySelectorAll('a[href]')) {
    final href = anchor.attributes['href'];
    if (href != null && href.contains('/download/art/')) {
      final normalized = normalizeOpenPostSubmissionUrl(href);
      if (normalized != null) return normalized;
    }
  }
  return null;
}

String? _viewerUrl(String extension, String? uploadId) {
  if (uploadId == null || uploadId.isEmpty || extension == 'doc') {
    return null;
  }
  if (extension == 'odt') return null;
  if (!_documentViewerExtensions.contains(extension)) return null;
  return 'https://www.furaffinity.net/route/document_viewer?upload_id=$uploadId';
}

String _attachmentFileName(
  String url, {
  required String extension,
  required String? fallbackTitle,
}) {
  final uri = Uri.tryParse(url);
  var fileName = uri != null && uri.pathSegments.isNotEmpty
      ? uri.pathSegments.last
      : '';
  if (fileName.isEmpty) {
    fileName = _trimmed(fallbackTitle) ?? 'submission';
  }
  fileName = fileName
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
      .replaceFirst(RegExp(r'[. ]+$'), '')
      .trim();
  if (fileName.isEmpty) fileName = 'submission';
  if (!fileName.toLowerCase().endsWith('.$extension')) {
    fileName = '$fileName.$extension';
  }
  return fileName;
}

String? _trimmed(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
