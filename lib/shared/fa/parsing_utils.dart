// parsing_utils.dart

import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart'    as dom;

/// Synchronous HTML parse function.
/// Must be a top-level function for use with compute().
dom.Document _parseHtmlSync(String html) {
  return html_parser.parse(html);
}

/// Asynchronously parse HTML in a background isolate via compute().
Future<dom.Document> parseHtml(String html) async {
  return compute(_parseHtmlSync, html);
}
