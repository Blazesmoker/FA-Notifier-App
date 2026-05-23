import 'package:html/parser.dart' as html_parser;

String? findFullShortenedSubmissionLink(String htmlSource, String truncatedUrl) {
  final document = html_parser.parse(htmlSource);
  for (var anchor in document.querySelectorAll('a.auto_link_shortened')) {
    final fullLink = anchor.attributes['title'] ?? anchor.attributes['href'];
    if (fullLink != null && fullLink.isNotEmpty) {
      return fullLink;
    }
  }
  return null;
}

String? findFullShortenedCommentLink(String commentHtml, String truncatedUrl) {
  final document = html_parser.parse(commentHtml);
  for (var anchor
      in document.querySelectorAll('a.auto_link.auto_link_shortened')) {
    final fullLink = anchor.attributes['title'] ?? anchor.attributes['href'];
    if (fullLink != null && fullLink.isNotEmpty) {
      return fullLink;
    }
  }
  return null;
}

String replaceTruncatedSubmissionLinks(String htmlContent) {
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
