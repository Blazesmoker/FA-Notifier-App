import 'package:html/parser.dart' as html_parser;

import 'package:FANotifier/features/profile/domain/profile_shout_text_repository.dart';

class ShoutTextParser implements ProfileShoutTextRepository {
  const ShoutTextParser();

  @override
  String plainTextFromHtml(String html) {
    return plainTextFromShoutHtml(html);
  }
}

String plainTextFromShoutHtml(String html) {
  return html_parser.parse(html).body?.text ?? html;
}
