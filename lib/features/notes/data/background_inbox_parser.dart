import 'package:html/dom.dart' as dom;

import 'package:FANotifier/core/utils/utils.dart';
import 'package:FANotifier/features/notes/domain/background_inbox_models.dart';
import 'package:FANotifier/features/notes/domain/message_model.dart';
import 'package:FANotifier/shared/fa/domain/notification_counts.dart';

BackgroundInboxPage parseBackgroundInboxPage(
  dom.Document document, {
  required bool includeTopbarCounts,
}) {
  return BackgroundInboxPage(
    messages: parseBackgroundInboxMessages(document),
    topbarCounts:
        includeTopbarCounts ? parseBackgroundInboxTopbarCounts(document) : null,
  );
}

List<Message> parseBackgroundInboxMessages(dom.Document document) {
  var noteElements = document.querySelectorAll(
      '.message-center-pms-note-list-view .note-list-container');
  if (noteElements.isEmpty) {
    noteElements = document.querySelectorAll('#notes-list .note-list-container');
  }
  if (noteElements.isEmpty) {
    final bool isClassic =
        document.querySelector('body[data-static-path="/themes/classic"]') !=
            null;
    if (isClassic) {
      List<dom.Element> classicRows =
          List.from(document.querySelectorAll('#notes-list tr.note'));
      if (classicRows.isNotEmpty &&
          classicRows.last.querySelector('input[type="checkbox"]') == null) {
        classicRows.removeLast();
      }
      noteElements = classicRows;
    } else {
      noteElements = document.querySelectorAll('td.note-list-container tr.note');
    }
  }

  final result = <Message>[];
  for (var noteEl in noteElements) {
    final subject = noteEl
            .querySelector(
                '.note-list-subject-container .c-noteListItem__subject')
            ?.text
            .trim() ??
        noteEl.querySelector('a.notelink.note-read.read')?.text.trim() ??
        noteEl.querySelector('a.notelink.note-unread.unread')?.text.trim() ??
        noteEl.querySelector('a.notelink')?.text.trim() ??
        'No subject';
    final sender = noteEl
            .querySelector('.c-usernameBlock__displayName .js-displayName')
            ?.text
            .trim() ??
        noteEl
            .querySelector(
                'div.c-usernameBlock.marquee-container a.c-usernameBlock__displayName.js-displayName-block span.js-displayName')
            ?.text
            .trim() ??
        'Unknown sender';
    final aTag = noteEl.querySelector('.note-list-subject-container a') ??
        noteEl.querySelector('a.notelink.note-unread.unread') ??
        noteEl.querySelector('a.notelink.note-read.read') ??
        noteEl.querySelector('a.notelink');
    final classicLink = aTag?.attributes['href'] ?? '';
    final String link = classicLink.startsWith('/viewmessage/')
        ? classicLink
        : (aTag?.attributes['newhref'] ?? classicLink);
    final checkbox = noteEl.querySelector('input[type="checkbox"]');
    final idFromLink = extractMessageId(link);
    final id = idFromLink.isNotEmpty
        ? idFromLink
        : (checkbox?.attributes['value'] ??
            (link.isNotEmpty ? link : '$sender|$subject|unknown-date'));
    final date =
        noteEl.querySelector('.note-list-senddate span')?.attributes['title'] ??
            noteEl
                .querySelector('td.alt1.nowrap span.popup_date')
                ?.attributes['title'] ??
            noteEl.querySelector('span.popup_date')?.attributes['title'] ??
            'Unknown date';
    final isUnread = noteEl.querySelector('img.unread') != null ||
        noteEl.querySelector('img[src*="pms-unread.png"]') != null ||
        noteEl.querySelector('a.notelink.note-unread.unread') != null;
    result.add(Message(
      id: id,
      subject: subject,
      sender: sender,
      recipient: '',
      date: date,
      link: link,
      isUnread: isUnread,
    ));
  }
  return result;
}

NotificationCounts? parseBackgroundInboxTopbarCounts(dom.Document document) {
  final links = document.querySelectorAll(
      'li.message-bar-desktop a.notification-container, li.noblock a.notification-container');
  if (links.isEmpty) return null;

  final counts = <String, int>{
    'S': 0,
    'W': 0,
    'C': 0,
    'F': 0,
    'J': 0,
    'N': 0,
  };
  for (final link in links) {
    final href = link.attributes['href'] ?? '';
    final title = (link.attributes['title'] ?? '').trim();
    final text = link.text.trim();
    final key = _backgroundTopbarTypeKey(href: href, title: title);
    if (key == null) continue;
    counts[key] =
        _extractBackgroundTopbarCount(title.isNotEmpty ? title : text);
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

String? _backgroundTopbarTypeKey({
  required String href,
  required String title,
}) {
  final h = href.toLowerCase();
  final t = title.toLowerCase();
  if (h.contains('msg/submissions') || t.contains('submission')) return 'S';
  if (h.contains('#watches') || t.contains('watch')) return 'W';
  if (h.contains('#comments') || t.contains('comment')) return 'C';
  if (h.contains('#favorites') || t.contains('favorite')) return 'F';
  if (h.contains('#journals') || t.contains('journal')) return 'J';
  if (h.contains('msg/pms') || t.contains('note')) return 'N';
  return null;
}

int _extractBackgroundTopbarCount(String text) {
  final match = RegExp(r'\d{1,3}(?:[,.]\d{3})*|\d+').firstMatch(text);
  if (match == null) return 0;
  return int.tryParse(match.group(0)!.replaceAll(RegExp(r'[,.]'), '')) ?? 0;
}
