import 'package:html/dom.dart' as dom;

import 'package:fanotifier/features/journals/data/journal_url_builder.dart';

String? extractOpenJournalDeleteLink(
  dom.Document document,
  String uniqueNumber,
) {
  final directDeleteHref = document
      .querySelector('a[href*="/controls/deletejournal/$uniqueNumber/"]')
      ?.attributes['href'];
  final normalizedDirectHref = buildAbsoluteFaUrl(directDeleteHref);
  if (normalizedDirectHref != null) {
    return normalizedDirectHref;
  }

  final candidateAnchors = document.querySelectorAll(
    'a[onclick*="/controls/deletejournal/"], '
    'a[href*="/controls/deletejournal/"], '
    'a.delete, '
    'a.delete_journal',
  );

  for (final anchor in candidateAnchors) {
    final href = buildAbsoluteFaUrl(anchor.attributes['href']);
    if (href != null) {
      final hrefMatch =
          RegExp(r'/controls/deletejournal/(\d+)/').firstMatch(href);
      if (hrefMatch?.group(1) == uniqueNumber) {
        return href;
      }
    }

    final deleteFromOnClick = _extractDeleteLinkFromOnClick(
      anchor.attributes['onclick'],
      uniqueNumber,
    );
    if (deleteFromOnClick != null) {
      return deleteFromOnClick;
    }
  }

  return null;
}

bool looksLikeMissingJournalDocument(dom.Document document) {
  final titleLower =
      (document.querySelector('title')?.text ?? '').toLowerCase();
  final bodyLower = (document.body?.text ?? '').toLowerCase();

  return titleLower.contains('system error') ||
      bodyLower.contains('not in our database') ||
      bodyLower.contains('this journal does not exist') ||
      bodyLower.contains('this submission does not exist') ||
      bodyLower
          .contains('the item you are trying to reach is not in our database');
}

String? _extractDeleteLinkFromOnClick(
  String? onClick,
  String uniqueNumber,
) {
  if (onClick == null || onClick.trim().isEmpty) return null;
  final escapedNumber = RegExp.escape(uniqueNumber);
  final match = RegExp(
    "(/controls/deletejournal/$escapedNumber/\\?key=[^'\"\\)\\s]+)",
  ).firstMatch(onClick);
  return buildAbsoluteFaUrl(match?.group(1));
}
