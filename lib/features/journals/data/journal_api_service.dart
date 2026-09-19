import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'package:fanotifier/features/journals/data/journal_cookies.dart';
import 'package:fanotifier/features/journals/data/journal_comment_parser.dart';
import 'package:fanotifier/features/journals/data/journal_delete_link_parser.dart';
import 'package:fanotifier/features/journals/data/journal_url_builder.dart';
import 'package:fanotifier/features/journals/domain/journal_fetch_result.dart';
import 'package:fanotifier/core/fa/fa_cookie_helper.dart';
import 'package:fanotifier/core/network/fa_http.dart';
import 'package:fanotifier/shared/fa/user_submitted_html_linkifier.dart';

class JournalApiService {
  JournalApiService({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                accountName: 'flutter_secure_storage_service',
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _secureStorage;

  Future<JournalCookies> _getCookies() async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    if (cookieA == null || cookieB == null) {
      throw Exception('Not logged in: missing cookies');
    }
    return JournalCookies(cookieA: cookieA, cookieB: cookieB);
  }

  Future<JournalFetchResult> fetchJournal(String journalId) async {
    final cookies = await _getCookies();
    final journalUrl = buildFaJournalUrl(journalId);
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
          'Failed to fetch journal ($journalId): ${response.statusCode}');
    }

    final decodedBody = utf8.decode(response.bodyBytes, allowMalformed: true);
    final document = html_parser.parse(decodedBody);

    final modernDetails = document.querySelector('userpage-nav-user-details');
    final classicTitleBox = document.querySelector('td.journal-title-box');
    final isJournalClassic =
        (modernDetails == null) && (classicTitleBox != null);

    dom.Element? profileImageElement;
    String? profileImageUrl;
    String? displayName;
    String? authorSlug;
    String? symbol;
    String? userTitle;

    profileImageElement = document.querySelector('userpage-nav-avatar img');
    dom.Element? profileAvatarAnchor =
        document.querySelector('userpage-nav-avatar a');

    if (!isJournalClassic && modernDetails != null) {
      final modernHeader = modernDetails.parent;
      profileImageElement = profileImageElement ??
          modernHeader?.querySelector('userpage-nav-avatar img');

      displayName = modernDetails
          .querySelector('a.c-usernameBlock__displayName span.js-displayName')
          ?.text
          .trim();

      final usernameLink =
          modernDetails.querySelector('a.c-usernameBlock__userName') ??
              modernDetails.querySelector('a.c-usernameBlock__displayName');
      symbol =
          usernameLink?.querySelector('span.c-usernameBlock__symbol')?.text.trim();

      final href = usernameLink?.attributes['href'];
      if (href != null) {
        final path = Uri.parse(href).path.toLowerCase();
        final usernameMatch = RegExp(r'^/user/([^/]+)/?$').firstMatch(path);
        if (usernameMatch != null) authorSlug = usernameMatch.group(1);
      }

      dom.Element? userTitleElement = modernDetails.querySelector('span.user-title') ??
          modernHeader?.querySelector('span.user-title') ??
          document.querySelector('userpage-nav-header span.user-title');

      if (userTitleElement != null) {
        final cleaned = userTitleElement.clone(true);
        cleaned
            .querySelectorAll('.hideonmobile, .popup_date')
            .forEach((e) => e.remove());

        var cleanedTitleText = cleaned.text
            .replaceAll('\u00A0', ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();

        if (cleanedTitleText.isNotEmpty) {
          var titlePart = cleanedTitleText.split('|').first.trim();
          final looksLikeDate = RegExp(r'\d{4}').hasMatch(titlePart) &&
              RegExp(r'\d{1,2}:\d{2}').hasMatch(titlePart);

          if (titlePart.isNotEmpty && !looksLikeDate) {
            userTitle = titlePart;
          }
        }
      }
    } else if (isJournalClassic) {
      dom.Element? classicTable;
      dom.Node? ancestor = classicTitleBox;
      while (ancestor != null && (ancestor is! dom.Element || ancestor.localName != 'table')) {
        ancestor = ancestor.parent;
      }
      classicTable = ancestor is dom.Element ? ancestor : null;

      profileImageElement = profileImageElement ??
          classicTable?.querySelector('td.avatar-box img.avatar') ??
          document.querySelector('td.avatar-box img.avatar');

      displayName = classicTitleBox
          .querySelector('a.c-usernameBlock__displayName span.js-displayName')
          ?.text
          .trim();

      final usernameLink =
          classicTitleBox.querySelector('a.c-usernameBlock__userName') ??
              classicTitleBox.querySelector('a.c-usernameBlock__displayName');
      symbol =
          usernameLink?.querySelector('span.c-usernameBlock__symbol')?.text.trim();

      final href = usernameLink?.attributes['href'];
      if (href != null) {
        final path = Uri.parse(href).path.toLowerCase();
        final usernameMatch = RegExp(r'^/user/([^/]+)/?$').firstMatch(path);
        if (usernameMatch != null) authorSlug = usernameMatch.group(1);
      }
    }

    if (authorSlug == null && profileAvatarAnchor != null) {
      final href = profileAvatarAnchor.attributes['href'];
      if (href != null) {
        final usernameMatch = RegExp(r'^/user/([^/]+)/?').firstMatch(href.toLowerCase());
        if (usernameMatch != null) authorSlug = usernameMatch.group(1);
      }
    }

    if (profileImageElement == null) {
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

    if (profileImageElement != null && profileImageUrl == null) {
      var src = profileImageElement.attributes['src'];
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
    submissionDescription = descElem == null
        ? null
        : linkifyBareWebUrlsInHtml(descElem.innerHtml);

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

    final commentBodies = parseJournalComments(document);

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

    final deleteLink = extractJournalDeleteLink(document, journalId);

    return JournalFetchResult(
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

  Future<String?> fetchDeleteLinkFromControls(String journalId) async {
    final cookies = await _getCookies();
    final candidateUrls = [
      'https://www.furaffinity.net/controls/journal/1/$journalId/',
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
          'Referer': buildFaJournalUrl(journalId),
        },
      );

      if (resp.statusCode != 200) {
        continue;
      }

      final doc =
          html_parser.parse(utf8.decode(resp.bodyBytes, allowMalformed: true));
      final deleteLink = extractJournalDeleteLink(doc, journalId);
      if (deleteLink != null) {
        return deleteLink;
      }
    }

    return null;
  }

  Future<bool> isJournalDeleted(String journalId) async {
    final cookies = await _getCookies();
    final response = await FAHttp.get(
      Uri.parse(buildFaJournalUrl(journalId)),
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
    return looksLikeMissingJournalDocument(doc);
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
    return parseJournalComments(document);
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
