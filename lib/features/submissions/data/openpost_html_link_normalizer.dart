import 'package:html/parser.dart' as html_parser;

import 'package:fanotifier/shared/fa/user_submitted_html_linkifier.dart';

String normalizeOpenPostTruncatedLinks(String htmlContent) {
  final document = html_parser.parse(
    '<div id="openpost-link-root">$htmlContent</div>',
  );
  final root = document.querySelector('#openpost-link-root')!;
  for (final anchor in root.querySelectorAll('a.auto_link_shortened')) {
    if (anchor.text.contains('.....')) {
      final fullLink = anchor.attributes['title'];
      if (fullLink != null && fullLink.isNotEmpty) {
        anchor.text = fullLink;
      }
    }
  }
  return linkifyBareWebUrlsInHtml(root.innerHtml);
}
