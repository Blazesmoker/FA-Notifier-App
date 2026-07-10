import 'package:html/dom.dart' as dom;

class ParsedNotificationSubmissionPreview {
  const ParsedNotificationSubmissionPreview({
    required this.url,
    required this.shouldCache,
  });

  final String url;
  final bool shouldCache;
}

String? parseNotificationAvatarUrl(dom.Document document) {
  final isClassic = document
          .querySelector('body')
          ?.attributes['data-static-path'] ==
      '/themes/classic';
  final avatarElement = isClassic
      ? document.querySelector('td.alt1 a img.avatar')
      : document.querySelector('userpage-nav-avatar a.current img');
  var src = avatarElement?.attributes['src'];
  if (src == null || src.isEmpty) return null;
  if (src.startsWith('//')) src = 'https:$src';
  return src;
}

ParsedNotificationSubmissionPreview? parseNotificationSubmissionPreview(
  dom.Document document,
) {
  final noticeSection =
      document.querySelector('section.aligncenter.notice-message');
  if (noticeSection != null &&
      noticeSection.text
          .contains('This submission contains Mature or Adult content')) {
    return const ParsedNotificationSubmissionPreview(
      url: 'assets/images/nsfw.png',
      shouldCache: false,
    );
  }

  final images = document.querySelectorAll('img');
  for (final image in images) {
    if (image.attributes.containsKey('data-preview-src')) {
      var src = image.attributes['data-preview-src'];
      if (src != null && src.isNotEmpty) {
        if (src.startsWith('//')) src = 'https:$src';
        return ParsedNotificationSubmissionPreview(
          url: src,
          shouldCache: true,
        );
      }
    }
  }

  final fallbackElement = document.querySelector('img#submissionImg');
  var fallbackSrc = fallbackElement?.attributes['src'];
  if (fallbackSrc != null && fallbackSrc.isNotEmpty) {
    if (fallbackSrc.startsWith('//')) fallbackSrc = 'https:$fallbackSrc';
    return ParsedNotificationSubmissionPreview(
      url: fallbackSrc,
      shouldCache: true,
    );
  }
  return null;
}
