import 'package:html/parser.dart' as html_parser;

String plainTextFromShoutHtml(String html) {
  return html_parser.parse(html).body?.text ?? html;
}
