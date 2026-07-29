import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:fanotifier/features/profile/domain/shout.dart';
import 'package:fanotifier/features/profile/data/user_profile_html_parser.dart';
import 'package:fanotifier/features/profile/data/user_profile_shouts_parser.dart';
import 'package:fanotifier/features/profile/data/user_profile_controls_shout_matcher.dart';
import 'package:fanotifier/features/profile/data/user_profile_controls_shouts_parser.dart';
import 'package:fanotifier/features/profile/domain/user_profile_api_models.dart';
import 'package:fanotifier/core/fa/fa_cookie_helper.dart';
import 'package:fanotifier/core/network/fa_http.dart';
import 'package:fanotifier/shared/fa/fa_username.dart';
import 'package:flutter/material.dart';

UserProfileParsed parseUserProfileHtml(String htmlBody) {
  return UserProfileApiService.parseUserProfile(htmlBody);
}

class UserProfileApiService {
  UserProfileApiService({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                accountName: 'flutter_secure_storage_service',
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _secureStorage;

  String _sanitizeUsername(String username) {
    return sanitizeFAUsername(username);
  }

  Future<UserProfileFetchPayload> fetchProfile({
    required String nickname,
    required bool sfwEnabled,
  }) async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');

    if (cookieA == null || cookieB == null) {
      throw StateError('No cookies found. User might not be logged in.');
    }

    final sanitizedUsername = _sanitizeUsername(nickname);
    final sfwValue = sfwEnabled ? '1' : '0';
    final profileUrl = 'https://www.furaffinity.net/user/$sanitizedUsername/';

    final response = await FAHttp.get(
      Uri.parse(profileUrl),
      headers: {
        'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
          'a=$cookieA; b=$cookieB; sfw=$sfwValue',
        ),
        'User-Agent': FAHttp.userAgent,
      },
    );

    if (response.statusCode != 200) {
      throw HttpException(
        'Failed to fetch profile: ${response.statusCode}',
        uri: Uri.parse(profileUrl),
      );
    }

    final decodedBody = utf8.decode(response.bodyBytes, allowMalformed: true);

    return UserProfileFetchPayload(
      sanitizedUsername: sanitizedUsername,
      htmlBody: decodedBody,
      sfwValue: sfwValue,
    );
  }

  Future<ShoutPagePayload?> fetchShoutPage({
    required String sanitizedUsername,
    required String? shoutPaginationKey,
    required int nextPage,
    required bool sfwEnabled,
  }) async {
    if (shoutPaginationKey == null || shoutPaginationKey.isEmpty) {
      return null;
    }

    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    if (cookieA == null || cookieB == null) {
      throw StateError('No cookies found. User might not be logged in.');
    }

    final sfwValue = sfwEnabled ? '1' : '0';
    final url = 'https://www.furaffinity.net/user/$sanitizedUsername/';

    final response = await FAHttp.post(
      Uri.parse(url),
      headers: {
        'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
          'a=$cookieA; b=$cookieB; sfw=$sfwValue',
        ),
        'Content-Type': 'application/x-www-form-urlencoded',
        'User-Agent': FAHttp.userAgent,
        'Referer': 'https://www.furaffinity.net/user/$sanitizedUsername/',
        'X-Requested-With': 'XMLHttpRequest',
      },
      body: {
        'action': 'shout_pagination',
        'key': shoutPaginationKey,
        'shout_page': nextPage.toString(),
      },
    );

    if (response.statusCode != 200) {
      throw HttpException(
        'Failed to load shouts page: ${response.statusCode}',
        uri: Uri.parse(url),
      );
    }

    final decodedBody = utf8.decode(response.bodyBytes, allowMalformed: true);
    return ShoutPagePayload(body: decodedBody, nextPage: nextPage);
  }

  Future<AdditionalShoutsPayload?> fetchAdditionalShouts({
    required String sanitizedUsername,
    required String? shoutPaginationKey,
    required int nextPage,
    required bool sfwEnabled,
    required Set<String> existingShoutIds,
  }) async {
    final payload = await fetchShoutPage(
      sanitizedUsername: sanitizedUsername,
      shoutPaginationKey: shoutPaginationKey,
      nextPage: nextPage,
      sfwEnabled: sfwEnabled,
    );
    if (payload == null) return null;

    final newShouts = parseAdditionalShoutsJson(
      payload.body,
      existingShoutIds,
      nextPage,
    );
    return AdditionalShoutsPayload(
        newShouts: newShouts, nextPage: payload.nextPage);
  }

  Future<WatchUnwatchResult> sendWatchUnwatchRequest(
    String urlPath, {
    required bool shouldWatch,
    required bool sfwEnabled,
  }) async {
    String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');

    final sfwValue = sfwEnabled ? '1' : '0';

    if (cookieA == null || cookieB == null) {
      return const WatchUnwatchResult(
        success: false,
        missingCookies: true,
      );
    }

    final fullUrl = 'https://www.furaffinity.net$urlPath';
    try {
      final response = await FAHttp.get(
        Uri.parse(fullUrl),
        headers: {
          'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
            'a=$cookieA; b=$cookieB; sfw=$sfwValue',
          ),
          'User-Agent': FAHttp.userAgent,
        },
      );

      return WatchUnwatchResult(
        success: response.statusCode == 200,
        missingCookies: false,
        statusCode: response.statusCode,
      );
    } catch (e) {
      return WatchUnwatchResult(
        success: false,
        missingCookies: false,
        error: e,
      );
    }
  }

  Future<BlockUnblockResult> sendBlockUnblockRequest(
    String urlOrPath,
    String keyValue, {
    required bool shouldBlock,
    required bool usePost,
    required bool sfwEnabled,
    required String sanitizedUsername,
  }) async {
    String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    final sfwValue = sfwEnabled ? '1' : '0';

    if (cookieA == null || cookieB == null) {
      return const BlockUnblockResult(
        success: false,
        missingCookies: true,
      );
    }

    final fullUrl = urlOrPath.startsWith('http')
        ? urlOrPath
        : 'https://www.furaffinity.net$urlOrPath';

    final uri = Uri.parse(fullUrl);

    final targetUrl = uri.toString();

    String refererUsername = sanitizedUsername;

    final segments = uri.pathSegments;

    if (segments.length >= 2 &&
        (segments.first == 'block' || segments.first == 'unblock')) {
      final candidateUsername = segments[1];
      refererUsername = candidateUsername;
    } else {
      debugPrint(
          '[_sendBlockUnblockRequest] Did NOT detect /block/username or /unblock/username pattern. Keeping sanitizedUsername.');
    }

    try {
      final uriTarget = Uri.parse(targetUrl);

      final headers = <String, String>{
        'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
          'a=$cookieA; b=$cookieB; sfw=$sfwValue',
        ),
        'User-Agent': FAHttp.userAgent,
        'Referer': 'https://www.furaffinity.net/user/$refererUsername/',
      };

      debugPrint('[_sendBlockUnblockRequest] headers prepared');

      late http.Response response;

      if (usePost) {
        response = await FAHttp.post(
          uriTarget,
          headers: {
            ...headers,
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: {'key': keyValue},
        );
      } else {
        response = await FAHttp.get(uriTarget, headers: headers);
      }

      response.headers.forEach((k, v) {
        debugPrint('    $k: $v');
      });

      final previewLength = min(500, response.body.length);
      final previewBody = response.body.substring(0, previewLength);
      debugPrint(previewBody);

      return BlockUnblockResult(
        success: response.statusCode == 302 || response.statusCode == 200,
        missingCookies: false,
        statusCode: response.statusCode,
      );
    } catch (e) {
      return BlockUnblockResult(
        success: false,
        missingCookies: false,
        error: e,
      );
    }
  }

  Future<DeleteShoutResult> deleteShout({
    required String shoutId,
    required bool sfwEnabled,
  }) async {
    return deleteShouts(
      shoutIds: [shoutId],
      sfwEnabled: sfwEnabled,
    );
  }

  Future<DeleteShoutResult> deleteShouts({
    required List<String> shoutIds,
    required bool sfwEnabled,
    int? page,
  }) async {
    if (shoutIds.isEmpty) {
      return const DeleteShoutResult(
        success: false,
        missingCookies: false,
      );
    }

    String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');

    final sfwValue = sfwEnabled ? '1' : '0';

    if (cookieA == null || cookieB == null) {
      return const DeleteShoutResult(
        success: false,
        missingCookies: true,
      );
    }

    final url = "https://www.furaffinity.net/controls/shouts/";
    try {
      final response = await FAHttp.post(
        Uri.parse(url),
        headers: {
          'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
            'a=$cookieA; b=$cookieB; sfw=$sfwValue',
          ),
          'Content-Type': 'application/x-www-form-urlencoded',
          'User-Agent': FAHttp.userAgent,
          'Referer': 'https://www.furaffinity.net/controls/shouts/',
        },
        body: _encodeFormBody([
          const MapEntry('do', 'update'),
          if (page != null) MapEntry('page', max(1, page).toString()),
          ...shoutIds.map((shoutId) => MapEntry('shouts[]', shoutId)),
        ]),
      );

      return DeleteShoutResult(
        success: response.statusCode == 200 || response.statusCode == 302,
        missingCookies: false,
        statusCode: response.statusCode,
      );
    } catch (e) {
      return DeleteShoutResult(
        success: false,
        missingCookies: false,
        error: e,
      );
    }
  }

  String _encodeFormBody(List<MapEntry<String, String>> fields) {
    return fields
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
        )
        .join('&');
  }

  Future<ControlsShoutsPageInfo> fetchControlsShoutsPage({
    required int page,
    required bool sfwEnabled,
  }) async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    if (cookieA == null || cookieB == null) {
      throw StateError('No cookies found. User might not be logged in.');
    }

    final sfwValue = sfwEnabled ? '1' : '0';
    final pageNumber = max(1, page);
    final uri =
        Uri.parse('https://www.furaffinity.net/controls/shouts/').replace(
      queryParameters: pageNumber == 1 ? null : {'page': pageNumber.toString()},
    );

    final response = await FAHttp.get(
      uri,
      headers: {
        'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
          'a=$cookieA; b=$cookieB; sfw=$sfwValue',
        ),
        'User-Agent': FAHttp.userAgent,
        'Referer': 'https://www.furaffinity.net/controls/shouts/',
      },
    );

    if (response.statusCode != 200) {
      throw HttpException(
        'Failed to fetch controls shouts page: ${response.statusCode}',
        uri: uri,
      );
    }

    final decodedBody = utf8.decode(response.bodyBytes, allowMalformed: true);
    return parseUserProfileControlsShoutsPage(
      htmlBody: decodedBody,
      pageNumber: pageNumber,
    );
  }

  Future<List<ResolvedControlsShout>> resolveControlsShouts({
    required List<Shout> shouts,
    required bool sfwEnabled,
  }) async {
    final resolved = <ResolvedControlsShout>[];
    final usedIds = <String>{};
    var remaining = List<Shout>.from(shouts);
    int page = 1;
    int totalPages = 1;

    while (remaining.isNotEmpty && page <= totalPages) {
      final pageInfo = await fetchControlsShoutsPage(
        page: page,
        sfwEnabled: sfwEnabled,
      );
      totalPages = max(totalPages, pageInfo.totalPages);

      final unresolved = <Shout>[];
      for (final shout in remaining) {
        final match = findMatchingUserProfileControlsShout(
          entries: pageInfo.entries,
          shout: shout,
          usedIds: usedIds,
        );
        if (match == null) {
          unresolved.add(shout);
          continue;
        }

        usedIds.add(match.id);
        resolved.add(
          ResolvedControlsShout(
            shout: shout,
            id: match.id,
            page: match.page,
          ),
        );
      }

      remaining = unresolved;
      page += 1;
    }

    return resolved;
  }

  Future<Map<String, int>> resolveControlsPagesForShouts({
    required List<String> shoutIds,
    required bool sfwEnabled,
  }) async {
    final remaining = shoutIds.toSet();
    final resolved = <String, int>{};
    int page = 1;
    int totalPages = 1;

    while (remaining.isNotEmpty && page <= totalPages) {
      final pageInfo = await fetchControlsShoutsPage(
        page: page,
        sfwEnabled: sfwEnabled,
      );
      totalPages = max(totalPages, pageInfo.totalPages);

      for (final shoutId in pageInfo.shoutIds) {
        if (remaining.remove(shoutId)) {
          resolved[shoutId] = pageInfo.page;
        }
      }

      page += 1;
    }

    return resolved;
  }

  List<Shout> parseAdditionalShoutsJson(
    String jsonBody,
    Set<String> existingShoutIds,
    int sourcePage,
  ) {
    return parseAdditionalProfileShoutsJson(
      jsonBody,
      existingShoutIds,
      sourcePage,
    );
  }

  static UserProfileParsed parseUserProfile(String htmlBody) {
    return parseUserProfileHtmlDocument(htmlBody);
  }
}
