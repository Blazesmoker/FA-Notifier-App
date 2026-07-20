import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'package:fanotifier/features/notifications/data/fa_notification_cookie_header_provider.dart';
import 'package:fanotifier/features/notifications/data/fa_notification_profile_shouts_parser.dart';
import 'package:fanotifier/features/notifications/data/notification_shout_parser.dart';
import 'package:fanotifier/features/notifications/data/simple_semaphore.dart';
import 'package:fanotifier/features/notifications/domain/fa_notification_models.dart';
import 'package:fanotifier/core/network/fa_http.dart';

class FaNotificationShoutRepository {
  FaNotificationShoutRepository({
    required SimpleSemaphore semaphore,
    FaNotificationCookieHeaderProvider cookieHeaderProvider =
        const FaNotificationCookieHeaderProvider(),
  })  : _semaphore = semaphore,
        _cookieHeaderProvider = cookieHeaderProvider;

  final SimpleSemaphore _semaphore;
  final FaNotificationCookieHeaderProvider _cookieHeaderProvider;
  bool _didFetchProfileShouts = false;
  final List<Shout> _profileShoutList = [];

  Future<List<Shout>> fetchProfileShouts(
    String myUsername, {
    bool forceRefresh = false,
  }) async {
    if (_didFetchProfileShouts && !forceRefresh) {
      debugPrint(
        '[fetchProfileShouts] Using cached _profileShoutList (size=${_profileShoutList.length})',
      );
      return _profileShoutList;
    }
    _didFetchProfileShouts = true;
    _profileShoutList.clear();
    final url = 'https://www.furaffinity.net/user/$myUsername/';
    debugPrint('[fetchProfileShouts] Fetching $url ...');
    await _semaphore.acquire();
    try {
      final cookieHeader = await _cookieHeaderProvider.load();
      final response = await FAHttp.get(
        Uri.parse(url),
        headers: {
          if (cookieHeader != null) 'Cookie': cookieHeader,
        },
      );
      if (response.statusCode == 200) {
        final document = html_parser.parse(response.body);
        parseNotificationProfileShouts(document, _profileShoutList);
      }
    } catch (error, stackTrace) {
      debugPrint('[fetchProfileShouts] Error: $error\n$stackTrace');
    } finally {
      _semaphore.release();
    }
    debugPrint(
      '[fetchProfileShouts] Returning ${_profileShoutList.length} items',
    );
    return _profileShoutList;
  }

  Future<List<Shout>> fetchMsgCenterShouts() async {
    debugPrint('[fetchMsgCenterShouts] Called');
    const url = 'https://www.furaffinity.net/msg/others/';
    try {
      final cookieHeader = await _cookieHeaderProvider.load();
      final response = await FAHttp.get(
        Uri.parse(url),
        headers: {
          if (cookieHeader != null) 'Cookie': cookieHeader,
        },
      );
      if (response.statusCode != 200) return <Shout>[];
      final document = html_parser.parse(response.body);
      return await _fetchMsgCenterShoutsFromDocument(document);
    } catch (error, stackTrace) {
      debugPrint('[fetchMsgCenterShouts] Error: $error\n$stackTrace');
      return <Shout>[];
    }
  }

  Future<List<Map<String, dynamic>>> fetchMsgOthersShouts() async {
    const url = 'https://www.furaffinity.net/msg/others/';
    debugPrint('[fetchMsgOthersShouts] Checking $url...');
    try {
      final cookieHeader = await _cookieHeaderProvider.load();
      final response = await FAHttp.get(
        Uri.parse(url),
        headers: {
          if (cookieHeader != null) 'Cookie': cookieHeader,
        },
      );
      if (response.statusCode != 200) return <Map<String, dynamic>>[];
      final document = html_parser.parse(response.body);
      return parseMessageCenterShouts(document);
    } catch (error, stackTrace) {
      debugPrint('[fetchMsgOthersShouts] Error: $error\n$stackTrace');
      return <Map<String, dynamic>>[];
    }
  }

  Future<List<Shout>> _fetchMsgCenterShoutsFromDocument(
    dom.Document document,
  ) async {
    final messageItems = parseMessageCenterShouts(document);
    debugPrint(
      '[fetchMsgCenterShouts] msgItems count=${messageItems.length}',
    );
    final myUsername = extractNotificationMenubarUsername(document);
    if (myUsername.isEmpty) {
      debugPrint(
        '[fetchMsgCenterShouts] No user found in menubar; profile parse skipped.',
      );
      return mergeMessageCenterShoutsWithProfile(
        messageItems: messageItems,
        profileShouts: const [],
      );
    }

    final needsProfileMerge = messageItems.any((message) {
      final removed = message['isRemoved'] as bool? ?? false;
      if (removed) return false;
      final avatar = (message['avatarUrl'] as String? ?? '').trim();
      final text = (message['textHtml'] as String? ?? '').trim();
      return avatar.isEmpty && text.isEmpty;
    });
    if (!needsProfileMerge) {
      return mergeMessageCenterShoutsWithProfile(
        messageItems: messageItems,
        profileShouts: const [],
      );
    }

    final profileShouts = await fetchProfileShouts(
      myUsername,
      forceRefresh: true,
    );
    return mergeMessageCenterShoutsWithProfile(
      messageItems: messageItems,
      profileShouts: profileShouts,
    );
  }
}
