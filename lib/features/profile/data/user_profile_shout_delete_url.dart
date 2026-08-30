import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

String? findOwnShoutDeleteUrlInElement(dom.Element element, String shoutId) {
  for (final anchor in element.querySelectorAll('a[href]')) {
    final href = anchor.attributes['href'];
    if (href != null && isOwnShoutDeleteUrl(href, shoutId)) {
      return href;
    }
  }
  return null;
}

String? findOwnShoutDeleteUrlInValue(dynamic value, String shoutId) {
  if (value is String) {
    if (isOwnShoutDeleteUrl(value, shoutId)) {
      return value;
    }
    final fragment = html_parser.parseFragment(value);
    for (final anchor in fragment.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href'];
      if (href != null && isOwnShoutDeleteUrl(href, shoutId)) {
        return href;
      }
    }
    final decodedValue = (fragment.text ?? '').trim();
    if (decodedValue != value && isOwnShoutDeleteUrl(decodedValue, shoutId)) {
      return decodedValue;
    }
    return null;
  }
  if (value is Map) {
    for (final nestedValue in value.values) {
      final url = findOwnShoutDeleteUrlInValue(nestedValue, shoutId);
      if (url != null) {
        return url;
      }
    }
  } else if (value is Iterable) {
    for (final nestedValue in value) {
      final url = findOwnShoutDeleteUrlInValue(nestedValue, shoutId);
      if (url != null) {
        return url;
      }
    }
  }
  return null;
}

bool isOwnShoutDeleteUrl(String rawUrl, String shoutId) {
  final uri = Uri.tryParse(rawUrl.trim());
  if (uri == null ||
      uri.queryParameters['action'] != 'hide_shout' ||
      uri.queryParameters['comment_id'] != shoutId) {
    return false;
  }
  final key = uri.queryParameters['key'];
  return key != null && RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(key);
}
