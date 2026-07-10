import 'package:html/dom.dart' as dom;

String extractNotificationNicknameLink(dom.Element element) {
  var nicknameLink = '';
  var parentAnchor = element.querySelector(
    'span.c-usernameBlockSimple.username-underlined a[href*="/user/"]',
  );
  parentAnchor ??= element.querySelector('a[href*="/user/"]');
  final href = parentAnchor?.attributes['href'];
  if (href != null) {
    final match = RegExp(
      r'^(?:https?://(?:www\.)?furaffinity\.net)?/user/([^/]+)/?$',
    ).firstMatch(href);
    if (match != null) {
      nicknameLink = match.group(1)!;
    }
  }
  return nicknameLink;
}

String? extractNotificationUsernameFromHref(String? href) {
  if (href == null) return null;
  return RegExp(
    r'(?:https?://(?:www\.)?furaffinity\.net)?/user/([^/]+)/?',
  ).firstMatch(href)?.group(1);
}

String? extractNotificationSubmissionIdFromHref(String? href) {
  if (href == null) return null;
  return RegExp(
    r'(?:https?://(?:www\.)?furaffinity\.net)?/view/(\d+)/?',
  ).firstMatch(href)?.group(1);
}

String? extractNotificationJournalIdFromHref(String? href) {
  if (href == null) return null;
  return RegExp(
    r'(?:https?://(?:www\.)?furaffinity\.net)?/journal/(\d+)/?',
  ).firstMatch(href)?.group(1);
}

String? normalizeNotificationImageUrl(String? src) {
  final trimmed = src?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  if (trimmed.startsWith('//')) return 'https:$trimmed';
  if (trimmed.startsWith('/')) {
    return 'https://www.furaffinity.net$trimmed';
  }
  return trimmed;
}
