import 'dart:convert';

import 'package:html/parser.dart' as html_parser;

String? parseNoteSubmissionHighQualityImageUrl(List<int> bodyBytes) {
  final body = utf8.decode(bodyBytes, allowMalformed: true);
  final document = html_parser.parse(body);
  final image = document.querySelector(
    '.submission-area img#submissionImg[src], img#submissionImg[src]',
  );
  final rawUrl = image?.attributes['data-fullview-src'] ??
      image?.attributes['src'];
  if (rawUrl == null || rawUrl.trim().isEmpty) return null;
  final url = rawUrl.trim();
  if (url.startsWith('//')) return 'https:$url';
  if (url.startsWith('/')) return 'https://www.furaffinity.net$url';
  return url;
}

String noteSubmissionImageExtension(String url, String? contentType) {
  final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
  for (final extension in ['.png', '.jpg', '.jpeg', '.gif', '.webp']) {
    if (path.endsWith(extension)) return extension;
  }
  return switch ((contentType ?? '').toLowerCase().split(';').first.trim()) {
    'image/png' => '.png',
    'image/gif' => '.gif',
    'image/webp' => '.webp',
    _ => '.jpg',
  };
}
