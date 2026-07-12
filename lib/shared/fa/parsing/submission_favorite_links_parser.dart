import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

import 'package:FANotifier/shared/fa/domain/submission_favorite_links.dart';

export 'package:FANotifier/shared/fa/domain/submission_favorite_links.dart';

SubmissionFavoriteLinks parseSubmissionFavoriteLinksFromHtml(
  String html, {
  bool includeClassicFallback = false,
}) {
  return parseSubmissionFavoriteLinksFromDocument(
    html_parser.parse(html),
    includeClassicFallback: includeClassicFallback,
  );
}

SubmissionFavoriteLinks parseSubmissionFavoriteLinksFromDocument(
  html_dom.Document document, {
  bool includeClassicFallback = false,
}) {
  var favUrl = '';
  var unfavUrl = '';

  String absoluteUrl(String href) {
    if (href.isEmpty || href.startsWith('http')) return href;
    return 'https://www.furaffinity.net$href';
  }

  void readLinks(Iterable<html_dom.Element> anchors) {
    for (final aTag in anchors) {
      final href = aTag.attributes['href'] ?? '';
      if (href.contains('/fav/')) {
        favUrl = absoluteUrl(href);
      } else if (href.contains('/unfav/')) {
        unfavUrl = absoluteUrl(href);
      }
    }
  }

  final actionSelectors = [
    '#submission-options a[href*="/fav/"]',
    '#submission-options a[href*="/unfav/"]',
    '.submission-controls-upper a[href*="/fav/"]',
    '.submission-controls-upper a[href*="/unfav/"]',
    '.favorite-nav a[href*="/fav/"]',
    '.favorite-nav a[href*="/unfav/"]',
    'div.fav a[href*="/fav/"]',
    'div.fav a[href*="/unfav/"]',
    'a.button[href*="/fav/"]',
    'a.button[href*="/unfav/"]',
  ];

  for (final selector in actionSelectors) {
    readLinks(document.querySelectorAll(selector));
  }

  if (includeClassicFallback && favUrl.isEmpty && unfavUrl.isEmpty) {
    final allLinks = document.querySelectorAll('a');
    for (final aTag in allLinks) {
      final href = aTag.attributes['href'] ?? '';
      final text = aTag.text.trim().toLowerCase();
      if (href.contains('/fav/') &&
          (text.contains('add') || text.contains('+fav'))) {
        favUrl = absoluteUrl(href);
      } else if (href.contains('/unfav/') &&
          (text.contains('remove') || text.contains('-fav'))) {
        unfavUrl = absoluteUrl(href);
      }
    }
  }

  return SubmissionFavoriteLinks(favUrl: favUrl, unfavUrl: unfavUrl);
}

String toRelativeFavoriteUrl(String url) {
  if (url.isEmpty || !url.startsWith('http')) return url;
  final uri = Uri.parse(url);
  return uri.path + (uri.hasQuery ? '?${uri.query}' : '');
}
