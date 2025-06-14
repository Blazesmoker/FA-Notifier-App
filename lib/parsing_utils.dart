// parsing_utils.dart

import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart'    as dom;

dom.Document parseHtml(String html) {
  return html_parser.parse(html);
}