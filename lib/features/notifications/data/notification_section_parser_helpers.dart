import 'package:html/dom.dart' as dom;

int extractNotificationCount(String source) {
  final match = RegExp(r'\d{1,3}(?:[,.]\d{3})*|\d+').firstMatch(source);
  if (match == null) return 0;
  return int.tryParse(
        match.group(0)!.replaceAll(RegExp(r'[,.]'), ''),
      ) ??
      0;
}

String? notificationTypeKeyFromHrefOrTitle({
  required String href,
  required String title,
}) {
  final normalizedHref = href.toLowerCase();
  final normalizedTitle = title.toLowerCase();
  if (normalizedHref.contains('#submissions') ||
      normalizedHref.contains('msg/submissions') ||
      normalizedTitle.contains('submission')) {
    return 'S';
  }
  if (normalizedHref.contains('#watches') ||
      normalizedTitle.contains('watch')) {
    return 'W';
  }
  if (normalizedHref.contains('#comments') ||
      normalizedTitle.contains('comment')) {
    return 'C';
  }
  if (normalizedHref.contains('#favorites') ||
      normalizedTitle.contains('favorite')) {
    return 'F';
  }
  if (normalizedHref.contains('#journals') ||
      normalizedTitle.contains('journal')) {
    return 'J';
  }
  if (normalizedHref.contains('#notes') ||
      normalizedHref.contains('msg/pms') ||
      normalizedTitle.contains('note')) {
    return 'N';
  }
  return null;
}

String notificationSectionHeadingFromContainer(dom.Element container) {
  final explicitHeading = (container.querySelector('h2') ??
          container.querySelector('h3') ??
          container.querySelector('legend') ??
          container.querySelector('.section-header .highlight'))
      ?.text
      .trim();
  if (explicitHeading != null && explicitHeading.isNotEmpty) {
    return normalizeNotificationSectionHeading(explicitHeading);
  }

  final lowerId = (container.id.isNotEmpty
          ? container.id
          : container.classes.join(' '))
      .toLowerCase();
  final html = container.outerHtml.toLowerCase();
  if ((lowerId.contains('submission') && lowerId.contains('comment')) ||
      html.contains('name="comments-submissions[]"')) {
    return 'Submission Comments';
  }
  if ((lowerId.contains('journal') && lowerId.contains('comment')) ||
      html.contains('name="comments-journals[]"')) {
    return 'Journal Comments';
  }
  if (lowerId.contains('journal') || html.contains('name="journals[]"')) {
    return 'Journals';
  }
  if (lowerId.contains('watch') || html.contains('name="watches[]"')) {
    return 'Watches';
  }
  if (lowerId.contains('shout') || html.contains('name="shouts[]"')) {
    return 'Shouts';
  }
  if (lowerId.contains('favorite') || html.contains('name="favorites[]"')) {
    return 'Favorites';
  }
  return 'No Title';
}

String normalizeNotificationSectionHeading(String heading) {
  final normalized = heading
      .trim()
      .replaceFirst(RegExp(r'^New\s+', caseSensitive: false), '');
  if (normalized.isEmpty) return 'No Title';
  return normalized
      .split(' ')
      .map(
        (word) =>
            word.isNotEmpty ? word[0].toUpperCase() + word.substring(1) : '',
      )
      .join(' ');
}
