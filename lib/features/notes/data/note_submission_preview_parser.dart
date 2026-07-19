import 'dart:convert';

import 'package:FANotifier/features/notes/domain/note_image_preview_link.dart';
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

List<String> parseNotePreviewPageImageUrls(
  NoteImagePreviewLink link,
  List<int> bodyBytes,
) {
  switch (link.source) {
    case NoteImagePreviewSource.imgur:
      return _parseImgurImageUrls(bodyBytes, link.uri);
    case NoteImagePreviewSource.googleImages:
      final imageUrl = _parseGoogleImagesOriginalUrl(
        link.uri,
        bodyBytes,
      );
      return imageUrl == null ? const [] : [imageUrl];
    case NoteImagePreviewSource.googleImageResult:
    case NoteImagePreviewSource.googleImageShare:
      return _parseGoogleImageResultUrls(bodyBytes, link.uri);
    case NoteImagePreviewSource.furAffinity:
    case NoteImagePreviewSource.googleDrive:
    case NoteImagePreviewSource.dropbox:
      return const [];
  }
}

String notePreviewCacheKey(NoteImagePreviewLink link) {
  if (link.source == NoteImagePreviewSource.googleImages) {
    final selectedId = googleImagesSelectedId(link);
    if (selectedId != null) return 'google-images:$selectedId';
  }
  return link.url;
}

String? googleImagesSelectedId(NoteImagePreviewLink link) {
  if (link.source != NoteImagePreviewSource.googleImages) return null;
  return _googleImagesSelectedId(link.uri);
}

String? directNotePreviewImageUrl(NoteImagePreviewLink link) {
  switch (link.source) {
    case NoteImagePreviewSource.googleDrive:
      final fileId = link.uri.pathSegments[2];
      return Uri.https(
        'drive.usercontent.google.com',
        '/download',
        {
          'id': fileId,
          'export': 'download',
          'confirm': 't',
        },
      ).toString();
    case NoteImagePreviewSource.dropbox:
      final queryParameters = Map<String, String>.from(
        link.uri.queryParameters,
      )..['dl'] = '1';
      return link.uri
          .replace(
            queryParameters: queryParameters,
          )
          .removeFragment()
          .toString();
    case NoteImagePreviewSource.googleImageResult:
      return _httpImageUrl(link.uri.queryParameters['imgurl']);
    case NoteImagePreviewSource.furAffinity:
    case NoteImagePreviewSource.imgur:
    case NoteImagePreviewSource.googleImages:
    case NoteImagePreviewSource.googleImageShare:
      return null;
  }
}

Uri notePreviewPageUri(NoteImagePreviewLink link) {
  return link.source == NoteImagePreviewSource.googleImages
      ? link.uri.removeFragment()
      : link.uri;
}

List<String> _parseGoogleImageResultUrls(
  List<int> bodyBytes,
  Uri pageUri,
) {
  final body = utf8.decode(bodyBytes, allowMalformed: true);
  final document = html_parser.parse(body);
  final urls = _parseOpenGraphImageUrls(bodyBytes, pageUri);
  for (final selector in [
    'img.sFlh5c[src]',
    'img[jsname="kn3ccd"][src]',
  ]) {
    for (final image in document.querySelectorAll(selector)) {
      final value = image.attributes['src'];
      if (value == null || value.isEmpty) continue;
      final url = _httpImageUrl(pageUri.resolve(value).toString());
      if (url != null && !urls.contains(url)) urls.add(url);
    }
  }
  return urls;
}

List<String> _parseImgurImageUrls(
  List<int> bodyBytes,
  Uri pageUri,
) {
  final urls = _parseOpenGraphImageUrls(bodyBytes, pageUri);
  final body = utf8
      .decode(bodyBytes, allowMalformed: true)
      .replaceAll(r'\/', '/');
  final matches = RegExp(
    r'''https://i\.imgur\.com/[A-Za-z0-9]+\.(?:png|jpe?g|gif|webp)(?:\?[^"'<>\\\s]*)?''',
    caseSensitive: false,
  ).allMatches(body);
  for (final match in matches) {
    final value = match.group(0);
    if (value == null) continue;
    final uri = Uri.tryParse(value);
    if (uri == null || uri.pathSegments.isEmpty) continue;
    final url = Uri.https(
      'i.imgur.com',
      '/${uri.pathSegments.join('/')}',
    ).toString();
    if (!urls.contains(url)) urls.add(url);
  }
  return urls;
}

List<String> _parseOpenGraphImageUrls(
  List<int> bodyBytes,
  Uri pageUri,
) {
  final body = utf8.decode(bodyBytes, allowMalformed: true);
  final document = html_parser.parse(body);
  final selectors = [
    'meta[property="og:image:secure_url"][content]',
    'meta[property="og:image"][content]',
    'meta[name="twitter:image"][content]',
    'meta[name="twitter:image:src"][content]',
  ];
  final urls = <String>[];
  for (final selector in selectors) {
    final value = document.querySelector(selector)?.attributes['content'];
    if (value == null || value.trim().isEmpty) continue;
    final resolved = pageUri.resolve(value.trim());
    if (resolved.scheme == 'http' || resolved.scheme == 'https') {
      final url = resolved.removeFragment().toString();
      if (!urls.contains(url)) urls.add(url);
    }
  }
  return urls;
}

String? _parseGoogleImagesOriginalUrl(
  Uri sourceUri,
  List<int> bodyBytes,
) {
  final selectedId = _googleImagesSelectedId(sourceUri);
  if (selectedId == null) return null;
  final body = utf8.decode(bodyBytes, allowMalformed: true);
  final resultPattern = RegExp(
    r'\[0,"' +
        RegExp.escape(selectedId) +
        r'",\["[^"]+",\d+,\d+\],\["([^"]+)",\d+,\d+\]',
  );
  final rawUrl = resultPattern.firstMatch(body)?.group(1);
  if (rawUrl == null || rawUrl.isEmpty) return null;
  try {
    final decoded = jsonDecode('"$rawUrl"');
    if (decoded is! String) return null;
    final uri = Uri.tryParse(decoded);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    return uri.toString();
  } on FormatException {
    return null;
  }
}

String? _googleImagesSelectedId(Uri uri) {
  String? encoded;
  try {
    encoded = Uri.splitQueryString(uri.fragment)['sv'];
  } on FormatException {
    return null;
  }
  if (encoded == null || encoded.isEmpty) return null;
  try {
    final bytes = base64Url.decode(base64Url.normalize(encoded));
    for (var index = 1; index < bytes.length - 1; index++) {
      if (bytes[index] != 0x65 || bytes[index + 1] != 0x2D) continue;
      final valueLength = bytes[index - 1];
      if (valueLength < 8 ||
          valueLength >= 128 ||
          index + valueLength > bytes.length) {
        continue;
      }
      final value = latin1.decode(
        bytes.sublist(index, index + valueLength),
      );
      if (!RegExp(r'^e-[A-Za-z0-9_-]+$').hasMatch(value)) continue;
      return value.substring(2);
    }
    return null;
  } on FormatException {
    return null;
  }
}

String? _httpImageUrl(String? value) {
  if (value == null || value.isEmpty) return null;
  final uri = Uri.tryParse(value);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }
  return uri.removeFragment().toString();
}

String noteSubmissionImageExtension(String url, String? contentType) {
  final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
  for (final extension in [
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.webp',
    '.avif',
  ]) {
    if (path.endsWith(extension)) return extension;
  }
  return switch ((contentType ?? '').toLowerCase().split(';').first.trim()) {
    'image/png' => '.png',
    'image/gif' => '.gif',
    'image/webp' => '.webp',
    'image/avif' => '.avif',
    _ => '.jpg',
  };
}
