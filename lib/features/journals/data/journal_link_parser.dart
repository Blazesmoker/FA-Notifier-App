import 'package:html/parser.dart' as html_parser;

String? findFullShortenedJournalLink(String htmlSource, String truncatedUrl) {
  final document = html_parser.parse(htmlSource);
  for (var anchor in document.querySelectorAll('a.auto_link_shortened')) {
    if (anchor.text.trim() == truncatedUrl) {
      return anchor.attributes['title'] ?? anchor.attributes['href'];
    }
  }
  return null;
}

String replaceTruncatedJournalLinks(String htmlContent) {
  final document = html_parser.parse(htmlContent);
  for (var anchor in document.querySelectorAll('a.auto_link_shortened')) {
    if (anchor.text.contains(".....")) {
      final fullLink = anchor.attributes['title'];
      if (fullLink != null && fullLink.isNotEmpty) {
        anchor.text = fullLink;
      }
    }
  }
  return document.outerHtml;
}

bool isDeleteJournalLinkForId(String link, String journalId) {
  final match = RegExp(r'/controls/deletejournal/(\d+)/').firstMatch(link);
  return match != null && match.group(1) == journalId;
}
