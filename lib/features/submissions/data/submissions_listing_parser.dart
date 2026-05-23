import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

import 'package:FANotifier/features/submissions/domain/submission_image_group.dart';
import 'package:FANotifier/features/submissions/domain/submissions_listing_parse_result.dart';
import 'package:FANotifier/shared/fa/fa_thumbnail_parser.dart';

SubmissionsListingParseResult parseSubmissionsListing(String html) {
  final doc = html_parser.parse(html);
  final isClassicStyle =
      doc.body?.attributes['data-static-path']?.contains('/themes/classic') ??
          false;
  final baseSubmissionsUrl = _extractBaseSubmissionsUrl(doc);
  final dateGroups = <DateImageGroup>[];

  final dateDivs = doc.querySelectorAll('.notifications-by-date');
  for (final dateDiv in dateDivs) {
    final heading = dateDiv.querySelector('h3.date-divider') ??
        dateDiv.querySelector('h4.date-divider');
    if (heading == null) continue;
    final dateLabel = heading.text.trim();

    final figures = dateDiv.querySelectorAll('figure.t-image');
    if (figures.isEmpty) continue;

    final images = <Map<String, dynamic>>[];
    for (final fig in figures) {
      final map = _extractListingData(fig);
      if (map != null) {
        images.add(map);
      }
    }
    if (images.isNotEmpty) {
      dateGroups.add(DateImageGroup(dateLabel: dateLabel, images: images));
    }
  }

  return SubmissionsListingParseResult(
    isClassicStyle: isClassicStyle,
    baseSubmissionsUrl: baseSubmissionsUrl,
    dateGroups: dateGroups,
    nextPageUrl: _extractNextPageUrl(doc),
  );
}

String? _extractBaseSubmissionsUrl(html_dom.Document doc) {
  final form = doc.querySelector('form#messages-form');
  if (form == null) return null;
  final action = form.attributes['action'] ?? '';
  if (action.isEmpty) return null;
  return action.startsWith('http') ? action : 'https://www.furaffinity.net$action';
}

Map<String, dynamic>? _extractListingData(html_dom.Element fig) {
  final data = FaThumbnailParser.extract(fig);
  if (data == null) return null;

  return {
    'postUrl': data['postUrl'],
    'uniqueNumber': data['uniqueNumber'],
    'thumbnailUrl': data['thumbnailUrl'],
    'width': data['width'],
    'height': data['height'],
    'rating': data['rating'],
    'title': data['title'],
    'author': data['author'],
    'authorProfileUrl': data['authorProfileUrl'],
    'hqUrl': null,
    'isFav': false,
    'initialIsFav': false,
    'favUrl': '',
    'unfavUrl': '',
    'detailFetchQueued': false,
  };
}

String? _extractNextPageUrl(html_dom.Document doc) {
  final nextButton = doc.querySelector('a.button.standard.more:not(.prev)');
  if (nextButton != null) {
    final href = nextButton.attributes['href'] ?? '';
    if (href.isNotEmpty) {
      return href.startsWith('http') ? href : 'https://www.furaffinity.net$href';
    }
  }

  final moreHalfList = doc.querySelectorAll('a.button.standard.more-half');
  html_dom.Element? nextLink;
  try {
    nextLink = moreHalfList.firstWhere((el) => !el.classes.contains('prev'));
  } catch (_) {
    nextLink = null;
  }
  if (nextLink != null) {
    final href = nextLink.attributes['href'] ?? '';
    if (href.isNotEmpty) {
      return href.startsWith('http') ? href : 'https://www.furaffinity.net$href';
    }
  }
  return null;
}
