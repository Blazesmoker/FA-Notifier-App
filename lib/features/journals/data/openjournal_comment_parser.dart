import 'package:html/dom.dart' as dom;

import 'package:FANotifier/features/journals/data/journal_url_builder.dart';

List<Map<String, dynamic>> parseOpenJournalComments(dom.Document document) {
  final commentBodies = <Map<String, dynamic>>[];
  final commentBlocks = document.querySelectorAll(
    '#comments-journal .comment_container, .comments-list .comment_container, div.comment_container',
  );

  for (final commentBlock in commentBlocks) {
    final comment = <String, dynamic>{};
    String? commentId;
    final anchorId =
        commentBlock.querySelector('a.comment_anchor')?.attributes['id'];
    commentId = _normalizeCommentId(anchorId);
    commentId ??= _normalizeCommentId(commentBlock.attributes['data-id']);
    commentId ??= _normalizeCommentId(commentBlock.attributes['id']);

    final avatarImage = commentBlock.querySelector('img.comment_useravatar') ??
        commentBlock.querySelector('img.avatar');
    comment['profileImage'] =
        buildAbsoluteFaUrl(avatarImage?.attributes['src']);

    final usernameBlock = commentBlock.querySelector('.c-usernameBlock');
    final displayNameSpan = usernameBlock?.querySelector('.js-displayName');
    final userNameAnchor =
        usernameBlock?.querySelector('.c-usernameBlock__userName');

    String? username;
    if (userNameAnchor != null) {
      var text = userNameAnchor.text.trim();
      text = text.replaceAll('\u00A0', ' ');
      text = text.replaceFirst(RegExp(r'^[^A-Za-z0-9_-]+'), '');
      if (text.isNotEmpty) username = text.trim();
    }

    comment['username'] = (username ?? '').isNotEmpty
        ? username
        : (displayNameSpan?.text.trim() ?? '');
    comment['displayName'] = displayNameSpan?.text.trim() ??
        (comment['username'] as String? ?? '');
    comment['symbol'] = usernameBlock
            ?.querySelector('.c-usernameBlock__symbol')
            ?.text
            .trim() ??
        '';
    comment['userTitle'] =
        commentBlock.querySelector('comment-title')?.text.trim() ?? '';
    comment['isOP'] =
        commentBlock.querySelector('.comment_op_marker') != null;

    comment['iconBeforeUrls'] = commentBlock
        .querySelectorAll('usericon-block-before img')
        .map((element) {
          final src = element.attributes['src'];
          if (src != null) return buildAbsoluteFaUrl(src) ?? '';
          return '';
        })
        .where((url) => url.isNotEmpty)
        .toList();
    comment['iconAfterUrls'] = commentBlock
        .querySelectorAll('usericon-block-after img')
        .map((element) {
          final src = element.attributes['src'];
          if (src != null) return buildAbsoluteFaUrl(src) ?? '';
          return '';
        })
        .where((url) => url.isNotEmpty)
        .toList();

    final popup = commentBlock.querySelector('.popup_date');
    comment['popupDateRelative'] = popup?.text.trim() ?? '';
    comment['popupDateFull'] = popup?.attributes['title'] ?? '';

    final hideAnchor = commentBlock
        .querySelector('a[href*="action=hide_comment"][href*="comment_id="]');
    final unhideAnchor = commentBlock.querySelector(
      'a[href*="action=unhide_comment"][href*="comment_id="]',
    );
    final hasAnyUnhideAction = commentBlock
            .querySelector('a[href*="action=unhide_comment"]') !=
        null;
    final editAnchor = commentBlock.querySelector('a.edit_link') ??
        commentBlock.querySelector('a[title*="Edit this Comment"]') ??
        commentBlock.querySelector('a[href*="/edit/"]');
    final deleteAnchor =
        commentBlock.querySelector('a[href*="action=delete_comment"]') ??
            commentBlock.querySelector('a[title*="Delete"]');

    final hideLink = buildAbsoluteFaUrl(hideAnchor?.attributes['href']);
    final unhideLink = buildAbsoluteFaUrl(unhideAnchor?.attributes['href']);
    final editLink = buildAbsoluteFaUrl(editAnchor?.attributes['href']);
    final deleteLink = buildAbsoluteFaUrl(deleteAnchor?.attributes['href']);
    comment['hideLink'] = hideLink;
    comment['unhideLink'] = unhideLink;
    comment['editLink'] = editLink;
    comment['deleteLink'] = deleteLink;

    if ((commentId == null || commentId.isEmpty) && unhideLink != null) {
      commentId = _extractCommentIdFromUrl(unhideLink);
    }
    if ((commentId == null || commentId.isEmpty) && hideLink != null) {
      commentId = _extractCommentIdFromUrl(hideLink);
    }
    comment['commentId'] = commentId ?? '';

    final hasDeletedInner = commentBlock
            .querySelector('comment-container.deleted-comment-container') !=
        null;
    final lowerAll = commentBlock.text.toLowerCase();
    comment['deleted'] = hasDeletedInner ||
        hasAnyUnhideAction ||
        lowerAll.contains('comment hidden') ||
        lowerAll.contains('hidden by its owner');

    var width = 100.0;
    final widthMatch = RegExp(r'width\s*:\s*([0-9.]+)%')
        .firstMatch(commentBlock.attributes['style'] ?? '');
    final commentTextElement =
        commentBlock.querySelector('.comment_text .user-submitted-links') ??
            commentBlock.querySelector('.comment_text') ??
            commentBlock
                .querySelector('comment-user-text .user-submitted-links') ??
            commentBlock.querySelector('comment-user-text');

    String? commentHtml;
    String? commentText;
    if (commentTextElement != null) {
      final cloned = commentTextElement.clone(true);
      cloned
          .querySelectorAll('.floatright, div.floatright')
          .forEach((element) => element.remove());
      commentHtml = _normalizeFaHtml(commentTextElement);
      commentText = commentTextElement.text.trim();
    }
    comment['commentHtml'] = commentHtml;
    comment['text'] = commentText;

    final combinedHiddenSource = '${commentText ?? ''} ${commentHtml ?? ''}';
    final hiddenByOwner = RegExp(
      r'comment\s+hidden\s+by\s+its\s+owner',
      caseSensitive: false,
    ).hasMatch(combinedHiddenSource);
    final hiddenCommentDetected = RegExp(
      r'comment\s+hidden',
      caseSensitive: false,
    ).hasMatch(combinedHiddenSource);
    comment['deleted'] = (comment['deleted'] == true) ||
        hiddenByOwner ||
        hiddenCommentDetected;

    if (comment['deleted'] == true) {
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
      comment['text'] =
          hiddenText.isNotEmpty ? hiddenText : 'Comment hidden by its owner';
      comment['commentHtml'] = null;
      comment['profileImage'] = null;
      comment['displayName'] = null;
      comment['username'] = null;
      comment['symbol'] = '';
      comment['userTitle'] = null;
    }

    if (widthMatch != null) {
      width = double.tryParse(widthMatch.group(1)!) ?? 100.0;
    }
    comment['width'] = width;
    commentBodies.add(comment);
  }

  return commentBodies;
}

String? _extractCommentIdFromUrl(String? url) {
  if (url == null) return null;
  return RegExp(r'(?:\?|&)comment_id=(\d+)').firstMatch(url)?.group(1);
}

String? _normalizeCommentId(String? raw) {
  if (raw == null) return null;
  final normalized = raw.trim();
  if (normalized.isEmpty) return null;
  if (normalized.startsWith('cid:')) {
    final suffix = normalized.substring(4);
    return RegExp(r'^\d+$').hasMatch(suffix) ? suffix : null;
  }
  final prefixedMatch = RegExp(r'cid:(\d+)').firstMatch(normalized);
  if (prefixedMatch != null) return prefixedMatch.group(1);
  return RegExp(r'(\d+)').firstMatch(normalized)?.group(1);
}

String _normalizeFaHtml(dom.Element root) {
  final cloned = root.clone(true);
  cloned.querySelectorAll('span.bbcode_i').forEach((element) {
    element.replaceWith(dom.Element.tag('i')..innerHtml = element.innerHtml);
  });
  cloned.querySelectorAll('span.bbcode_b').forEach((element) {
    element.replaceWith(dom.Element.tag('b')..innerHtml = element.innerHtml);
  });
  cloned.querySelectorAll('span.bbcode_u').forEach((element) {
    element.replaceWith(dom.Element.tag('u')..innerHtml = element.innerHtml);
  });
  cloned.querySelectorAll('span.bbcode_center').forEach((element) {
    element.replaceWith(dom.Element.tag('div')
      ..attributes['style'] = 'text-align:center'
      ..innerHtml = element.innerHtml);
  });
  return cloned.innerHtml;
}
