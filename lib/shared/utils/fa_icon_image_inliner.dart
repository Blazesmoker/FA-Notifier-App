import 'dart:convert';

import 'package:FANotifier/shared/fa/fa_media_auth.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

Future<String> inlineFaIconUsernameImages(String html) async {
  final document = html_parser.parse(html);
  final images = document.querySelectorAll('a.iconusername img[src]');
  if (images.isEmpty) {
    return html;
  }

  final srcToDataUri = <String, String>{};
  final uniqueSources = images
      .map((image) => image.attributes['src'])
      .whereType<String>()
      .toSet();

  await Future.wait(
    uniqueSources.map((src) async {
      final resolvedUrl = FaMediaAuth.normalizeUrl(src);
      if (!FaMediaAuth.isFaUrl(resolvedUrl)) {
        return;
      }
      final dataUri = await _fetchDataUri(resolvedUrl);
      if (dataUri != null) {
        srcToDataUri[src] = dataUri;
      }
    }),
  );

  if (srcToDataUri.isEmpty) {
    return html;
  }

  for (final image in images) {
    final src = image.attributes['src'];
    final dataUri = src == null ? null : srcToDataUri[src];
    if (dataUri != null) {
      image.attributes['src'] = dataUri;
    }
  }

  return document.body?.innerHtml ?? html;
}

Future<String?> _fetchDataUri(String url) async {
  try {
    final headers = await FaMediaAuth.headersForUrl(url);
    final response = await http.get(
      Uri.parse(url),
      headers: headers,
    );
    final contentType = response.headers['content-type']?.split(';').first;
    if (response.statusCode != 200 ||
        contentType == null ||
        !contentType.startsWith('image/')) {
      return null;
    }
    return 'data:$contentType;base64,${base64Encode(response.bodyBytes)}';
  } catch (_) {
    return null;
  }
}
