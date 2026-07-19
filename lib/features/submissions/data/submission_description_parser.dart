import 'package:html/parser.dart' as html_parser;

import 'package:FANotifier/features/submissions/data/openpost_html_link_normalizer.dart';

String extractSubmissionDescriptionHtml(
  String html, {
  bool allowBodyFallback = false,
}) {
  final doc = html_parser.parse(html);
  doc
      .querySelectorAll(
        'script, .footerAds, #ddmenu, .mobile-navigation, '
        '.mobile-notification-bar, #header, .online-stats, .news-block, '
        '.submission-sidebar, .leaderboardAd, .footerAds, .online-stats',
      )
      .forEach((e) => e.remove());

  final submissionDesc = doc.querySelector(
        '.submission-description-text.user-submitted-links, '
        '.submission-description.user-submitted-links, '
        '.submission-description, '
        'td.alt1[width="70%"][valign="top"][align="left"][style*="padding:8px"]',
      ) ??
      (allowBodyFallback ? doc.body : null);

  if (submissionDesc == null) {
    return '<p>No submission description found.</p>';
  }

  for (final a in submissionDesc.querySelectorAll('a[href]')) {
    final href = a.attributes['href']!;
    if (href.startsWith('/https://') || href.startsWith('/http://')) {
      a.attributes['href'] = href.substring(1);
    }
  }

  return normalizeOpenPostTruncatedLinks(submissionDesc.outerHtml);
}

String extractSubmissionDescriptionHtmlDefault(String html) {
  return extractSubmissionDescriptionHtml(html);
}

String extractSubmissionDescriptionHtmlWithBodyFallback(String html) {
  return extractSubmissionDescriptionHtml(html, allowBodyFallback: true);
}

String findFullSubmissionAutoShortenedLink(
  String htmlSource,
  String truncatedUrl,
) {
  final document = html_parser.parse(htmlSource);
  for (final anchor in document.querySelectorAll('a.auto_link_shortened')) {
    if (anchor.text.trim() == truncatedUrl) {
      return anchor.attributes['title'] ??
          anchor.attributes['href'] ??
          truncatedUrl;
    }
  }
  return truncatedUrl;
}

String plainTextFromSubmissionHtml(String html) {
  final document = html_parser.parse(html);
  return document.body?.text.trim() ?? '';
}
