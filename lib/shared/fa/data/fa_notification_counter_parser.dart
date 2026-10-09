import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'package:fanotifier/shared/fa/domain/notification_counts.dart';

NotificationCounts? parseFaNotificationCounterHeader(String html) {
  final bars = RegExp(
    r'''<li\b[^>]*\bclass\s*=\s*["'][^"']*\b(?:message-bar-desktop|noblock)\b[^"']*["'][^>]*>''',
    caseSensitive: false,
  );
  final closingTag = RegExp(r'</li\s*>', caseSensitive: false);
  for (final match in bars.allMatches(html)) {
    final closingTags = closingTag.allMatches(html, match.end).iterator;
    if (!closingTags.moveNext()) {
      continue;
    }
    final end = closingTags.current.end;
    if (end - match.start > 16384) {
      continue;
    }
    final counts = parseFaNotificationCounters(
      html_parser.parse(html.substring(match.start, end)),
    );
    if (counts != null) {
      return counts;
    }
  }
  return null;
}

NotificationCounts? parseFaNotificationCounters(dom.Document document) {
  final bar = document.querySelector('li.message-bar-desktop') ??
      document.querySelector('li.noblock');
  if (bar == null) {
    return null;
  }
  final counts = <String, int>{};
  var found = false;
  for (final link in bar.querySelectorAll('a.notification-container')) {
    final type = notificationTypeKeyFromHrefOrTitle(
      href: link.attributes['href'] ?? '',
      title: link.attributes['title'] ?? '',
    );
    if (type == null) {
      continue;
    }
    found = true;
    final title = (link.attributes['title'] ?? '').trim();
    counts[type] = extractNotificationCount(
      title.isEmpty ? link.text : title,
    );
  }
  if (!found) {
    return null;
  }
  return NotificationCounts(
    submissions: counts['S'] ?? 0,
    watches: counts['W'] ?? 0,
    comments: counts['C'] ?? 0,
    favorites: counts['F'] ?? 0,
    journals: counts['J'] ?? 0,
    notes: counts['N'] ?? 0,
  );
}

int extractNotificationCount(String source) {
  final match = RegExp(r'\d+(?:[,.]\d{3})*').firstMatch(source);
  if (match == null) {
    return 0;
  }
  return int.tryParse(
        match.group(0)!.replaceAll(RegExp(r'[,.]'), ''),
      ) ??
      0;
}

String? notificationTypeKeyFromHrefOrTitle({
  required String href,
  required String title,
}) {
  final path = href.toLowerCase();
  final label = title.toLowerCase();
  if (path.contains('#submissions') ||
      path.contains('msg/submissions') || label.contains('submission')) {
    return 'S';
  }
  if (path.contains('#watches') || label.contains('watch')) {
    return 'W';
  }
  if (path.contains('#comments') || label.contains('comment')) {
    return 'C';
  }
  if (path.contains('#favorites') || label.contains('favorite')) {
    return 'F';
  }
  if (path.contains('#journals') || label.contains('journal')) {
    return 'J';
  }
  if (path.contains('#notes') || path.contains('msg/pms') ||
      label.contains('note')) {
    return 'N';
  }
  return null;
}
