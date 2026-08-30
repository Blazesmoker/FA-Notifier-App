import 'package:html/dom.dart' as dom;
import 'package:fanotifier/core/utils/html_tags_debug.dart';
import 'package:fanotifier/features/submissions/data/openpost_comments_parser.dart';
import 'package:fanotifier/features/submissions/data/openpost_folder_parser.dart';
import 'package:fanotifier/features/submissions/data/openpost_html_link_normalizer.dart';
import 'package:fanotifier/features/submissions/data/openpost_submission_metadata_parser.dart';
import 'package:fanotifier/features/submissions/data/openpost_submission_stats_parser.dart';
import 'package:fanotifier/features/submissions/data/openpost_submission_attachment_parser.dart';
import 'package:fanotifier/features/submissions/domain/openpost_models.dart';
import 'package:fanotifier/shared/fa/parsing_utils.dart';

class OpenPostApiService {
  /// Parses the main post document and returns structured data.
  static OpenPostParseResult parsePostDocument(dom.Document document) {
    final titleText = document.querySelector('title')?.text.toLowerCase() ?? '';
    final h2Text = document.querySelector('h2')?.text.toLowerCase() ?? '';
    final bodyText = document.body?.text.toLowerCase() ?? '';

    final isSystemError = titleText.contains('system error') ||
        h2Text.contains('system error') ||
        bodyText.contains('not in our database');

    if (isSystemError) {
      throw FaSystemErrorException(
        'This submission does not exist or has been deleted',
      );
    }

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
      '.submission-description-artist img.submission-user-icon.avatar, .submission-description-header img.submission-user-icon.avatar, .submission-id-avatar img, td.alt1 .avatar img, .classic-submission-title.avatar a img, .classic-submissiont-title.avatar a img',
    );

    var usernameAnchor = logQuery(
            document,
            '.submission-description-artist span.c-usernameBlockSimple.username-underlined a[href^="/user/"], .submission-description-header span.c-usernameBlockSimple.username-underlined a[href^="/user/"]') ??
        logQuery(document, '.submission-id-sub-container a[href^="/user/"]') ??
        logQuery(document,
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
    final titleElem = logQuery(document,
        '.submission-title h2 p, .submission-title h2, .classic-submission-title.information h2');

    // Full image
    final imageElem = logQuery(document,
        '.submission-area img#submissionImg[src], img#submissionImg[src]');
    String? fullViewUrl =
        normalizeFaUrl(imageElem?.attributes['data-fullview-src']);
    fullViewUrl ??= normalizeFaUrl(imageElem?.attributes['src']);

    // Description
    var descElem = logQuery(
            document, '.submission-description-text.user-submitted-links') ??
        logQuery(document, '.submission-description.user-submitted-links') ??
        logQuery(document,
            '.submission-description, td.alt1[width="70%"][valign="top"][align="left"][style*="padding:8px"]');
    String fixedDescription = '';

    void fixPrefixedLinks(dom.Element root) {
      for (final a in root.querySelectorAll('a[href]')) {
        final href = a.attributes['href']!;
        if (href.startsWith('/https://') || href.startsWith('/http://')) {
          a.attributes['href'] = href.substring(1);
        }
      }
    }

    if (descElem != null) {
      fixPrefixedLinks(descElem);
      fixedDescription = normalizeOpenPostTruncatedLinks(descElem.outerHtml);
    }

    // Publication time
    var publicationTimeElem = logQuery(
      document,
      '.submission-id-sub-container .popup_date, td.alt1.stats-container .popup_date',
    );
    publicationTimeElem ??= logQuery(document, '.popup_date');
    String? rawTime = publicationTimeElem?.attributes['title']?.trim();
    rawTime ??= publicationTimeElem?.text.trim();

    final stats = parseOpenPostSubmissionStats(document);
    final metadata = parseOpenPostSubmissionMetadata(document);

    return OpenPostParseResult(
      currentUsername: currentUsername,
      username: extractedUsername,
      linkUsername: linkUser,
      profileImageUrl: normalizeFaUrl(profileIcon?.attributes['src']),
      submissionTitle: titleElem?.text.trim(),
      fullViewImageUrl: fullViewUrl,
      submissionDescription: fixedDescription,
      publicationTimeRaw: rawTime,
      rating: stats.rating,
      favoritesCount: stats.favoritesCount,
      viewCount: stats.viewCount,
      commentsCount: stats.commentsCount,
      favLink: stats.favLink,
      unfavLink: stats.unfavLink,
      isFavorited: stats.unfavLink != null,
      category: metadata.category,
      type: metadata.type,
      species: metadata.species,
      gender: metadata.gender,
      size: metadata.size,
      fileSize: metadata.fileSize,
      folders: parseOpenPostFolderLinks(document),
      keywords: metadata.keywords,
      keywordTags: metadata.keywordTags,
      metaKeywordTags: metadata.metaKeywordTags,
      tagBlocklistNonce: metadata.tagBlocklistNonce,
      imageWidth: metadata.imageWidth,
      imageHeight: metadata.imageHeight,
      submissionAttachment: parseOpenPostSubmissionAttachment(document),
    );
  }

  static List<Map<String, dynamic>> parseComments(dom.Document document) {
    return parseOpenPostComments(document);
  }
}

class FaSystemErrorException implements Exception {
  final String message;
  FaSystemErrorException(this.message);
  @override
  String toString() => message;
}
