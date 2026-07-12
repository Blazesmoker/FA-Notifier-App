import 'package:FANotifier/core/fa/fa_media_auth.dart';
import 'package:html/parser.dart' as html_parser;

Future<String> inlineFaIconUsernameImages(String html) {
  final document = html_parser.parse(html);
  final images = document.querySelectorAll('a.iconusername img[src]');
  if (images.isEmpty) {
    return Future.value(html);
  }

  for (final image in images) {
    final src = image.attributes['src'];
    if (src == null) {
      continue;
    }
    final resolvedUrl = FaMediaAuth.normalizeUrl(src);
    if (FaMediaAuth.isFaUrl(resolvedUrl)) {
      image.attributes['src'] = resolvedUrl;
    }
  }

  return Future.value(document.body?.innerHtml ?? html);
}
