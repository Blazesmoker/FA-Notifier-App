import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

String linkifyBareWebUrlsInHtml(String html) {
  final document = html_parser.parse(
    '<div id="user-submitted-link-root">$html</div>',
  );
  final root = document.querySelector('#user-submitted-link-root')!;
  final textNodes = <dom.Text>[];

  void collectTextNodes(dom.Node node, bool excluded) {
    final localName = node is dom.Element ? node.localName : null;
    final excludesChildren = excluded ||
        localName == 'a' ||
        localName == 'script' ||
        localName == 'style';
    if (node is dom.Text && !excludesChildren) {
      textNodes.add(node);
    }
    for (final child in node.nodes) {
      collectTextNodes(child, excludesChildren);
    }
  }

  collectTextNodes(root, false);

  for (final textNode in textNodes) {
    final text = textNode.data;
    final matches = _webUrlPattern.allMatches(text).toList();
    if (matches.isEmpty) continue;
    final parent = textNode.parentNode;
    if (parent == null) continue;
    var offset = 0;

    for (final match in matches) {
      final rawUrl = match.group(0)!;
      final url = _withoutTrailingPunctuation(rawUrl);
      if (url.isEmpty) continue;
      final urlEnd = match.start + url.length;
      if (match.start > offset) {
        parent.insertBefore(
          dom.Text(text.substring(offset, match.start)),
          textNode,
        );
      }
      final anchor = dom.Element.tag('a')
        ..attributes['href'] = url
        ..text = url;
      parent.insertBefore(anchor, textNode);
      offset = urlEnd;
    }

    if (offset < text.length) {
      parent.insertBefore(dom.Text(text.substring(offset)), textNode);
    }
    textNode.remove();
  }

  return root.innerHtml;
}

final RegExp _webUrlPattern = RegExp(
  r'''https?://[^\s<>"']+''',
  caseSensitive: false,
);

String _withoutTrailingPunctuation(String value) {
  var result = value;
  while (result.isNotEmpty &&
      const {'.', ',', ';', ':', '!', '?', ')', ']', '}'}
          .contains(result[result.length - 1])) {
    result = result.substring(0, result.length - 1);
  }
  return result;
}
