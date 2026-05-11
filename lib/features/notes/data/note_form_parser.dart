import 'package:html/parser.dart' as html_parser;

String? parseNewMessageKey(String html) {
  final document = html_parser.parse(html);
  return document
      .querySelector('form#note-form input[name="key"]')
      ?.attributes['value'];
}
