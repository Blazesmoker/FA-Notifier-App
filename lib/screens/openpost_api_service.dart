import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import '../parsing_utils.dart';
import '../utils/html_tags_debug.dart';


class OpenPostParseResult {
  OpenPostParseResult({
    required this.currentUsername,
    required this.username,
    required this.linkUsername,
    required this.profileImageUrl,
    required this.submissionTitle,
    required this.fullViewImageUrl,
    required this.submissionDescription,
    required this.publicationTimeRaw,
    required this.rating,
    required this.favoritesCount,
    required this.viewCount,
    required this.commentsCount,
    required this.favLink,
    required this.unfavLink,
    required this.isFavorited,
    required this.category,
    required this.type,
    required this.species,
    required this.gender,
    required this.size,
    required this.fileSize,
    required this.keywords,
    required this.keywordTags,
    required this.metaKeywordTags,
    required this.tagBlocklistNonce,
    required this.imageWidth,
    required this.imageHeight,
  });

  final String? currentUsername;
  final String? username;
  final String? linkUsername;
  final String? profileImageUrl;
  final String? submissionTitle;
  final String? fullViewImageUrl;
  final String? submissionDescription;
  final String? publicationTimeRaw;
  /// "general" | "mature" | "adult" | null
  final String? rating;
  final int favoritesCount;
  final int viewCount;
  final int commentsCount;
  final String? favLink;
  final String? unfavLink;
  final bool isFavorited;
  final String? category;
  final String? type;
  final String? species;
  final String? gender;
  final String? size;
  final String? fileSize;
  final List<String> keywords;
  final List<FaPostTag> keywordTags;
  final List<FaPostTag> metaKeywordTags;
  final String? tagBlocklistNonce;
  final double? imageWidth;
  final double? imageHeight;
}

class FaPostTag {
  const FaPostTag({
    required this.name,
    required this.isBlocked,
    required this.isMeta,
    required this.isSearchable,
  });

  final String name;
  final bool isBlocked;
  final bool isMeta;
  final bool isSearchable;
}

class OpenPostApiService {
  /// Parses the main post document and returns structured data.
  static OpenPostParseResult parsePostDocument(dom.Document document) {
    // Current logged-in username
    final currentUserElem = logQuery(document, '#my-username') ??
        logQuery(document, 'span#my-username');
    String? currentUsername;
    if (currentUserElem != null) {
      final fullText = currentUserElem.text.trim();
      final match = RegExp(r'\(([^)]+)\)').firstMatch(fullText);
      if (match != null && match.groupCount >= 1) {
        currentUsername = match.group(1)?.trim();
      } else {
        currentUsername = fullText;
      }
    }

    // Submission author data
    final profileIcon = logQuery(
      document,
      '.submission-id-avatar img, td.alt1 .avatar img, .classic-submission-title.avatar a img, .classic-submissiont-title.avatar a img',
    );

    var usernameAnchor =
        logQuery(document, '.submission-id-sub-container a[href^="/user/"]') ??
            logQuery(
                document,
                '.classic-submission-title.information span.c-usernameBlockSimple.username-underlined a[href^="/user/"]');

    String? extractedUsername;
    final userSpan = usernameAnchor?.querySelector('span');
    if (userSpan != null) {
      extractedUsername = userSpan.text.trim();
    } else if (usernameAnchor != null) {
      extractedUsername = usernameAnchor.text.trim();
    }

    String? linkUser;
    final href = usernameAnchor?.attributes['href'];
    if (href != null) {
      final parts = href.split('/');
      if (parts.length >= 3) {
        linkUser = parts[2];
      }
    }

    // Submission title
    final titleElem =
        logQuery(document, '.submission-title h2 p, .classic-submission-title.information h2');

    // Full image
    final imageElem =
        logQuery(document, '.submission-area img#submissionImg[src], img#submissionImg[src]');
    String? fullViewUrl = imageElem?.attributes['data-fullview-src']?.replaceFirst('//', 'https://');
    fullViewUrl ??= imageElem?.attributes['src']?.replaceFirst('//', 'https://');


    // Description
    var descElem = logQuery(document, '.submission-description.user-submitted-links') ??
        logQuery(
            document,
            '.submission-description, td.alt1[width="70%"][valign="top"][align="left"][style*="padding:8px"]');
    String fixedDescription = '';

    void _fixPrefixedLinks(dom.Element root) {
      for (final a in root.querySelectorAll('a[href]')) {
        final href = a.attributes['href']!;
        if (href.startsWith('/https://') || href.startsWith('/http://')) {
          a.attributes['href'] = href.substring(1);
        }
      }
    }

    if (descElem != null) {
      _fixPrefixedLinks(descElem);
      fixedDescription = _fixTruncatedLinks(descElem.outerHtml);
    }

    // Publication time
    var publicationTimeElem = logQuery(
      document,
      '.submission-id-sub-container .popup_date, td.alt1.stats-container .popup_date',
    );
    publicationTimeElem ??= logQuery(document, '.popup_date');
    String? rawTime = publicationTimeElem?.attributes['title']?.trim();
    rawTime ??= publicationTimeElem?.text.trim();

    // View count
    var viewCountElem = logQuery(document, '.views .font-large');
    if (viewCountElem == null) {
      final statsContainer = logQuery(document, 'td.alt1.stats-container');
      if (statsContainer != null) {
        final boldElements = statsContainer.getElementsByTagName('b');
        String? viewsText;
        for (final b in boldElements) {
          if (b.text.trim() == 'Views:') {
            final nodes = b.parent?.nodes;
            if (nodes != null) {
              final index = nodes.indexOf(b);
              if (index != -1 && index < nodes.length - 1) {
                viewsText = nodes[index + 1].text?.trim();
              }
            }
            break;
          }
        }
        if (viewsText != null && viewsText.isNotEmpty) {
          viewCountElem = dom.Element.tag('span')..text = viewsText;
        }
      }
    }
    final parsedViewCount = int.tryParse(viewCountElem?.text.trim() ?? '0') ?? 0;

    // Comments count
    var commentsCountElem = logQuery(document, '.comments .font-large');
    if (commentsCountElem == null) {
      final statsContainer = logQuery(document, 'td.alt1.stats-container');
      if (statsContainer != null) {
        final boldElements = statsContainer.getElementsByTagName('b');
        String? commentsText;
        for (final b in boldElements) {
          if (b.text.trim() == 'Comments:') {
            final nodes = b.parent?.nodes;
            if (nodes != null) {
              final index = nodes.indexOf(b);
              if (index != -1 && index < nodes.length - 1) {
                commentsText = nodes[index + 1].text?.trim();
              }
            }
            break;
          }
        }
        if (commentsText != null && commentsText.isNotEmpty) {
          commentsCountElem = dom.Element.tag('span')..text = commentsText;
        }
      }
    }
    final parsedCommentsCount = int.tryParse(commentsCountElem?.text.trim() ?? '0') ?? 0;

    // Rating (General/Mature/Adult)
    String? rating;
    dom.Element? ratingElem =
        logQuery(document, '.rating .font-large') ??
            logQuery(document, 'span[class*="c-contentRating--"]');
    if (ratingElem == null) {
      // Classic fallback: parse from stats container labels.
      final statsContainer = logQuery(document, 'td.alt1.stats-container');
      if (statsContainer != null) {
        final boldElements = statsContainer.getElementsByTagName('b');
        for (final b in boldElements) {
          if (b.text.trim() == 'Rating:') {
            final nodes = b.parent?.nodes;
            if (nodes != null) {
              final index = nodes.indexOf(b);
              if (index != -1 && index < nodes.length - 1) {
                final ratingText = nodes[index + 1].text?.trim().toLowerCase() ?? '';
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
    if (rating == null && ratingElem != null) {
      if (ratingElem.classes.contains('c-contentRating--general')) rating = 'general';
      if (ratingElem.classes.contains('c-contentRating--mature')) rating = 'mature';
      if (ratingElem.classes.contains('c-contentRating--adult')) rating = 'adult';
    }
    if (rating == null && ratingElem != null) {
      final t = ratingElem.text.trim().toLowerCase();
      if (t.contains('general')) rating = 'general';
      if (t.contains('mature')) rating = 'mature';
      if (t.contains('adult')) rating = 'adult';
    }

    // Info section
    final infoSection = logQuery(document, 'section.info.text, td.alt1.stats-container');
    String? category;
    String? type;
    String? species;
    String? gender;
    String? size;
    String? fileSize;
    final isClassic = document
            .querySelector('body')
            ?.attributes['data-static-path']
            ?.contains('themes/classic') ??
        false;

    if (infoSection != null) {
      if (!isClassic) {
        final divs = infoSection.querySelectorAll('div');
        for (final div in divs) {
          final strong = div.querySelector('strong.highlight');
          if (strong == null) continue;
          final label = strong.text.trim();
          switch (label) {
            case 'Category':
              category = div.querySelector('.category-name')?.text.trim();
              type ??= div.querySelector('.type-name')?.text.trim();
              break;
            case 'Theme':
            case 'Type':
              type = div.querySelector('.type-name')?.text.trim() ??
                  div.querySelector('.theme-name')?.text.trim() ??
                  div.querySelector('span')?.text.trim();
              break;
            case 'Species':
              species = div.querySelector('span')?.text.trim();
              break;
            case 'Gender':
              gender = div.querySelector('span')?.text.trim();
              break;
            case 'Size':
              size = div.querySelector('span')?.text.trim();
              break;
            case 'File Size':
              fileSize = div.querySelector('span')?.text.trim();
              break;
          }
        }
      } else {
        final infoHtml = infoSection.innerHtml;
        category ??= RegExp(r'<b>\s*Category:\s*</b>\s*([^<]+)<br\s*/?>', caseSensitive: false)
            .firstMatch(infoHtml)
            ?.group(1)
            ?.trim();
        type ??= RegExp(r'<b>\s*Theme:\s*</b>\s*([^<]+)<br\s*/?>', caseSensitive: false)
            .firstMatch(infoHtml)
            ?.group(1)
            ?.trim();
        species ??= RegExp(r'<b>\s*Species:\s*</b>\s*([^<]+)<br\s*/?>', caseSensitive: false)
            .firstMatch(infoHtml)
            ?.group(1)
            ?.trim();
        gender ??= RegExp(r'<b>\s*Gender:\s*</b>\s*([^<]+)<br\s*/?>', caseSensitive: false)
            .firstMatch(infoHtml)
            ?.group(1)
            ?.trim();
        final sizeMatch = RegExp(
          r'<b>\s*Resolution:\s*</b>\s*([0-9]+)\s*x\s*([0-9]+)<br\s*/?>',
          caseSensitive: false,
        ).firstMatch(infoHtml);
        if (sizeMatch != null) {
          size = '${sizeMatch.group(1)?.trim()} x ${sizeMatch.group(2)?.trim()}';
        }
        fileSize ??= RegExp(
          r'<b>\s*File Size:\s*</b>\s*([^<]+)<br\s*/?>',
          caseSensitive: false,
        ).firstMatch(infoHtml)?.group(1)?.trim();
      }
    }

    // Image dimensions
    double? imageWidth;
    double? imageHeight;
    if (infoSection != null) {
      if (!isClassic) {
        final divs = infoSection.querySelectorAll('div');
        for (final div in divs) {
          final strong = div.querySelector('strong.highlight');
          if (strong != null && strong.text.trim() == 'Size') {
            final sizeText = div.querySelector('span')?.text.trim();
            if (sizeText != null) {
              final dims = sizeText.toLowerCase().split('x');
              if (dims.length >= 2) {
                imageWidth = double.tryParse(dims[0].trim());
                imageHeight = double.tryParse(dims[1].trim());
                break;
              }
            }
          }
        }
      } else {
        final infoHtml = infoSection.innerHtml;
        final resMatch = RegExp(
          r'<b>\s*Resolution:\s*</b>\s*([0-9]+)\s*x\s*([0-9]+)<br\s*/?>',
          caseSensitive: false,
        ).firstMatch(infoHtml);
        if (resMatch != null) {
          imageWidth = double.tryParse(resMatch.group(1)!.trim());
          imageHeight = double.tryParse(resMatch.group(2)!.trim());
        }
      }
    }

    // Keywords / Meta Keywords
    final bodyElem = document.querySelector('body');
    final tagBlocklistNonce =
        bodyElem?.attributes['data-tag-blocklist-nonce']?.trim();
    final tagBlocklistRaw = bodyElem?.attributes['data-tag-blocklist'] ?? '';
    final blockedTags = tagBlocklistRaw
        .trim()
        .split(RegExp(r'\s+'))
        .where((t) => t.trim().isNotEmpty)
        .map((t) => t.trim().toLowerCase())
        .toSet();

    // Keywords should *not* fall back to a generic `section.tags-row` selector,
    // because meta-only posts still use `tags-row` with the `tags-row--meta`
    // modifier. If we accidentally select that, we end up duplicating meta tags
    // in the normal "Keywords" list.
    dom.Element? keywordSection =
        document.querySelector('section.tags-row:not(.tags-row--meta)') ??
            document.querySelector('section.tags-mobile:not(.tags-mobile--meta)') ??
            logQuery(document, 'section.tags-row:not(.tags-row--meta)') ??
            logQuery(document, 'section.tags-mobile:not(.tags-mobile--meta)') ??
            logQuery(document, '#keywords');

    dom.Element? metaKeywordSection = document.querySelector('section.tags-row.tags-row--meta') ??
        document.querySelector('section.tags-mobile.tags-mobile--meta');

    final keywordTags = _parseTagsFromSection(
      keywordSection,
      isMeta: false,
      blockedTags: blockedTags,
    );
    final metaKeywordTags = _parseTagsFromSection(
      metaKeywordSection,
      isMeta: true,
      blockedTags: blockedTags,
    );

    // Back-compat string list (used by some UI)
    final List<String> keywords = [
      for (final t in keywordTags)
        if (t.isSearchable) t.name,
    ];

    // Favorite count (unused for state but kept parity)
    var favCountElem = logQuery(document, '.favorites .font-large');
    if (favCountElem == null) {
      final statsContainer = logQuery(document, 'td.alt1.stats-container');
      if (statsContainer != null) {
        final boldElements = statsContainer.getElementsByTagName('b');
        String? favText;
        for (final b in boldElements) {
          if (b.text.trim() == 'Favorites:') {
            final parentNodes = b.parent?.nodes;
            if (parentNodes != null) {
              int idx = parentNodes.indexOf(b);
              while (idx + 1 < parentNodes.length) {
                idx++;
                final sibling = parentNodes[idx];
                if (sibling is dom.Element && sibling.localName == 'a') {
                  favText = sibling.text.trim();
                  break;
                } else if (sibling is dom.Text) {
                  final trimmed = sibling.text.trim();
                  if (trimmed.isNotEmpty) {
                    favText = trimmed;
                    break;
                  }
                }
              }
            }
            break;
          }
        }
        if (favText != null && favText.isNotEmpty) {
          favCountElem = dom.Element.tag('span')..text = favText;
        }
      }
    }
    final localFavoritesCount = int.tryParse(favCountElem?.text.trim() ?? '0') ?? 0;

    // Fav/unfav links
    var favLinkElement = logQuery(document, '.favorite-nav a[href^="/fav/"]') ??
        logQuery(document, 'a[href^="/fav/"].button');
    var unfavLinkElement = logQuery(document, '.favorite-nav a[href^="/unfav/"]') ??
        logQuery(document, 'a[href^="/unfav/"].button');
    if (favLinkElement == null) {
      final actionsContainers = logQueryAll(document, 'div.alt1.actions.aligncenter');
      for (final actionsDiv in actionsContainers) {
        final boldElements = actionsDiv.getElementsByTagName('b');
        for (final b in boldElements) {
          final a = b.querySelector('a');
          if (a != null && (a.attributes['href'] ?? '').startsWith('/fav/')) {
            favLinkElement = a;
            break;
          }
        }
        if (favLinkElement != null) break;
      }
    }
    if (unfavLinkElement == null) {
      final actionsContainers = logQueryAll(document, 'div.alt1.actions.aligncenter');
      for (final actionsDiv in actionsContainers) {
        final boldElements = actionsDiv.getElementsByTagName('b');
        for (final b in boldElements) {
          final a = b.querySelector('a');
          if (a != null && (a.attributes['href'] ?? '').startsWith('/unfav/')) {
            unfavLinkElement = a;
            break;
          }
        }
        if (unfavLinkElement != null) break;
      }
    }
    final localFavLink = favLinkElement?.attributes['href'];
    final localUnfavLink = unfavLinkElement?.attributes['href'];

    return OpenPostParseResult(
      currentUsername: currentUsername,
      username: extractedUsername,
      linkUsername: linkUser,
      profileImageUrl: profileIcon?.attributes['src']?.replaceFirst('//', 'https://'),
      submissionTitle: titleElem?.text.trim(),
      fullViewImageUrl: fullViewUrl,
      submissionDescription: fixedDescription,
      publicationTimeRaw: rawTime,
      rating: rating,
      favoritesCount: localFavoritesCount,
      viewCount: parsedViewCount,
      commentsCount: parsedCommentsCount,
      favLink: localFavLink,
      unfavLink: localUnfavLink,
      isFavorited: localUnfavLink != null,
      category: category,
      type: type,
      species: species,
      gender: gender,
      size: size,
      fileSize: fileSize,
      keywords: keywords,
      keywordTags: keywordTags,
      metaKeywordTags: metaKeywordTags,
      tagBlocklistNonce: tagBlocklistNonce,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
    );
  }

  static List<FaPostTag> _parseTagsFromSection(
    dom.Element? section, {
    required bool isMeta,
    required Set<String> blockedTags,
  }) {
    if (section == null) return const [];

    final List<FaPostTag> tags = [];

    for (final tagContainer in section.querySelectorAll('span.tags')) {
      final tagBlock = tagContainer.querySelector('a.tag-block');
      final dataTagName = tagBlock?.attributes['data-tag-name']?.trim();
      final isBlockedFromClass =
          tagBlock?.classes.contains('remove-tag') ?? false;

      final searchAnchor =
          tagContainer.querySelector('a[href^="/search/@keywords"]');
      final String? label = searchAnchor?.text.trim();
      final isSearchable = searchAnchor != null;

      String? fallbackLabel;
      if (!isSearchable) {
        fallbackLabel = tagContainer
                .querySelector('span.tag-invalid')
                ?.text
                .trim() ??
            tagContainer.querySelector('a')?.text.trim();
      }

      final name = (dataTagName ?? label ?? fallbackLabel ?? '').trim();
      if (name.isEmpty) continue;
      if (tags.any((t) => t.name == name)) continue;

      final normalizedName = name.toLowerCase();
      final isBlocked = isBlockedFromClass || blockedTags.contains(normalizedName);

      tags.add(
        FaPostTag(
          name: name,
          isBlocked: isBlocked,
          isMeta: isMeta,
          isSearchable: isSearchable,
        ),
      );
    }

    return tags;
  }

  /// Parses comment containers from the provided FA post document.
  /// Returns a list of maps compatible with the existing CommentWidget.
  static List<Map<String, dynamic>> parseComments(dom.Document document) {
    final commentContainers =
        document.querySelectorAll('.comment_container, table.container-comment');

    final List<Map<String, dynamic>> loadedComments = [];

    for (final commentContainer in commentContainers) {
      final bool isClassic = (commentContainer.localName == 'table');

      final innerContainer = commentContainer.querySelector('comment-container');
      bool isDeleted =
          innerContainer?.classes.contains('deleted-comment-container') ?? false;

      bool isClassicDeleted = false;
      dom.Element? classicDeletedCell;
      if (isClassic) {
        classicDeletedCell = commentContainer.querySelector('td.comment-deleted');
        if (classicDeletedCell != null) {
          isClassicDeleted = true;
          isDeleted = true;
        }
      }

      double widthPercent = 100.0;
      if (!isClassic) {
        final style = commentContainer.attributes['style'];
        if (style != null) {
          final widthRegex = RegExp(r'width\s*:\s*(\d+(?:\.\d+)?)%');
          final match = widthRegex.firstMatch(style);
          if (match != null) {
            widthPercent = double.tryParse(match.group(1) ?? '') ?? 100.0;
          }
        }
      } else {
        final tableWidth = commentContainer.attributes['width'];
        if (tableWidth != null) {
          final numericPart = tableWidth.replaceAll('%', '').trim();
          widthPercent = double.tryParse(numericPart) ?? 100.0;
        }
      }

      String? profileImage = commentContainer
          .querySelector('img.avatar, .avatar img')
          ?.attributes['src']
          ?.replaceFirst('//', 'https://');

      final displayNameAnchor =
          commentContainer.querySelector('a.c-usernameBlock__displayName span.js-displayName');
      final String? displayName = displayNameAnchor?.text.trim();

      String parsedSymbol = '';
      String parsedUserName = '';
      final userNameAnchor = commentContainer.querySelector('a.c-usernameBlock__userName');
      if (userNameAnchor != null) {
        final symbolElement = userNameAnchor.querySelector('span.c-usernameBlock__symbol');
        if (symbolElement != null) {
          parsedSymbol = symbolElement.text.trim();
        }
        final fullText = userNameAnchor.text.trim();
        parsedUserName = fullText.replaceFirst(parsedSymbol, '').trim();
      }
      final effectiveUserName = parsedUserName.isNotEmpty ? parsedUserName : displayName;
      final usernameForUI = effectiveUserName ?? 'Anonymous';

      final userTitleElement = commentContainer.querySelector(
          'comment-title.custom-title, span.custom-title');
      final String? userTitle = userTitleElement?.text.trim();

      final iconBeforeElements =
          commentContainer.querySelectorAll('usericon-block-before img');
      final List<String> iconBeforeUrls = iconBeforeElements.map((elem) {
        final src = elem.attributes['src'];
        if (src != null) {
          if (src.startsWith('//')) return 'https:$src';
          if (src.startsWith('/')) return 'https://www.furaffinity.net$src';
          return src;
        }
        return '';
      }).where((url) => url.isNotEmpty).toList();

      final iconAfterElements =
          commentContainer.querySelectorAll('usericon-block-after img');
      final List<String> iconAfterUrls = iconAfterElements.map((elem) {
        final src = elem.attributes['src'];
        if (src != null) {
          if (src.startsWith('//')) return 'https:$src';
          if (src.startsWith('/')) return 'https://www.furaffinity.net$src';
          return src;
        }
        return '';
      }).where((url) => url.isNotEmpty).toList();

      String? commentText;
      String? commentHtml;
      final commentTextElement = commentContainer.querySelector(
          '.comment_text, .message-text, .replyto-message');

      if (isClassicDeleted && classicDeletedCell != null) {
        commentText = classicDeletedCell.text.trim();
        commentHtml = classicDeletedCell.innerHtml;
      }

      if (commentTextElement != null) {
        String rawHtml = commentTextElement.innerHtml;
        rawHtml = rawHtml.replaceAllMapped(
          RegExp(
              r'<i\s+class="(smilie\s+[^"]+)"[^>]*>(?:\s*</i>)?|<i\s+class="(smilie\s+[^"]+)"[^>]*/?>',
              caseSensitive: false),
          (m) {
            final cls = (m.group(1) ?? m.group(2))!;
            return '[${cls.replaceAll(' ', '-')}]';
          },
        );
        rawHtml = rawHtml
            .replaceAll(RegExp(r'<i\s+class="bbcode\s+bbcode_i"[^>]*>', caseSensitive: false), '[[i]]')
            .replaceAll(RegExp(r'</i>', caseSensitive: false), '[[/i]]')
            .replaceAll(RegExp(r'<strong\s+class="bbcode\s+bbcode_b"[^>]*>', caseSensitive: false), '[[b]]')
            .replaceAll(RegExp(r'</strong>', caseSensitive: false), '[[/b]]')
            .replaceAll(RegExp(r'<b\s+class="bbcode\s+bbcode_b"[^>]*>', caseSensitive: false), '[[b]]')
            .replaceAll(RegExp(r'</b>', caseSensitive: false), '[[/b]]')
            .replaceAll(RegExp(r'<u\s+class="bbcode\s+bbcode_u"[^>]*>', caseSensitive: false), '[[u]]')
            .replaceAll(RegExp(r'</u>', caseSensitive: false), '[[/u]]');

        rawHtml = _fixTruncatedLinks(rawHtml);
        final commentDoc = html_parser.parse(rawHtml);
        commentDoc.querySelectorAll('a.auto_link_shortened').forEach((element) {
          final fullLink = element.attributes['title'] ?? element.attributes['href'];
          if (fullLink != null) {
            element.innerHtml = fullLink;
          }
        });

        commentText = commentDoc.body?.text.trim();
        commentHtml = commentDoc.body?.innerHtml ?? rawHtml;
      }

      final dateElem = commentContainer.querySelector('.popup_date');
      final popupDateFull = dateElem?.attributes['title']?.trim();
      final popupDateRelative = dateElem?.text.trim();

      String? hideLink;
      final unhideLink = commentContainer.querySelector('a[href*="action=unhide_comment"]');
      if (unhideLink != null) {
        hideLink = unhideLink.attributes['href'];
      } else {
        final hideLinkCandidate =
            commentContainer.querySelector('a[href*="action=hide_comment"]');
        if (hideLinkCandidate != null) {
          hideLink = hideLinkCandidate.attributes['href'];
        }
      }
      if (hideLink != null && hideLink.startsWith('/')) {
        hideLink = 'https://www.furaffinity.net$hideLink';
      }

      String? commentId;
      final replyLinkHref =
          commentContainer.querySelector('.replyto_link')?.attributes['href'];
      if (replyLinkHref != null) {
        final match = RegExp(r'/replyto/[\w]+/(\d+)/').firstMatch(replyLinkHref);
        if (match != null) {
          commentId = match.group(1);
        }
      }
      if (commentId == null) {
        final tableId = commentContainer.id; // e.g. "cid:167658070"
        if (tableId != null && tableId.startsWith('cid:')) {
          commentId = tableId.replaceFirst('cid:', '').trim();
        }
      }

      final editLinkModern = commentContainer.querySelector('comment-edit a');
      String? editLink;
      if (editLinkModern != null) {
        editLink = editLinkModern.attributes['href'];
      } else {
        final editLinkClassic =
            commentContainer.querySelector('a.edit-link[href*="/edit/"]');
        if (editLinkClassic != null) {
          editLink = editLinkClassic.attributes['href'];
        }
      }
      if (editLink != null && editLink.startsWith('/')) {
        editLink = 'https://www.furaffinity.net$editLink';
      }

      final replyLinkElement = commentContainer.querySelector('td.reply-link a');
      final String? replyLink = replyLinkElement?.attributes['href'];

      final commentMap = <String, dynamic>{
        'profileImage': profileImage,
        'displayName': displayName,
        'userName': effectiveUserName,
        'username': usernameForUI,
        'symbol': parsedSymbol.isNotEmpty ? parsedSymbol : '@',
        'userTitle': userTitle,
        'replyLink': replyLink,
        'text': commentText,
        'commentHtml': commentHtml,
        'width': widthPercent,
        'isOP': commentContainer.querySelector('.comment_op_marker') != null,
        'popupDateFull': popupDateFull,
        'popupDateRelative': popupDateRelative,
        'showFullDate': false,
        'commentId': commentId,
        'iconBeforeUrls': iconBeforeUrls,
        'iconAfterUrls': iconAfterUrls,
        'deleted': isDeleted,
        'hideLink': hideLink,
        'editLink': editLink,
      };

      if (isDeleted) {
        String hiddenText = commentText ?? '';
        hiddenText = hiddenText
            .replaceAll(
                RegExp(r'Unhide\s+Comment(\s*<span.*?<\/span>)?', caseSensitive: false),
                '')
            .trim();
        commentMap['text'] = hiddenText;
        commentMap['profileImage'] = null;
        commentMap['displayName'] = null;
        commentMap['userName'] = null;
      } else {
        if (profileImage == null || effectiveUserName == null || commentText == null) {
          continue;
        }
      }

      loadedComments.add(commentMap);
    }

    return loadedComments;
  }

  static String _fixTruncatedLinks(String htmlContent) {
    final document = html_parser.parse(htmlContent);
    for (final anchor in document.querySelectorAll('a.auto_link_shortened')) {
      if (anchor.text.contains('.....')) {
        final fullLink = anchor.attributes['title'];
        if (fullLink != null && fullLink.isNotEmpty) {
          anchor.text = fullLink;
        }
      }
    }
    return document.outerHtml;
  }
}

