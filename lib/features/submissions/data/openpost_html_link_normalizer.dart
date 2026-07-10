import 'package:html/parser.dart' as html_parser;

String normalizeOpenPostTruncatedLinks(String htmlContent) {
  final document = html_parser.parse(htmlContent);
  for (final anchor in document.querySelectorAll('a.auto_link_shortened')) {
    if (anchor.text.contains('.....')) {
      final fullLink = anchor.attributes['title'];
      if (fullLink != null && fullLink.isNotEmpty) {
        anchor.text = fullLink;
      }
    }
  }
  return document.outerHtml;
}
