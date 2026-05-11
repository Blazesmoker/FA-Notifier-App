import 'package:html/parser.dart';

import 'package:FANotifier/features/profile/domain/profile_journals_models.dart';

ProfileJournalsParseResult parseProfileJournalsHtml(String html) {
  final document = parse(html);
  final journalElements =
      document.querySelectorAll('section[id^="jid:"], table[id^="jid:"]');

  final buttonElements =
      document.querySelectorAll('a.button.standard, a.button.older');
  var hasMore = false;
  for (final button in buttonElements) {
    if (button.text.trim().toLowerCase() == 'older') {
      hasMore = true;
      break;
    }
  }

  final journalMetadata = <Map<String, dynamic>>[];

  for (final element in journalElements) {
    final sectionId = element.attributes['id'];
    final uniqueNumber = sectionId?.replaceFirst('jid:', '');
    final journalId = uniqueNumber;

    var title = element.querySelector('div.section-header > h2')?.text.trim();
    if (title == null || title.isEmpty) {
      title = element.querySelector('td.cat a')?.text.trim();
    }

    var datePosted = element
        .querySelector(
            'div.section-header > span.font-small > strong > span.popup_date')
        ?.attributes['title'];
    if (datePosted == null || datePosted.isEmpty) {
      datePosted = element.querySelector('span.popup_date')?.attributes['title'];
    }

    var contentHtml = element
        .querySelector('div.section-body > div.journal-body.user-submitted-links')
        ?.innerHtml
        .trim();
    if (contentHtml == null || contentHtml.isEmpty) {
      contentHtml =
          element.querySelector('td.addpad div.no_overflow')?.innerHtml.trim();
    }

    var commentsLink = element
        .querySelector('div.section-footer a[href^="/journal/"]')
        ?.attributes['href'];
    var commentsText = element
        .querySelector('div.section-footer a[href^="/journal/"] > span.font-large')
        ?.text
        .trim();
    if (commentsLink == null || commentsText == null || commentsText.isEmpty) {
      final commentAnchor =
          element.querySelector('td[align="right"] a[href^="/journal/"]');
      if (commentAnchor != null) {
        commentsLink = commentAnchor.attributes['href'];
        final regex = RegExp(r'Comments\s*\((\d+)\)');
        final match = regex.firstMatch(commentAnchor.text);
        commentsText = match != null ? match.group(1) : '0';
      }
    }
    final commentsCount = int.tryParse(commentsText ?? '0') ?? 0;

    if (uniqueNumber != null &&
        journalId != null &&
        title != null &&
        datePosted != null &&
        contentHtml != null) {
      journalMetadata.add({
        'journalId': journalId,
        'uniqueNumber': uniqueNumber,
        'title': title,
        'datePosted': datePosted,
        'contentHtml': contentHtml,
        'commentsLink': commentsLink,
        'commentsCount': commentsCount,
      });
    }
  }

  return ProfileJournalsParseResult(
    journals: journalMetadata,
    hasMore: hasMore,
  );
}
