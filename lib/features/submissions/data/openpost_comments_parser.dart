import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'package:FANotifier/features/submissions/data/openpost_html_link_normalizer.dart';
import 'package:FANotifier/shared/fa/parsing_utils.dart';

List<Map<String, dynamic>> parseOpenPostComments(dom.Document document) {
  final commentContainers =
      document.querySelectorAll('.comment_container, table.container-comment');
  final loadedComments = <Map<String, dynamic>>[];

  for (final commentContainer in commentContainers) {
    final isClassic = commentContainer.localName == 'table';
    final innerContainer = commentContainer.querySelector('comment-container');
    var isDeleted =
        innerContainer?.classes.contains('deleted-comment-container') ?? false;

    var isClassicDeleted = false;
    dom.Element? classicDeletedCell;
    if (isClassic) {
      classicDeletedCell = commentContainer.querySelector('td.comment-deleted');
      if (classicDeletedCell != null) {
        isClassicDeleted = true;
        isDeleted = true;
      }
    }

    var widthPercent = 100.0;
    if (!isClassic) {
      final style = commentContainer.attributes['style'];
      if (style != null) {
        final match =
            RegExp(r'width\s*:\s*(\d+(?:\.\d+)?)%').firstMatch(style);
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

    var profileImage = normalizeFaUrl(
      commentContainer
          .querySelector('img.avatar, .avatar img')
          ?.attributes['src'],
    );
    final displayNameAnchor = commentContainer
        .querySelector('a.c-usernameBlock__displayName span.js-displayName');
    final displayName = displayNameAnchor?.text.trim();

    var parsedSymbol = '';
    var parsedUserName = '';
    final userNameAnchor =
        commentContainer.querySelector('a.c-usernameBlock__userName');
    if (userNameAnchor != null) {
      final symbolElement =
          userNameAnchor.querySelector('span.c-usernameBlock__symbol');
      if (symbolElement != null) {
        parsedSymbol = symbolElement.text.trim();
      }
      final fullText = userNameAnchor.text.trim();
      parsedUserName = fullText.replaceFirst(parsedSymbol, '').trim();
    }
    final effectiveUserName =
        parsedUserName.isNotEmpty ? parsedUserName : displayName;
    final usernameForUI = effectiveUserName ?? 'Anonymous';

    final userTitleElement = commentContainer
        .querySelector('comment-title.custom-title, span.custom-title');
    final userTitle = userTitleElement?.text.trim();

    final iconBeforeUrls = commentContainer
        .querySelectorAll('usericon-block-before img')
        .map((element) {
          final src = element.attributes['src'];
          if (src != null) {
            if (src.startsWith('//')) return 'https:$src';
            if (src.startsWith('/')) {
              return 'https://www.furaffinity.net$src';
            }
            return src;
          }
          return '';
        })
        .where((url) => url.isNotEmpty)
        .toList();

    final iconAfterUrls = commentContainer
        .querySelectorAll('usericon-block-after img')
        .map((element) {
          final src = element.attributes['src'];
          if (src != null) {
            if (src.startsWith('//')) return 'https:$src';
            if (src.startsWith('/')) {
              return 'https://www.furaffinity.net$src';
            }
            return src;
          }
          return '';
        })
        .where((url) => url.isNotEmpty)
        .toList();

    String? commentText;
    String? commentHtml;
    final commentTextElement = commentContainer
        .querySelector('.comment_text, .message-text, .replyto-message');

    if (isClassicDeleted && classicDeletedCell != null) {
      commentText = classicDeletedCell.text.trim();
      commentHtml = classicDeletedCell.innerHtml;
    }

    if (commentTextElement != null) {
      var rawHtml = commentTextElement.innerHtml;
      rawHtml = rawHtml.replaceAllMapped(
        RegExp(
          r'<i\s+class="(smilie\s+[^"]+)"[^>]*>(?:\s*</i>)?|<i\s+class="(smilie\s+[^"]+)"[^>]*/?>',
          caseSensitive: false,
        ),
        (match) {
          final className = (match.group(1) ?? match.group(2))!;
          return '[${className.replaceAll(' ', '-')}]';
        },
      );

      rawHtml = normalizeOpenPostTruncatedLinks(rawHtml);
      final commentDocument = html_parser.parse(rawHtml);
      for (final element
          in commentDocument.querySelectorAll('a.auto_link_shortened')) {
        final fullLink =
            element.attributes['title'] ?? element.attributes['href'];
        if (fullLink != null) {
          element.innerHtml = fullLink;
        }
      }

      commentText = commentDocument.body?.text.trim();
      commentHtml = commentDocument.body?.innerHtml ?? rawHtml;
    }

    final dateElement = commentContainer.querySelector('.popup_date');
    final popupDateFull = dateElement?.attributes['title']?.trim();
    final popupDateRelative = dateElement?.text.trim();

    String? hideLink;
    final unhideLink =
        commentContainer.querySelector('a[href*="action=unhide_comment"]');
    final hasUnhideAction = unhideLink != null;
    if (unhideLink != null) {
      hideLink = unhideLink.attributes['href'];
    } else {
      hideLink = commentContainer
          .querySelector('a[href*="action=hide_comment"]')
          ?.attributes['href'];
    }
    if (hideLink != null && hideLink.startsWith('/')) {
      hideLink = 'https://www.furaffinity.net$hideLink';
    }

    final combinedHiddenSource = '${commentText ?? ''} ${commentHtml ?? ''}';
    final hiddenByOwner = RegExp(
      r'comment\s+hidden\s+by\s+its\s+owner',
      caseSensitive: false,
    ).hasMatch(combinedHiddenSource);
    final hiddenCommentDetected = RegExp(
      r'comment\s+hidden',
      caseSensitive: false,
    ).hasMatch(combinedHiddenSource);
    isDeleted = isDeleted ||
        hasUnhideAction ||
        hiddenByOwner ||
        hiddenCommentDetected;

    String? commentId;
    final replyLinkHref =
        commentContainer.querySelector('.replyto_link')?.attributes['href'];
    if (replyLinkHref != null) {
      commentId =
          RegExp(r'/replyto/[\w]+/(\d+)/').firstMatch(replyLinkHref)?.group(1);
    }
    if (commentId == null) {
      final tableId = commentContainer.id;
      if (tableId.startsWith('cid:')) {
        commentId = tableId.replaceFirst('cid:', '').trim();
      }
    }

    final editLinkModern = commentContainer.querySelector('comment-edit a');
    String? editLink;
    if (editLinkModern != null) {
      editLink = editLinkModern.attributes['href'];
    } else {
      editLink = commentContainer
          .querySelector('a.edit-link[href*="/edit/"]')
          ?.attributes['href'];
    }
    if (editLink != null && editLink.startsWith('/')) {
      editLink = 'https://www.furaffinity.net$editLink';
    }

    final replyLink =
        commentContainer.querySelector('td.reply-link a')?.attributes['href'];
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
      var hiddenText = commentText ?? '';
      hiddenText = hiddenText
          .replaceAll(
            RegExp(
              r'Unhide\s+Comment(\s*<span.*?</span>)?',
              caseSensitive: false,
            ),
            '',
          )
          .trim();
      commentMap['text'] =
          hiddenText.isNotEmpty ? hiddenText : 'Comment hidden by its owner';
      commentMap['commentHtml'] = null;
      commentMap['profileImage'] = null;
      commentMap['displayName'] = null;
      commentMap['userName'] = null;
      commentMap['username'] = null;
      commentMap['symbol'] = '';
      commentMap['userTitle'] = null;
    } else if (profileImage == null ||
        effectiveUserName == null ||
        commentText == null) {
      continue;
    }

    loadedComments.add(commentMap);
  }

  return loadedComments;
}
