import 'package:html/parser.dart' as html_parser;

String extractUserDescriptionHtml(String html, {bool allowBodyFallback = false}) {
  final doc = html_parser.parse(html);

  doc
      .querySelectorAll(
        'script, .footerAds, #ddmenu, .mobile-navigation, '
        '.mobile-notification-bar, #header, .userpage-layout-left-col, '
        '.userpage-layout-right-col, #footer, .online-stats, .news-block',
      )
      .forEach((e) => e.remove());

  final userDescElem = doc.querySelector('section.userpage-layout-profile') ??
      doc.querySelector('td.ldot') ??
      (allowBodyFallback ? doc.body : null);

  if (userDescElem == null) {
    return '<p>No user profile found.</p>';
  }

  if (userDescElem.localName == 'section') {
    return userDescElem.outerHtml.trim();
  }

  if (userDescElem.localName == 'td') {
    final classicHtml = userDescElem.innerHtml;
    const headerMarker = '<b>Artist Profile:</b><br>';
    final splitIndex = classicHtml.indexOf(headerMarker);
    if (splitIndex != -1) {
      return classicHtml.substring(splitIndex + headerMarker.length).trim();
    }
    return classicHtml.trim();
  }

  return userDescElem.outerHtml.trim();
}

String extractUserDescriptionHtmlDefault(String html) {
  return extractUserDescriptionHtml(html);
}

String extractUserDescriptionHtmlWithBodyFallback(String html) {
  return extractUserDescriptionHtml(html, allowBodyFallback: true);
}

String? findFullAutoShortenedLink(
  String htmlSource,
  String truncatedUrl,
) {
  final document = html_parser.parse(htmlSource);
  for (final anchor in document.querySelectorAll('a.auto_link_shortened')) {
    if (anchor.text.trim() == truncatedUrl) {
      return anchor.attributes['title'] ?? anchor.attributes['href'];
    }
  }
  return null;
}

String plainTextFromHtml(String html) {
  final document = html_parser.parse(html);
  return document.body?.text.trim() ?? '';
}
