import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:fanotifier/features/journals/data/journal_document_parser.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:html/parser.dart' as html_parser;

import 'package:fanotifier/features/journals/data/journal_cookies.dart';
import 'package:fanotifier/features/journals/data/journal_delete_link_parser.dart';
import 'package:fanotifier/features/journals/data/journal_url_builder.dart';
import 'package:fanotifier/features/journals/domain/journal_fetch_result.dart';
import 'package:fanotifier/core/fa/fa_cookie_helper.dart';
import 'package:fanotifier/shared/fa/cloudflare_challenge_exception.dart';
import 'package:fanotifier/core/network/fa_http.dart';

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

    if (FaCookieHelper.isCloudflareChallengePage(
      body: response.body,
      statusCode: response.statusCode,
      headers: response.headers,
    )) {
      throw const CloudflareChallengeException();
    }
    if (response.statusCode != 200) {
      throw Exception(
          'Failed to fetch journal ($journalId): ${response.statusCode}');
    }

    return compute(
      parseJournalDocument,
      JournalDocumentInput(bytes: response.bodyBytes, journalId: journalId),
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

  Future<List<Map<String, dynamic>>> fetchCommentsFromBody(String body) {
    return compute(parseJournalCommentsBody, body);
  }

  DateTime? tryParseDate(String raw) => parseJournalDate(raw);
}
