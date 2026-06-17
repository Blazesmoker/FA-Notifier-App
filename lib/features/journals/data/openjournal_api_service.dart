import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'package:FANotifier/shared/fa/fa_cookie_helper.dart';
import 'package:FANotifier/shared/fa/fa_http.dart';

class OpenJournalFetchResult {
  OpenJournalFetchResult({
    required this.profileImageUrl,
    required this.displayName,
    required this.authorSlug,
    required this.symbol,
    required this.userTitle,
    required this.isJournalClassic,
    required this.ownerEditLink,
    required this.favoriteLink,
    required this.unfavoriteLink,
    required this.isFavorited,
    required this.watchLink,
    required this.unwatchLink,
    required this.isWatching,
    required this.blockLink,
    required this.unblockLink,
    required this.isBlocked,
    required this.title,
    required this.dateTime,
    required this.dateTimeRaw,
    required this.submissionDescription,
    required this.commentsCount,
    required this.fullViewImageUrl,
    required this.fileLink,
    required this.category,
    required this.type,
    required this.species,
    required this.gender,
    required this.keywords,
    required this.deleteLink,
    required this.commentBodies,
  });

  final String? profileImageUrl;
  final String? displayName;
  final String? authorSlug;
  final String? symbol;
  final String? userTitle;
  final bool isJournalClassic;

  final String? ownerEditLink;
  final String? favoriteLink;
  final String? unfavoriteLink;
  final bool isFavorited;
  final String? watchLink;
  final String? unwatchLink;
  final bool isWatching;
  final String? blockLink;
  final String? unblockLink;
  final bool isBlocked;

  final String? title;
  final DateTime? dateTime;
  final String? dateTimeRaw;
  final String? submissionDescription;
  final int commentsCount;
  final String? fullViewImageUrl;
  final String? fileLink;
  final String? category;
  final String? type;
  final String? species;
  final String? gender;
  final List<String> keywords;

  final String? deleteLink;
  final List<Map<String, dynamic>> commentBodies;
}

class OpenJournalApiService {
  OpenJournalApiService({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                accountName: 'flutter_secure_storage_service',
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _secureStorage;

  Future<_Cookies> _getCookies() async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    if (cookieA == null || cookieB == null) {
      throw Exception('Not logged in: missing cookies');
    }
    return _Cookies(cookieA: cookieA, cookieB: cookieB);
  }

  String? _absFaUrl(String? href) {
    if (href == null) return null;
    final h = href.trim();
    if (h.isEmpty) return null;
    if (h.startsWith('http://') || h.startsWith('https://')) return h;
    if (h.startsWith('//')) return 'https:$h';
    if (h.startsWith('/')) return 'https://www.furaffinity.net$h';
    return 'https://www.furaffinity.net/$h';
  }

  String? _extractCommentIdFromUrl(String? url) {
    if (url == null) return null;
    final m = RegExp(r'(?:\?|&)comment_id=(\d+)').firstMatch(url);
    return m?.group(1);
  }

  String? _normalizeCommentId(String? raw) {
    if (raw == null) return null;
    final t = raw.trim();
    if (t.isEmpty) return null;
    if (t.startsWith('cid:')) {
      final s = t.substring(4);
      return RegExp(r'^\d+$').hasMatch(s) ? s : null;
    }
    final m = RegExp(r'cid:(\d+)').firstMatch(t);
    if (m != null) return m.group(1);
    final m2 = RegExp(r'(\d+)').firstMatch(t);
    return m2?.group(1);
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
    return _absFaUrl(match?.group(1));
  }

  String? _extractDeleteLinkFromDocument(
    dom.Document document,
    String uniqueNumber,
  ) {
    final directDeleteHref = document
        .querySelector('a[href*="/controls/deletejournal/$uniqueNumber/"]')
        ?.attributes['href'];
    final normalizedDirectHref = _absFaUrl(directDeleteHref);
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
      final href = _absFaUrl(anchor.attributes['href']);
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

  bool _looksLikeMissingJournalDocument(dom.Document document) {
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

  List<Map<String, dynamic>> _parseCommentsFromDocument(dom.Document document) {
    final commentBodies = <Map<String, dynamic>>[];

    final commentBlocks = document.querySelectorAll(
      '#comments-journal .comment_container, .comments-list .comment_container, div.comment_container',
    );

    for (final c in commentBlocks) {
      final comment = <String, dynamic>{};

      String? commentId;

      final anchorId = c.querySelector('a.comment_anchor')?.attributes['id'];
      commentId = _normalizeCommentId(anchorId);
      commentId ??= _normalizeCommentId(c.attributes['data-id']);
      commentId ??= _normalizeCommentId(c.attributes['id']);

      final avatarImg = c.querySelector('img.comment_useravatar') ??
          c.querySelector('img.avatar');
      comment['profileImage'] = _absFaUrl(avatarImg?.attributes['src']);

      final usernameBlock = c.querySelector('.c-usernameBlock');
      final displayNameSpan = usernameBlock?.querySelector('.js-displayName');
      final userNameA =
          usernameBlock?.querySelector('.c-usernameBlock__userName');

      String? username;
      if (userNameA != null) {
        var t = userNameA.text.trim();
        t = t.replaceAll('\u00A0', ' ');
        t = t.replaceFirst(RegExp(r'^[^A-Za-z0-9_-]+'), '');
        if (t.isNotEmpty) username = t.trim();
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
          c.querySelector('comment-title')?.text.trim() ?? '';
      comment['isOP'] = c.querySelector('.comment_op_marker') != null;

      final iconBeforeElems =
          c.querySelectorAll('usericon-block-before img');
      final iconBeforeUrls = iconBeforeElems
          .map((elem) {
            final src = elem.attributes['src'];
            if (src != null) return _absFaUrl(src) ?? '';
            return '';
          })
          .where((url) => url.isNotEmpty)
          .toList();
      final iconAfterElems =
          c.querySelectorAll('usericon-block-after img');
      final iconAfterUrls = iconAfterElems
          .map((elem) {
            final src = elem.attributes['src'];
            if (src != null) return _absFaUrl(src) ?? '';
            return '';
          })
          .where((url) => url.isNotEmpty)
          .toList();
      comment['iconBeforeUrls'] = iconBeforeUrls;
      comment['iconAfterUrls'] = iconAfterUrls;

      final popup = c.querySelector('.popup_date');
      comment['popupDateRelative'] = popup?.text.trim() ?? '';
      comment['popupDateFull'] = popup?.attributes['title'] ?? '';

      final hideA = c
          .querySelector('a[href*="action=hide_comment"][href*="comment_id="]');
      final unhideA = c.querySelector(
          'a[href*="action=unhide_comment"][href*="comment_id="]');
      final hasAnyUnhideAction =
          c.querySelector('a[href*="action=unhide_comment"]') != null;

      final editA = c.querySelector('a.edit_link') ??
          c.querySelector('a[title*="Edit this Comment"]') ??
          c.querySelector('a[href*="/edit/"]');

      final deleteA = c.querySelector('a[href*="action=delete_comment"]') ??
          c.querySelector('a[title*="Delete"]');

      final hideLink = _absFaUrl(hideA?.attributes['href']);
      final unhideLink = _absFaUrl(unhideA?.attributes['href']);
      final editLink = _absFaUrl(editA?.attributes['href']);
      final deleteLink = _absFaUrl(deleteA?.attributes['href']);

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

      final hasDeletedInner =
          c.querySelector('comment-container.deleted-comment-container') !=
              null;
      final lowerAll = c.text.toLowerCase();
      comment['deleted'] = hasDeletedInner ||
          hasAnyUnhideAction ||
          lowerAll.contains('comment hidden') ||
          lowerAll.contains('hidden by its owner');

      double width = 100.0;
      final style = c.attributes['style'] ?? '';
      final mw = RegExp(r'width\s*:\s*([0-9.]+)%').firstMatch(style);
      final commentTextElement =
          c.querySelector('.comment_text .user-submitted-links') ??
              c.querySelector('.comment_text') ??
              c.querySelector('comment-user-text .user-submitted-links') ??
              c.querySelector('comment-user-text');

      String? commentHtml;
      String? commentText;

      if (commentTextElement != null) {
        final cloned = commentTextElement.clone(true);

        // Remove control junk
        cloned
            .querySelectorAll('.floatright, div.floatright')
            .forEach((e) => e.remove());

        String normalizeFaHtml(dom.Element root) {
          final cloned = root.clone(true);

          cloned.querySelectorAll('span.bbcode_i').forEach((e) {
            e.replaceWith(dom.Element.tag('i')..innerHtml = e.innerHtml);
          });

          cloned.querySelectorAll('span.bbcode_b').forEach((e) {
            e.replaceWith(dom.Element.tag('b')..innerHtml = e.innerHtml);
          });

          cloned.querySelectorAll('span.bbcode_u').forEach((e) {
            e.replaceWith(dom.Element.tag('u')..innerHtml = e.innerHtml);
          });

          cloned.querySelectorAll('span.bbcode_center').forEach((e) {
            e.replaceWith(dom.Element.tag('div')
              ..attributes['style'] = 'text-align:center'
              ..innerHtml = e.innerHtml);
          });

          return cloned.innerHtml;
        }

        commentHtml = normalizeFaHtml(commentTextElement);
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
        String hiddenText = commentText ?? '';
        hiddenText = hiddenText
            .replaceAll(
              RegExp(r'Unhide\s+Comment(\s*<span.*?<\/span>)?',
                  caseSensitive: false),
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

      if (mw != null) {
        width = double.tryParse(mw.group(1)!) ?? 100.0;
      }
      comment['width'] = width;

      commentBodies.add(comment);
    }

    return commentBodies;
  }

  Future<OpenJournalFetchResult> fetchJournal(String uniqueNumber) async {
    final cookies = await _getCookies();
    final journalUrl = 'https://www.furaffinity.net/journal/$uniqueNumber/';
    final response = await FAHttp.get(
      Uri.parse(journalUrl),
      headers: {
        'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
          'a=${cookies.cookieA}; b=${cookies.cookieB}',
        ),
        'User-Agent': FAHttp.userAgent,
        'Accept-Encoding': 'gzip',
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
          'Failed to fetch journal ($uniqueNumber): ${response.statusCode}');
    }

    final decodedBody = utf8.decode(response.bodyBytes, allowMalformed: true);
    final document = html_parser.parse(decodedBody);

    final modernDetails = document.querySelector('userpage-nav-user-details');
    final classicTitleBox = document.querySelector('td.journal-title-box');
    final isJournalClassic =
        (modernDetails == null) && (classicTitleBox != null);

    dom.Element? profileImgEl;
    String? profileImageUrl;
    String? displayName;
    String? authorSlug;
    String? symbol;
    String? userTitle;

    profileImgEl = document.querySelector('userpage-nav-avatar img');
    dom.Element? profileAvatarAnchor =
        document.querySelector('userpage-nav-avatar a');

    if (!isJournalClassic && modernDetails != null) {
      final modernHeader = modernDetails.parent;
      profileImgEl = profileImgEl ??
          modernHeader?.querySelector('userpage-nav-avatar img');

      displayName = modernDetails
          .querySelector('a.c-usernameBlock__displayName span.js-displayName')
          ?.text
          .trim();

      final userNameA =
          modernDetails.querySelector('a.c-usernameBlock__userName') ??
              modernDetails.querySelector('a.c-usernameBlock__displayName');
      symbol =
          userNameA?.querySelector('span.c-usernameBlock__symbol')?.text.trim();

      final href = userNameA?.attributes['href'];
      if (href != null) {
        final path = Uri.parse(href).path.toLowerCase();
        final m = RegExp(r'^/user/([^/]+)/?$').firstMatch(path);
        if (m != null) authorSlug = m.group(1);
      }

      dom.Element? utSpan = modernDetails.querySelector('span.user-title') ??
          modernHeader?.querySelector('span.user-title') ??
          document.querySelector('userpage-nav-header span.user-title');

      if (utSpan != null) {
        final cleaned = utSpan.clone(true);
        cleaned
            .querySelectorAll('.hideonmobile, .popup_date')
            .forEach((e) => e.remove());

        var t = cleaned.text
            .replaceAll('\u00A0', ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();

        if (t.isNotEmpty) {
          var titlePart = t.split('|').first.trim();
          final looksLikeDate = RegExp(r'\d{4}').hasMatch(titlePart) &&
              RegExp(r'\d{1,2}:\d{2}').hasMatch(titlePart);

          if (titlePart.isNotEmpty && !looksLikeDate) {
            userTitle = titlePart;
          }
        }
      }
    } else if (isJournalClassic) {
      dom.Element? classicTable;
      dom.Node? cur = classicTitleBox;
      while (cur != null && (cur is! dom.Element || cur.localName != 'table')) {
        cur = cur.parent;
      }
      classicTable = cur is dom.Element ? cur : null;

      profileImgEl = profileImgEl ??
          classicTable?.querySelector('td.avatar-box img.avatar') ??
          document.querySelector('td.avatar-box img.avatar');

      displayName = classicTitleBox
          .querySelector('a.c-usernameBlock__displayName span.js-displayName')
          ?.text
          .trim();

      final userNameA =
          classicTitleBox.querySelector('a.c-usernameBlock__userName') ??
              classicTitleBox.querySelector('a.c-usernameBlock__displayName');
      symbol =
          userNameA?.querySelector('span.c-usernameBlock__symbol')?.text.trim();

      final href = userNameA?.attributes['href'];
      if (href != null) {
        final path = Uri.parse(href).path.toLowerCase();
        final m = RegExp(r'^/user/([^/]+)/?$').firstMatch(path);
        if (m != null) authorSlug = m.group(1);
      }
    }

    if (authorSlug == null && profileAvatarAnchor != null) {
      final href = profileAvatarAnchor.attributes['href'];
      if (href != null) {
        final m = RegExp(r'^/user/([^/]+)/?').firstMatch(href.toLowerCase());
        if (m != null) authorSlug = m.group(1);
      }
    }

    if (profileImgEl == null) {
      final ogImage = document
          .querySelector('meta[property="og:image"]')
          ?.attributes['content'];
      if (ogImage != null && ogImage.isNotEmpty) {
        profileImageUrl = ogImage.startsWith('//')
            ? 'https:$ogImage'
            : (ogImage.startsWith('http')
                ? ogImage
                : 'https://www.furaffinity.net$ogImage');
      }
    }

    if (profileImgEl != null && profileImageUrl == null) {
      var src = profileImgEl.attributes['src'];
      if (src != null && src.isNotEmpty) {
        if (src.startsWith('//')) {
          src = 'https:$src';
        } else if (src.startsWith('/')) {
          src = 'https://www.furaffinity.net$src';
        }
      }
      profileImageUrl = src;
    }

    final ownerEditLink = document
        .querySelector('a.owner_edit_journal.action-link')
        ?.attributes['href'];

    String? favoriteLink;
    String? unfavoriteLink;
    bool isFavorited = false;
    final favLinks = document.querySelectorAll('a.fav');
    for (var favLink in favLinks) {
      final href = favLink.attributes['href'] ?? '';
      if (href.contains('/fav/')) {
        favoriteLink = href;
        isFavorited = favLink.classes.contains('active');
      } else if (href.contains('/unfav/')) {
        unfavoriteLink = href;
      }
    }

    String? watchLink;
    String? unwatchLink;
    bool isWatching = false;
    final watchLinks = document.querySelectorAll('a.watch');
    for (var wl in watchLinks) {
      final href = wl.attributes['href'] ?? '';
      if (href.contains('/watch/')) {
        watchLink = href;
        isWatching = wl.classes.contains('active');
      } else if (href.contains('/unwatch/')) {
        unwatchLink = href;
      }
    }

    String? blockLink;
    String? unblockLink;
    bool isBlocked = false;
    final blockLinks = document.querySelectorAll('a.block');
    for (var bl in blockLinks) {
      final href = bl.attributes['href'] ?? '';
      if (href.contains('/block/')) {
        blockLink = href;
      } else if (href.contains('/unblock/')) {
        unblockLink = href;
        isBlocked = bl.classes.contains('active');
      }
    }

    String? title;
    String? submissionDescription;
    DateTime? publicationTime;
    String? publicationTimeRaw;

    title =
        document.querySelector('#c-journalTitleTop__subject h3')?.text.trim();
    title ??= document.querySelector('td.journal-title-box h2')?.text.trim();
    title ??= document.querySelector('title')?.text.trim();

    final dateElem =
        document.querySelector('#c-journalTitleTop__date .popup_date');
    if (dateElem != null) {
      final unix = int.tryParse(dateElem.attributes['data-time'] ?? '');
      if (unix != null) {
        publicationTime =
            DateTime.fromMillisecondsSinceEpoch(unix * 1000, isUtc: true);
      }

      publicationTimeRaw = dateElem.attributes['title'];

      if (publicationTime == null && publicationTimeRaw != null) {
        try {
          publicationTime = DateFormat('MMMM d, yyyy hh:mm:ss a')
              .parseUtc(publicationTimeRaw);
        } catch (_) {}
      }
    }

    if (publicationTime == null && publicationTimeRaw != null) {
      publicationTime = tryParseDate(publicationTimeRaw);
    }

    final descElem = document.querySelector('.journal-content') ??
        document.querySelector('.journal-body') ??
        document.querySelector('.journal-message');
    submissionDescription = descElem?.innerHtml;

    String? fullViewImageUrl;
    String? fileLink;
    String? category;
    String? type;
    String? species;
    String? gender;
    final keywords = <String>[];

    final statsTable =
        document.querySelector('table.maintable table.stats-container');
    if (statsTable != null) {
      final rows = statsTable.querySelectorAll('tr');
      for (var row in rows) {
        final label =
            row.querySelector('td:nth-child(1)')?.text.toLowerCase().trim() ??
                '';
        final value = row.querySelector('td:nth-child(2)')?.text.trim() ?? '';
        switch (label) {
          case 'category':
            category = value;
            break;
          case 'type':
            type = value;
            break;
          case 'species':
            species = value;
            break;
          case 'gender':
            gender = value;
            break;
        }
      }
    }

    document.querySelectorAll('a.keyword').forEach((a) {
      final kw = a.text.trim();
      if (kw.isNotEmpty) keywords.add(kw);
    });

    fullViewImageUrl = document.querySelector('a.fullview')?.attributes['href'];
    fileLink = document.querySelector('a.download')?.attributes['href'];

    final commentBodies = _parseCommentsFromDocument(document);

    int commentsCount = 0;
    String? footerCountText;
    final footerCountElem = document
            .querySelector('#comments-journal .section-footer .font-large') ??
        document.querySelector('.section-footer.aligncenter .font-large') ??
        document.querySelector('.section-footer .font-large');
    footerCountText = footerCountElem?.text.trim();
    if (footerCountText != null && footerCountText.isNotEmpty) {
      commentsCount = int.tryParse(footerCountText) ?? 0;
    }
    if (commentsCount == 0 && commentBodies.isNotEmpty) {
      commentsCount = commentBodies.length;
    }

    final deleteLink = _extractDeleteLinkFromDocument(document, uniqueNumber);

    return OpenJournalFetchResult(
      profileImageUrl: profileImageUrl,
      displayName: displayName,
      authorSlug: authorSlug,
      symbol: symbol,
      userTitle: userTitle,
      isJournalClassic: isJournalClassic,
      ownerEditLink: ownerEditLink,
      favoriteLink: favoriteLink,
      unfavoriteLink: unfavoriteLink,
      isFavorited: isFavorited,
      watchLink: watchLink,
      unwatchLink: unwatchLink,
      isWatching: isWatching,
      blockLink: blockLink,
      unblockLink: unblockLink,
      isBlocked: isBlocked,
      title: title,
      dateTime: publicationTime,
      dateTimeRaw: publicationTimeRaw,
      submissionDescription: submissionDescription,
      commentsCount: commentsCount,
      fullViewImageUrl: fullViewImageUrl,
      fileLink: fileLink,
      category: category,
      type: type,
      species: species,
      gender: gender,
      keywords: keywords,
      deleteLink: deleteLink,
      commentBodies: commentBodies,
    );
  }

  Future<String?> fetchDeleteLinkFromControls(String uniqueNumber) async {
    final cookies = await _getCookies();
    final candidateUrls = [
      'https://www.furaffinity.net/controls/journal/1/$uniqueNumber/',
      'https://www.furaffinity.net/controls/journal/',
    ];

    for (final url in candidateUrls) {
      final resp = await FAHttp.get(
        Uri.parse(url),
        headers: {
          'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
            'a=${cookies.cookieA}; b=${cookies.cookieB}',
          ),
          'User-Agent': FAHttp.userAgent,
          'Accept-Encoding': 'gzip',
          'Referer': 'https://www.furaffinity.net/journal/$uniqueNumber/',
        },
      );

      if (resp.statusCode != 200) {
        continue;
      }

      final doc =
          html_parser.parse(utf8.decode(resp.bodyBytes, allowMalformed: true));
      final deleteLink = _extractDeleteLinkFromDocument(doc, uniqueNumber);
      if (deleteLink != null) {
        return deleteLink;
      }
    }

    return null;
  }

  Future<bool> isJournalDeleted(String uniqueNumber) async {
    final cookies = await _getCookies();
    final response = await FAHttp.get(
      Uri.parse('https://www.furaffinity.net/journal/$uniqueNumber/'),
      headers: {
        'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
          'a=${cookies.cookieA}; b=${cookies.cookieB}',
        ),
        'User-Agent': FAHttp.userAgent,
        'Accept-Encoding': 'gzip',
      },
    );

    if (response.statusCode == 404) {
      return true;
    }

    if (response.statusCode != 200) {
      return false;
    }

    final doc =
        html_parser.parse(utf8.decode(response.bodyBytes, allowMalformed: true));
    return _looksLikeMissingJournalDocument(doc);
  }

  Future<Map<String, String?>> fetchUserPageLinks(String? authorSlug) async {
    final cookies = await _getCookies();
    if (authorSlug == null) {
      return {
        'watchLink': null,
        'unwatchLink': null,
        'blockLink': null,
        'unblockLink': null
      };
    }
    final url = 'https://www.furaffinity.net/user/$authorSlug/';
    final response = await FAHttp.get(
      Uri.parse(url),
      headers: {
        'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
          'a=${cookies.cookieA}; b=${cookies.cookieB}',
        ),
        'User-Agent': FAHttp.userAgent,
        'Accept-Encoding': 'gzip',
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
          'Failed to fetch user page links: ${response.statusCode}');
    }

    final document = html_parser
        .parse(utf8.decode(response.bodyBytes, allowMalformed: true));
    String? watchLink;
    String? unwatchLink;
    String? blockLink;
    String? unblockLink;

    final watchLinks = document.querySelectorAll('a.watch');
    for (var wl in watchLinks) {
      final href = wl.attributes['href'] ?? '';
      if (href.contains('/watch/')) {
        watchLink = href;
      } else if (href.contains('/unwatch/')) {
        unwatchLink = href;
      }
    }

    final blockLinks = document.querySelectorAll('a.block');
    for (var bl in blockLinks) {
      final href = bl.attributes['href'] ?? '';
      if (href.contains('/block/')) {
        blockLink = href;
      } else if (href.contains('/unblock/')) {
        unblockLink = href;
      }
    }

    return {
      'watchLink': watchLink,
      'unwatchLink': unwatchLink,
      'blockLink': blockLink,
      'unblockLink': unblockLink,
    };
  }

  Future<List<Map<String, dynamic>>> fetchCommentsFromBody(String body) async {
    final document = html_parser.parse(body);
    return _parseCommentsFromDocument(document);
  }

  DateTime? tryParseDate(String raw) {
    final trimmed = raw.trim();
    final formats = [
      DateFormat("MMMM d, yyyy h:mm:ss a"),
      DateFormat("MMMM d, yyyy hh:mm:ss a"),
      DateFormat("MMMM d, yyyy h:mm a"),
      DateFormat("MMMM d, yyyy hh:mm a"),
      DateFormat("MMM d, yyyy h:mm a"),
      DateFormat("MMM d, yyyy hh:mm a"),
      DateFormat("MMM d yyyy h:mm a"),
      DateFormat("yyyy-MM-dd HH:mm:ss"),
    ];
    for (final fmt in formats) {
      try {
        return fmt.parse(trimmed, true).toLocal();
      } catch (_) {}
    }
    return DateTime.tryParse(trimmed);
  }
}

class _Cookies {
  _Cookies({required this.cookieA, required this.cookieB});
  final String cookieA;
  final String cookieB;
}
