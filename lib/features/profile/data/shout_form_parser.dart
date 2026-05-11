import 'package:html/parser.dart' as html_parser;

String? parseShoutKey(String html) {
  final document = html_parser.parse(html);
  var key = document
      .querySelector('form.shout-post-form input[name="key"]')
      ?.attributes['value'];
  key ??= document.querySelector('form#JSForm input[name="key"]')?.attributes['value'];
  return key;
}
