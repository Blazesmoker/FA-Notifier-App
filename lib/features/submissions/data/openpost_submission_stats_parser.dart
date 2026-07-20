import 'package:html/dom.dart' as dom;

import 'package:fanotifier/core/utils/html_tags_debug.dart';
import 'package:fanotifier/features/submissions/domain/openpost_parse_sections.dart';

OpenPostSubmissionStats parseOpenPostSubmissionStats(dom.Document document) {
  dom.Element? submissionPageStat(String label) {
    final containers = document.querySelectorAll('.submission-page-stats > div');
    for (final container in containers) {
      final title = container.attributes['title']?.trim().toLowerCase();
      final hasLabel = title == label.toLowerCase() ||
          container.querySelector('.highlight')?.text.trim().toLowerCase() ==
              label.toLowerCase();
      if (!hasLabel) continue;
      for (final child in container.children) {
        if (child.classes.contains('highlight')) continue;
        final text = child.text.trim();
        if (text.isNotEmpty) {
          return dom.Element.tag('span')..text = text;
        }
      }
    }
    return null;
  }

  var viewCountElement = logQuery(document, '.views .font-large');
  viewCountElement ??= submissionPageStat('Views');
  if (viewCountElement == null) {
    final statsContainer = logQuery(document, 'td.alt1.stats-container');
    if (statsContainer != null) {
      final boldElements = statsContainer.getElementsByTagName('b');
      String? viewsText;
      for (final bold in boldElements) {
        if (bold.text.trim() == 'Views:') {
          final nodes = bold.parent?.nodes;
          if (nodes != null) {
            final index = nodes.indexOf(bold);
            if (index != -1 && index < nodes.length - 1) {
              viewsText = nodes[index + 1].text?.trim();
            }
          }
          break;
        }
      }
      if (viewsText != null && viewsText.isNotEmpty) {
        viewCountElement = dom.Element.tag('span')..text = viewsText;
      }
    }
  }
  final viewCount =
      int.tryParse(viewCountElement?.text.trim() ?? '0') ?? 0;

  var commentsCountElement = logQuery(document, '.comments .font-large');
  commentsCountElement ??= submissionPageStat('Comments');
  if (commentsCountElement == null) {
    final statsContainer = logQuery(document, 'td.alt1.stats-container');
    if (statsContainer != null) {
      final boldElements = statsContainer.getElementsByTagName('b');
      String? commentsText;
      for (final bold in boldElements) {
        if (bold.text.trim() == 'Comments:') {
          final nodes = bold.parent?.nodes;
          if (nodes != null) {
            final index = nodes.indexOf(bold);
            if (index != -1 && index < nodes.length - 1) {
              commentsText = nodes[index + 1].text?.trim();
            }
          }
          break;
        }
      }
      if (commentsText != null && commentsText.isNotEmpty) {
        commentsCountElement = dom.Element.tag('span')..text = commentsText;
      }
    }
  }
  final commentsCount =
      int.tryParse(commentsCountElement?.text.trim() ?? '0') ?? 0;

  String? rating;
  dom.Element? ratingElement = logQuery(document, '.rating .font-large') ??
      logQuery(document, 'div[class*="c-contentRating--"]') ??
      logQuery(document, 'span[class*="c-contentRating--"]');
  if (ratingElement == null) {
    final statsContainer = logQuery(document, 'td.alt1.stats-container');
    if (statsContainer != null) {
      final boldElements = statsContainer.getElementsByTagName('b');
      for (final bold in boldElements) {
        if (bold.text.trim() == 'Rating:') {
          final nodes = bold.parent?.nodes;
          if (nodes != null) {
            final index = nodes.indexOf(bold);
            if (index != -1 && index < nodes.length - 1) {
              final ratingText =
                  nodes[index + 1].text?.trim().toLowerCase() ?? '';
              if (ratingText.contains('general')) rating = 'general';
              if (ratingText.contains('mature')) rating = 'mature';
              if (ratingText.contains('adult')) rating = 'adult';
            }
          }
          break;
        }
      }
    }
  }
  if (rating == null && ratingElement != null) {
    if (ratingElement.classes.contains('c-contentRating--general')) {
      rating = 'general';
    }
    if (ratingElement.classes.contains('c-contentRating--mature')) {
      rating = 'mature';
    }
    if (ratingElement.classes.contains('c-contentRating--adult')) {
      rating = 'adult';
    }
  }
  if (rating == null && ratingElement != null) {
    final text = ratingElement.text.trim().toLowerCase();
    if (text.contains('general')) rating = 'general';
    if (text.contains('mature')) rating = 'mature';
    if (text.contains('adult')) rating = 'adult';
  }

  var favoritesCountElement = logQuery(document, '.favorites .font-large');
  favoritesCountElement ??= submissionPageStat('Favorites');
  if (favoritesCountElement == null) {
    final statsContainer = logQuery(document, 'td.alt1.stats-container');
    if (statsContainer != null) {
      final boldElements = statsContainer.getElementsByTagName('b');
      String? favoritesText;
      for (final bold in boldElements) {
        if (bold.text.trim() == 'Favorites:') {
          final parentNodes = bold.parent?.nodes;
          if (parentNodes != null) {
            var index = parentNodes.indexOf(bold);
            while (index + 1 < parentNodes.length) {
              index++;
              final sibling = parentNodes[index];
              if (sibling is dom.Element && sibling.localName == 'a') {
                favoritesText = sibling.text.trim();
                break;
              } else if (sibling is dom.Text) {
                final trimmed = sibling.text.trim();
                if (trimmed.isNotEmpty) {
                  favoritesText = trimmed;
                  break;
                }
              }
            }
          }
          break;
        }
      }
      if (favoritesText != null && favoritesText.isNotEmpty) {
        favoritesCountElement = dom.Element.tag('span')..text = favoritesText;
      }
    }
  }
  final favoritesCount =
      int.tryParse(favoritesCountElement?.text.trim() ?? '0') ?? 0;

  var favLinkElement = logQuery(document, '.favorite-nav a[href^="/fav/"]') ??
      logQuery(document, 'a[href^="/fav/"].button');
  var unfavLinkElement =
      logQuery(document, '.favorite-nav a[href^="/unfav/"]') ??
          logQuery(document, 'a[href^="/unfav/"].button');
  if (favLinkElement == null) {
    final actionContainers =
        logQueryAll(document, 'div.alt1.actions.aligncenter');
    for (final actions in actionContainers) {
      final boldElements = actions.getElementsByTagName('b');
      for (final bold in boldElements) {
        final anchor = bold.querySelector('a');
        if (anchor != null &&
            (anchor.attributes['href'] ?? '').startsWith('/fav/')) {
          favLinkElement = anchor;
          break;
        }
      }
      if (favLinkElement != null) break;
    }
  }
  if (unfavLinkElement == null) {
    final actionContainers =
        logQueryAll(document, 'div.alt1.actions.aligncenter');
    for (final actions in actionContainers) {
      final boldElements = actions.getElementsByTagName('b');
      for (final bold in boldElements) {
        final anchor = bold.querySelector('a');
        if (anchor != null &&
            (anchor.attributes['href'] ?? '').startsWith('/unfav/')) {
          unfavLinkElement = anchor;
          break;
        }
      }
      if (unfavLinkElement != null) break;
    }
  }

  return OpenPostSubmissionStats(
    viewCount: viewCount,
    commentsCount: commentsCount,
    rating: rating,
    favoritesCount: favoritesCount,
    favLink: favLinkElement?.attributes['href'],
    unfavLink: unfavLinkElement?.attributes['href'],
  );
}
