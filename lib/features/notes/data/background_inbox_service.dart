import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:html/parser.dart' as html_parser;

import 'package:FANotifier/features/notes/data/background_inbox_parser.dart';
import 'package:FANotifier/features/notes/domain/background_inbox_models.dart';
import 'package:FANotifier/features/notes/domain/inbox_second_page_policy.dart';
import 'package:FANotifier/features/notes/domain/message_model.dart';
import 'package:FANotifier/shared/fa/fa_cookie_helper.dart';
import 'package:FANotifier/shared/fa/fa_http.dart';

class BackgroundInboxService {
  BackgroundInboxService({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                accountName: 'flutter_secure_storage_service',
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _secureStorage;

  Future<BackgroundInboxSnapshot> fetchSnapshot({
    required Set<String> shownNoteIds,
    required Set<String> seenNoteIds,
  }) async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    if (cookieA == null || cookieB == null) {
      debugPrint('[BG] No cookies found - user not logged in');
      throw Exception('Not logged in');
    }

    final page1 = await _fetchPage(
      page: 1,
      cookieA: cookieA,
      cookieB: cookieB,
    );
    final result = <Message>[...page1.messages];
    var fetchedPage2 = false;

    if (shouldFetchSecondInboxPage(
      page1Messages: page1.messages,
      shownNoteIds: shownNoteIds,
      seenNoteIds: seenNoteIds,
      topbarNotes: page1.topbarCounts?.notes,
    )) {
      final page2 = await _fetchPage(
        page: 2,
        cookieA: cookieA,
        cookieB: cookieB,
      );
      result.addAll(page2.messages);
      fetchedPage2 = true;
    }

    return BackgroundInboxSnapshot(
      messages: result,
      topbarCounts: page1.topbarCounts,
      fetchedPage2: fetchedPage2,
    );
  }

  Future<BackgroundInboxPage> _fetchPage({
    required int page,
    required String cookieA,
    required String cookieB,
  }) async {
    final url = Uri.parse('https://www.furaffinity.net/msg/pms/$page/');
    final response = await FAHttp.get(
      url,
      headers: {
        'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
          'a=$cookieA; b=$cookieB; folder=inbox',
        ),
        'User-Agent': FAHttp.userAgent,
      },
    );
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final decoded = utf8.decode(response.bodyBytes, allowMalformed: true);
    final document = html_parser.parse(decoded);
    return parseBackgroundInboxPage(
      document,
      includeTopbarCounts: page == 1,
    );
  }
}

Future<BackgroundInboxSnapshot> fetchBackgroundInboxSnapshot({
  required Set<String> shownNoteIds,
  required Set<String> seenNoteIds,
}) {
  return BackgroundInboxService().fetchSnapshot(
    shownNoteIds: shownNoteIds,
    seenNoteIds: seenNoteIds,
  );
}
