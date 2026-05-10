import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'package:FANotifier/shared/fa/network.dart';
import 'package:FANotifier/features/profile/domain/shout.dart';
import 'package:FANotifier/features/profile/domain/user_link.dart';
import 'package:flutter/cupertino.dart';
import 'package:FANotifier/shared/fa/fa_cookie_helper.dart';
import 'package:FANotifier/shared/fa/fa_http.dart';

class UserProfileParsed {
  UserProfileParsed({
    required this.profileBannerUrl,
    required this.profileImageUrl,
    required this.profileDisplayName,
    required this.profileUserNamePart,
    required this.symbolUsername,
    required this.username,
    required this.userTitle,
    required this.registrationDate,
    required this.userDescription,
    required this.hasRealUserProfile,
    required this.isClassicMarkup,
    required this.acceptingTrades,
    required this.acceptingCommissions,
    required this.userIconBeforeUrls,
    required this.userIconAfterUrls,
    required this.views,
    required this.submissions,
    required this.favs,
    required this.commentsEarned,
    required this.commentsMade,
    required this.journals,
    required this.featuredImageUrl,
    required this.featuredImageTitle,
    required this.featuredPostNumber,
    required this.userProfileImageUrl,
    required this.userProfilePostNumber,
    required this.userProfileTexts,
    required this.contactInformationLinks,
    required this.recentWatchers,
    required this.recentWatchersCount,
    required this.recentlyWatched,
    required this.recentlyWatchedCount,
    required this.shouts,
    required this.shoutPaginationKey,
    required this.currentShoutPage,
    required this.totalShoutPages,
    required this.watchLink,
    required this.unwatchLink,
    required this.blockLink,
    required this.unblockLink,
    required this.blockUsesPost,
    required this.unblockUsesPost,
    required this.isWatching,
    required this.isBlocked,
    required this.isOwnProfile,
  });

  String? profileBannerUrl;
  String? profileImageUrl;
  String? profileDisplayName;
  String? profileUserNamePart;
  String? symbolUsername;
  String username;
  String? userTitle;
  String? registrationDate;
  String? userDescription;
  bool hasRealUserProfile;
  bool isClassicMarkup;
  bool acceptingTrades;
  bool acceptingCommissions;
  List<String> userIconBeforeUrls;
  List<String> userIconAfterUrls;
  int? views;
  int? submissions;
  int? favs;
  int? commentsEarned;
  int? commentsMade;
  int? journals;
  String? featuredImageUrl;
  String? featuredImageTitle;
  String? featuredPostNumber;
  String? userProfileImageUrl;
  String? userProfilePostNumber;
  String? userProfileTexts;
  List<Map<String, String>> contactInformationLinks;
  List<UserLink> recentWatchers;
  int recentWatchersCount;
  List<UserLink> recentlyWatched;
  int recentlyWatchedCount;
  List<Shout> shouts;
  String? shoutPaginationKey;
  int currentShoutPage;
  int totalShoutPages;
  String? watchLink;
  String? unwatchLink;
  String? blockLink;
  String? unblockLink;
  bool blockUsesPost;
  bool unblockUsesPost;
  bool isWatching;
  bool isBlocked;
  bool isOwnProfile;
}

UserProfileParsed parseUserProfileHtml(String htmlBody) {
  return UserProfileApiService.parseUserProfile(htmlBody);
}

class UserProfileFetchPayload {
  final String sanitizedUsername;
  final String htmlBody;
  final String sfwValue;

  UserProfileFetchPayload({
    required this.sanitizedUsername,
    required this.htmlBody,
    required this.sfwValue,
  });
}

class ShoutPagePayload {
  final String body;
  final int nextPage;

  ShoutPagePayload({
    required this.body,
    required this.nextPage,
  });
}

class WatchUnwatchResult {
  final bool success;
  final bool missingCookies;
  final int? statusCode;
  final Object? error;

  const WatchUnwatchResult({
    required this.success,
    required this.missingCookies,
    this.statusCode,
    this.error,
  });
}

class BlockUnblockResult {
  final bool success;
  final bool missingCookies;
  final int? statusCode;
  final Object? error;

  const BlockUnblockResult({
    required this.success,
    required this.missingCookies,
    this.statusCode,
    this.error,
  });
}

class DeleteShoutResult {
  final bool success;
  final bool missingCookies;
  final int? statusCode;
  final Object? error;

  const DeleteShoutResult({
    required this.success,
    required this.missingCookies,
    this.statusCode,
    this.error,
  });
}

class AdditionalShoutsPayload {
  final List<Shout> newShouts;
  final int nextPage;

  const AdditionalShoutsPayload({
    required this.newShouts,
    required this.nextPage,
  });
}

class ControlsShoutsPageInfo {
  final int page;
  final int totalPages;
  final Set<String> shoutIds;
  final List<ControlsShoutEntry> entries;

  const ControlsShoutsPageInfo({
    required this.page,
    required this.totalPages,
    required this.shoutIds,
    required this.entries,
  });
}

class ControlsShoutEntry {
  final String id;
  final int page;
  final String avatarUrl;
  final String profileNickname;
  final String popupDateFull;
  final String messageHtml;

  const ControlsShoutEntry({
    required this.id,
    required this.page,
    required this.avatarUrl,
    required this.profileNickname,
    required this.popupDateFull,
    required this.messageHtml,
  });
}

class ResolvedControlsShout {
  final Shout shout;
  final String id;
  final int page;

  const ResolvedControlsShout({
    required this.shout,
    required this.id,
    required this.page,
  });
}

class UserProfileApiService {
  UserProfileApiService(this._secureStorage);

  final FlutterSecureStorage _secureStorage;
  final RegExp _usernameSanitizeRegex = RegExp(r'[^a-zA-Z0-9_.~-]');

  String _sanitizeUsername(String username) {
    return username.replaceAll(_usernameSanitizeRegex, '').toLowerCase();
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

    final response = await httpClient.get(
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

    final response = await http.post(
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
      final response = await httpClient.get(
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

      headers.forEach((k, v) {
        if (k.toLowerCase() == 'cookie') {
          debugPrint(
              '  $k: ${v.substring(0, v.length.clamp(0, 200))}${v.length > 200 ? '... (truncated)' : ''}');
        } else {
          debugPrint('  $k: $v');
        }
      });

      late http.Response response;

      if (usePost) {
        response = await http.post(
          uriTarget,
          headers: {
            ...headers,
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: {'key': keyValue},
        );
      } else {
        response = await http.get(uriTarget, headers: headers);
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
      final response = await http.post(
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

    final response = await httpClient.get(
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
    final document = html_parser.parse(decodedBody);

    final entries = <ControlsShoutEntry>[];
    final shoutContainers = document.querySelectorAll(
      'form#shouts-form #shouts-list div.comment_container',
    );
    for (final container in shoutContainers) {
      final checkbox = container.querySelector(
        'input[type="checkbox"][name="shouts[]"]',
      );
      final shoutId = _normalizeShoutIdValue(checkbox?.attributes['value']);
      if (shoutId.isEmpty) {
        continue;
      }

      final avatarElem = container.querySelector('img.comment_useravatar');
      final avatarUrl = _normalizeComparableUrl(
        avatarElem?.attributes['src'] ?? '',
      );

      final profileLink = container.querySelector(
        '.avatar a[href*="/user/"], '
        'a.c-usernameBlock__userName[href*="/user/"], '
        'a.c-usernameBlock__displayName[href*="/user/"]',
      );
      final profileNickname = _extractProfileNickname(
        profileLink?.attributes['href'],
      );

      final dateElem = container.querySelector('span.popup_date');
      final popupDateFull = _normalizeComparableValue(
        dateElem?.attributes['title'] ?? dateElem?.text ?? '',
      );

      final messageElem =
          container.querySelector('comment-user-text.comment_text');
      final messageHtml = messageElem?.innerHtml.trim() ?? '';

      entries.add(
        ControlsShoutEntry(
          id: shoutId,
          page: pageNumber,
          avatarUrl: avatarUrl,
          profileNickname: profileNickname,
          popupDateFull: popupDateFull,
          messageHtml: messageHtml,
        ),
      );
    }

    final ids = entries.map((entry) => entry.id).toSet();

    final options = document.querySelectorAll(
      'form.c-shoutPaginationForm select[name="page"] option',
    );
    final pageValues = options
        .map((option) => int.tryParse(option.attributes['value'] ?? ''))
        .whereType<int>()
        .toSet();
    final totalPages = pageValues.isEmpty ? 1 : pageValues.reduce(max);

    return ControlsShoutsPageInfo(
      page: pageNumber,
      totalPages: totalPages,
      shoutIds: ids,
      entries: entries,
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
        final match = _findMatchingControlsEntry(
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

  String _normalizeShoutIdValue(dynamic rawValue) {
    if (rawValue == null) {
      return '';
    }

    final value = rawValue.toString().trim();
    if (value.isEmpty) {
      return '';
    }

    if (RegExp(r'^\d+$').hasMatch(value)) {
      return value;
    }

    final anchorMatch = RegExp(r'shout-(\d+)').firstMatch(value);
    if (anchorMatch != null) {
      return anchorMatch.group(1) ?? '';
    }

    return '';
  }

  String _extractShoutIdFromPayload(Map<String, dynamic> shoutData) {
    const directKeys = ['anchor_id', 'anchor', 'id', 'shout_id', 'comment_id'];

    for (final key in directKeys) {
      final normalized = _normalizeShoutIdValue(shoutData[key]);
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }

    for (final value in shoutData.values) {
      final normalized = _extractShoutIdFromDynamic(value);
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }

    return '';
  }

  String _extractShoutIdFromDynamic(dynamic value) {
    final direct = _normalizeShoutIdValue(value);
    if (direct.isNotEmpty) {
      return direct;
    }

    if (value is Map) {
      for (final nestedValue in value.values) {
        final nested = _extractShoutIdFromDynamic(nestedValue);
        if (nested.isNotEmpty) {
          return nested;
        }
      }
    } else if (value is Iterable) {
      for (final nestedValue in value) {
        final nested = _extractShoutIdFromDynamic(nestedValue);
        if (nested.isNotEmpty) {
          return nested;
        }
      }
    }

    return '';
  }

  String _normalizeComparableValue(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _normalizeComparableNickname(String value) {
    return _normalizeComparableValue(value).toLowerCase();
  }

  String _normalizeComparableUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    if (trimmed.startsWith('//')) {
      return 'https:$trimmed';
    }
    if (trimmed.startsWith('/')) {
      return 'https://www.furaffinity.net$trimmed';
    }
    return trimmed;
  }

  String _extractProfileNickname(String? href) {
    if (href == null || href.isEmpty) {
      return '';
    }

    final parts = href.split('/').where((part) => part.isNotEmpty).toList();
    final userIndex = parts.indexOf('user');
    if (userIndex != -1 && userIndex + 1 < parts.length) {
      return parts[userIndex + 1].toLowerCase();
    }

    return parts.isEmpty ? '' : parts.last.toLowerCase();
  }

  String _normalizeComparableMessageHtml(String rawHtml) {
    if (rawHtml.trim().isEmpty) {
      return '';
    }

    final document = html_parser.parse('<div id="root">$rawHtml</div>');
    final root = document.querySelector('#root');
    if (root == null) {
      return '';
    }

    final content = root.querySelector('.user-submitted-links') ?? root;
    return _normalizeComparableValue(content.innerHtml);
  }

  String _normalizeComparableMessageText(String rawHtml) {
    if (rawHtml.trim().isEmpty) {
      return '';
    }

    final document = html_parser.parse('<div id="root">$rawHtml</div>');
    final root = document.querySelector('#root');
    if (root == null) {
      return '';
    }

    final content = root.querySelector('.user-submitted-links') ?? root;
    return _normalizeComparableValue(content.text);
  }

  bool _controlsEntryMatchesShout(
    ControlsShoutEntry entry,
    Shout shout,
  ) {
    if (shout.id.isNotEmpty && shout.id == entry.id) {
      return true;
    }

    final shoutNickname = _normalizeComparableNickname(shout.profileNickname);
    final entryNickname = _normalizeComparableNickname(entry.profileNickname);
    if (shoutNickname.isNotEmpty &&
        entryNickname.isNotEmpty &&
        shoutNickname != entryNickname) {
      return false;
    }

    final shoutDate = _normalizeComparableValue(shout.popupDateFull);
    final entryDate = _normalizeComparableValue(entry.popupDateFull);
    if (shoutDate.isNotEmpty &&
        entryDate.isNotEmpty &&
        shoutDate != entryDate) {
      return false;
    }

    final shoutHtml = _normalizeComparableMessageHtml(shout.text);
    final entryHtml = _normalizeComparableMessageHtml(entry.messageHtml);
    if (shoutHtml.isNotEmpty &&
        entryHtml.isNotEmpty &&
        shoutHtml == entryHtml) {
      return true;
    }

    final shoutText = _normalizeComparableMessageText(shout.text);
    final entryText = _normalizeComparableMessageText(entry.messageHtml);
    if (shoutText.isNotEmpty &&
        entryText.isNotEmpty &&
        shoutText == entryText) {
      return true;
    }

    final shoutAvatar = _normalizeComparableUrl(shout.avatarUrl);
    final entryAvatar = _normalizeComparableUrl(entry.avatarUrl);
    return shoutDate.isNotEmpty &&
        entryDate.isNotEmpty &&
        shoutDate == entryDate &&
        shoutNickname.isNotEmpty &&
        entryNickname.isNotEmpty &&
        shoutNickname == entryNickname &&
        (shoutAvatar.isEmpty ||
            entryAvatar.isEmpty ||
            shoutAvatar == entryAvatar);
  }

  ControlsShoutEntry? _findMatchingControlsEntry({
    required List<ControlsShoutEntry> entries,
    required Shout shout,
    required Set<String> usedIds,
  }) {
    for (final entry in entries) {
      if (usedIds.contains(entry.id)) {
        continue;
      }
      if (_controlsEntryMatchesShout(entry, shout)) {
        return entry;
      }
    }

    return null;
  }

  /// Parse additional shouts returned from a pagination call.
  /// Expects the FA JSON payload that includes HTML fragments.
  List<Shout> parseAdditionalShoutsJson(
    String jsonBody,
    Set<String> existingShoutIds,
    int sourcePage,
  ) {
    final List<Shout> newShouts = [];
    try {
      final Map<String, dynamic> jsonData = json.decode(jsonBody);
      if (!jsonData.containsKey('shouts')) return newShouts;

      final shoutsList = jsonData['shouts'] as List<dynamic>;
      for (var shoutData in shoutsList) {
        if (shoutData is! Map) {
          continue;
        }

        final shoutMap = Map<String, dynamic>.from(shoutData);
        final shoutId = _extractShoutIdFromPayload(shoutMap);

        if (shoutId.isNotEmpty && existingShoutIds.contains(shoutId)) {
          continue;
        }

        String avatarUrl = shoutMap['avatar_url'] ?? '';
        if (avatarUrl.startsWith('//')) {
          avatarUrl = 'https:$avatarUrl';
        }

        String displayNameHtml =
            shoutMap['shout_display_name_with_icons'] ?? '';
        final displayNameDoc = html_parser.parse(displayNameHtml);

        final displayNameElem = displayNameDoc.querySelector('.js-displayName');
        final userNameElem =
            displayNameDoc.querySelector('a.c-usernameBlock__userName span');
        final symbolElem =
            displayNameDoc.querySelector('.c-usernameBlock__symbol');

        String displayName = displayNameElem?.text.trim() ?? 'Unknown';
        String userNamePart = userNameElem?.text.trim() ?? '';
        String symbol = symbolElem?.text.trim() ?? "~";

        final usernameWithoutSymbol =
            userNamePart.replaceFirst(symbol, '').trim();
        String cmtUsername = (usernameWithoutSymbol.isEmpty ||
                displayName.toLowerCase() ==
                    usernameWithoutSymbol.toLowerCase())
            ? displayName
            : '$displayName\n@$usernameWithoutSymbol';

        String profileNickname = 'Unknown';
        final profileLink = displayNameDoc.querySelector('a[href*="/user/"]');
        if (profileLink != null) {
          String? href = profileLink.attributes['href'];
          if (href != null) {
            profileNickname =
                href.split('/').where((part) => part.isNotEmpty).last;
          }
        }

        String relativeDate = 'Unknown date';
        String fullDate = 'Unknown date';
        String dateHtml = shoutMap['thisdate'] ?? '';
        if (dateHtml.isNotEmpty) {
          final dateDoc = html_parser.parse(dateHtml);
          final dateElem = dateDoc.querySelector('span.popup_date');
          if (dateElem != null) {
            relativeDate = dateElem.text.trim();
            fullDate = dateElem.attributes['title']?.trim() ?? relativeDate;
          }
        }

        String text = shoutMap['message'] ?? '';

        List<String> shoutIconBeforeUrls = [];
        List<String> shoutIconAfterUrls = [];

        final beforeIcons =
            displayNameDoc.querySelectorAll('usericon-block-before img');
        shoutIconBeforeUrls = beforeIcons
            .map((imgElem) {
              String? src = imgElem.attributes['src'];
              if (src != null) {
                if (src.startsWith('//')) return 'https:$src';
                if (src.startsWith('/'))
                  return 'https://www.furaffinity.net$src';
                return src;
              }
              return '';
            })
            .where((src) => src.isNotEmpty)
            .toList();

        final afterIcons =
            displayNameDoc.querySelectorAll('usericon-block-after img');
        shoutIconAfterUrls = afterIcons
            .map((imgElem) {
              String? src = imgElem.attributes['src'];
              if (src != null) {
                if (src.startsWith('//')) return 'https:$src';
                if (src.startsWith('/'))
                  return 'https://www.furaffinity.net$src';
                return src;
              }
              return '';
            })
            .where((src) => src.isNotEmpty)
            .toList();

        newShouts.add(Shout(
          id: shoutId,
          avatarUrl: avatarUrl,
          username: cmtUsername,
          profileNickname: profileNickname,
          date: relativeDate,
          text: text,
          popupDateFull: fullDate,
          popupDateRelative: relativeDate,
          iconBeforeUrls: shoutIconBeforeUrls,
          iconAfterUrls: shoutIconAfterUrls,
          symbol: symbol,
          sourcePage: sourcePage,
        ));
      }
    } catch (_) {}

    return newShouts;
  }

  static UserProfileParsed parseUserProfile(String htmlBody) {
    final document = html_parser.parse(htmlBody);

    bool localHasRealUserProfile = true;

    String? userProfileImageUrl;
    String? userProfilePostNumber;
    String? userProfileTexts;
    bool acceptingTrades = false;
    bool acceptingCommissions = false;

    String? profileBannerUrl;
    final bannerElem = document.querySelector(
            'site-banner picture source[media="(min-width: 800px)"]') ??
        document.querySelector('site-banner img') ??
        document.querySelector('source[media="(min-width: 800px)"]');
    if (bannerElem != null) {
      String bannerUrl =
          bannerElem.attributes['srcset'] ?? bannerElem.attributes['src'] ?? '';
      if (bannerUrl.startsWith('/themes/beta/img/banners/logo/')) {
        profileBannerUrl = 'https://www.furaffinity.net$bannerUrl';
      } else if (bannerUrl.startsWith('//')) {
        profileBannerUrl = 'https:$bannerUrl';
      } else if (bannerUrl.startsWith('http://') ||
          bannerUrl.startsWith('https://')) {
        profileBannerUrl = bannerUrl;
      } else {
        profileBannerUrl = 'https://www.furaffinity.net$bannerUrl';
      }
    } else {
      profileBannerUrl =
          'https://d.furaffinity.net/media/banners/modern/fa-banner-summer.jpg';
    }

    String? profileImageUrl;
    final profilePicElem = document.querySelector('userpage-nav-avatar img') ??
        document.querySelector('img.avatar');
    profileImageUrl = profilePicElem != null
        ? (profilePicElem.attributes['src']?.replaceFirst('//', 'https://'))
        : null;

    final displayNameElem = document
            .querySelector('a.c-usernameBlock__displayName .js-displayName') ??
        document.querySelector('a.js-displayName-block .js-displayName');
    final displayName = displayNameElem?.text.trim() ?? 'Unknown User';

    final userNameElem =
        document.querySelector('a.c-usernameBlock__userName span') ??
            document.querySelector('a.js-userName-block span');
    final symbolElem = document.querySelector(
            'a.c-usernameBlock__userName span .c-usernameBlock__symbol') ??
        document
            .querySelector('a.js-userName-block span .c-usernameBlock__symbol');

    String symbolText = symbolElem?.text.trim() ?? '';
    String fullUserName = userNameElem?.text.trim() ?? '';
    String nicknameWithoutSymbol = fullUserName;
    if (symbolText.isNotEmpty) {
      nicknameWithoutSymbol = fullUserName.replaceFirst(symbolText, '').trim();
    }
    final symbolUsername = symbolText.isNotEmpty
        ? '$symbolText $nicknameWithoutSymbol'
        : fullUserName;
    final username =
        (nicknameWithoutSymbol.isNotEmpty ? nicknameWithoutSymbol : displayName)
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9\\-_.~]'), '');
    final profileUserNamePart = '';

    List<String> userIconBeforeUrls = [];
    List<String> userIconAfterUrls = [];
    final usernameContainer = document.querySelector('.c-usernameBlock') ??
        document.querySelector('div.c-usernameBlock');
    final iconBeforeElems =
        usernameContainer?.querySelectorAll('usericon-block-before img');
    if (iconBeforeElems != null && iconBeforeElems.isNotEmpty) {
      userIconBeforeUrls = iconBeforeElems
          .map((imgElem) {
            String? src = imgElem.attributes['src'];
            if (src != null) {
              if (src.startsWith('//')) return 'https:$src';
              if (src.startsWith('/')) return 'https://www.furaffinity.net$src';
              return src;
            }
            return '';
          })
          .where((src) => src.isNotEmpty)
          .toList();
    }
    final iconAfterElems =
        usernameContainer?.querySelectorAll('usericon-block-after img');
    if (iconAfterElems != null && iconAfterElems.isNotEmpty) {
      userIconAfterUrls = iconAfterElems
          .map((imgElem) {
            String? src = imgElem.attributes['src'];
            if (src != null) {
              if (src.startsWith('//')) return 'https:$src';
              if (src.startsWith('/')) return 'https://www.furaffinity.net$src';
              return src;
            }
            return '';
          })
          .where((src) => src.isNotEmpty)
          .toList();
    }

    String? userTitle;
    String? registrationDate;
    final userTitleElem = document.querySelector('span.user-title');
    if (userTitleElem != null) {
      String fullText = userTitleElem.text.trim();
      final regExp = RegExp(r'Registered:\s+(.+)$', multiLine: true);
      final regMatch = regExp.firstMatch(fullText);
      if (regMatch != null) {
        registrationDate = regMatch.group(1)!.trim();
        userTitle = fullText.substring(0, regMatch.start).trim();
        if (userTitle.endsWith("|")) {
          userTitle = userTitle.substring(0, userTitle.length - 1).trim();
        }
      } else {
        userTitle = fullText;
        registrationDate = "";
      }
    } else {
      final classicHtml = document.body?.innerHtml ?? "";
      final userTitleMatch = RegExp(r'<b>\s*User Title:\s*<\/b>\s*([^<]+)')
          .firstMatch(classicHtml);
      final registeredMatch =
          RegExp(r'<b>\s*Registered Since:\s*<\/b>\s*([^<]+)')
              .firstMatch(classicHtml);
      userTitle = userTitleMatch?.group(1)?.trim() ?? "";
      registrationDate = registeredMatch?.group(1)?.trim() ?? 'N/A';
    }

    String? userDescription;
    bool hasRealUserProfile = true;
    final sectionElem =
        document.querySelector('section.userpage-layout-profile') ??
            document.querySelector('td.ldot');
    if (sectionElem != null) {
      if (sectionElem.localName == 'section') {
        userDescription = sectionElem.outerHtml.trim();
      } else if (sectionElem.localName == 'td') {
        String classicHtml = sectionElem.innerHtml;
        const headerMarker = '<b>Artist Profile:</b><br>';
        final splitIndex = classicHtml.indexOf(headerMarker);
        if (splitIndex != -1) {
          userDescription =
              classicHtml.substring(splitIndex + headerMarker.length).trim();
        } else {
          userDescription = classicHtml.trim();
        }
      }

      if (userDescription != null &&
          userDescription.contains('<i>Not Available...</i>')) {
        hasRealUserProfile = false;
      }
    } else {
      userDescription = 'No description available.';
      hasRealUserProfile = false;
    }

    int? views;
    int? submissions;
    int? favs;
    int? commentsEarned;
    int? commentsMade;
    int? journals;
    dom.Element? statsSection =
        document.querySelector('.userpage-section-right .section-body');
    String statsText = "";
    if (statsSection != null) {
      statsText = statsSection.text.trim();
    } else {
      dom.Element? classicStatsTable;
      for (dom.Element table in document.querySelectorAll('table')) {
        var firstRow = table.querySelector('tr');
        if (firstRow != null) {
          var firstCell = firstRow.querySelector('td');
          if (firstCell != null && firstCell.text.trim() == 'Statistics') {
            classicStatsTable = table;
            break;
          }
        }
      }
      if (classicStatsTable != null) {
        var statsCell = classicStatsTable
            .querySelector('tr:nth-child(2) td[align=\"left\"]');
        statsText = statsCell?.text.trim() ?? "";
      }
    }

    int? _extract(String label) {
      final regex = RegExp('$label\\s*(\\d+)');
      final match = regex.firstMatch(statsText);
      if (match != null && match.groupCount > 0) {
        return int.tryParse(match.group(1)!);
      }
      return null;
    }

    if (statsText.isNotEmpty) {
      views = _extract('Views:') ?? _extract('Page Visits:');
      submissions = _extract('Submissions:');
      favs = _extract('Favs:') ?? _extract('Favorites:');
      commentsEarned =
          _extract('Comments Earned:') ?? _extract('Comments Received:');
      commentsMade = _extract('Comments Made:') ?? _extract('Comments Given:');
      journals = _extract('Journals:');
    } else {
      views = 0;
      submissions = 0;
      favs = 0;
      commentsEarned = 0;
      commentsMade = 0;
      journals = 0;
    }

    bool isClassicMarkup = document.body != null &&
        document.body!.attributes['data-static-path'] == '/themes/classic';

    bool userProfileFound = false;
    if (!isClassicMarkup) {
      final userSections = document.querySelectorAll('.userpage-section-right');
      for (var section in userSections) {
        final headerElem = section.querySelector('.section-header h2') ??
            section.querySelector('.section-header h3') ??
            section.querySelector('.section-header');
        final headerText = headerElem?.text.trim() ?? '';

        if (headerText.toLowerCase() == 'user profile'.toLowerCase()) {
          final linkElem = section.querySelector(
                  '.section-submission.aligncenter a[href^="/view/"]') ??
              section.querySelector('.section-submission a[href^="/view/"]') ??
              section.querySelector('.section-body a[href^="/view/"]') ??
              section.querySelector('a[href^="/view/"]');

          if (linkElem != null) {
            final href = linkElem.attributes['href'];
            if (href != null) {
              final hrefParts = href.split('/');
              userProfilePostNumber =
                  hrefParts.length > 2 ? hrefParts[2] : 'N/A';
            }

            final imageElem = linkElem.querySelector('img') ??
                section.querySelector('.section-submission.aligncenter img') ??
                section.querySelector('.section-submission img') ??
                section.querySelector('.section-body img');

            if (imageElem != null) {
              String? imageSrc = imageElem.attributes['src'];
              if (imageSrc != null && imageSrc.isNotEmpty) {
                if (imageSrc.startsWith('//')) {
                  userProfileImageUrl = 'https:$imageSrc';
                } else if (imageSrc.startsWith('http://') ||
                    imageSrc.startsWith('https://')) {
                  userProfileImageUrl = imageSrc;
                } else {
                  userProfileImageUrl = 'https://www.furaffinity.net$imageSrc';
                }
              }
            }
          }

          final sectionBodyElem = section.querySelector('.section-body');
          if (sectionBodyElem != null &&
              sectionBodyElem.innerHtml.trim().isNotEmpty) {
            userProfileTexts = sectionBodyElem.innerHtml.trim();
          } else {
            userProfileTexts = null;
          }

          userProfileFound = true;
          break;
        }
      }
    }

    if (isClassicMarkup || !userProfileFound) {
      final profileIdElem = document.getElementById('profilepic-submission');
      if (profileIdElem != null) {
        final anchor = profileIdElem.querySelector('a[href^="/view/"]');
        if (anchor != null) {
          final href = anchor.attributes['href'];
          if (href != null) {
            final parts = href.split('/');
            userProfilePostNumber = parts.length > 2 ? parts[2] : 'N/A';
          }
        }

        final imageElem = profileIdElem.querySelector('img');
        if (imageElem != null) {
          String? imageSrc = imageElem.attributes['src'];
          if (imageSrc != null) {
            if (imageSrc.startsWith('//')) {
              userProfileImageUrl = 'https:$imageSrc';
            } else if (imageSrc.startsWith('http://') ||
                imageSrc.startsWith('https://')) {
              userProfileImageUrl = imageSrc;
            } else {
              userProfileImageUrl = 'https://www.furaffinity.net$imageSrc';
            }
          }
        }
      }

      dom.Element? artistInfoCell;
      for (dom.Element table in document.querySelectorAll('table.maintable')) {
        final headerElem = table.querySelector('td.cat b');
        if (headerElem != null &&
            headerElem.text.trim() == 'Artist Information') {
          artistInfoCell = table.querySelector('td.alt1.user-info');
          break;
        }
      }

      if (artistInfoCell != null) {
        userProfileTexts = artistInfoCell.innerHtml.trim();
      }

      final optionYesElements = document.querySelectorAll('span.option-yes');
      acceptingTrades = optionYesElements.any(
        (elem) => elem.text.trim().toLowerCase().contains('trades'),
      );
      acceptingCommissions = optionYesElements.any(
        (elem) => elem.text.trim().toLowerCase().contains('commissions'),
      );
    }

    String? featuredImageUrl;
    String? featuredImageTitle;
    String? featuredPostNumber;

    dom.Element? featuredSection;
    for (final section in document.querySelectorAll('.userpage-section-left')) {
      final header = section.querySelector('.section-header h2') ??
          section.querySelector('.section-header h3') ??
          section.querySelector('.section-header');
      if (header != null &&
          header.text
              .toLowerCase()
              .contains('featured submission'.toLowerCase())) {
        featuredSection = section;
        break;
      }
    }

    if (featuredSection != null) {
      final linkElem = featuredSection.querySelector(
              '.section-body .aligncenter.preview_img a[href^="/view/"]') ??
          featuredSection.querySelector('.section-body a[href^="/view/"]') ??
          featuredSection.querySelector('a[href^="/view/"]');

      if (linkElem != null) {
        final href = linkElem.attributes['href'];
        if (href != null) {
          final hrefParts = href.split('/');
          featuredPostNumber = hrefParts.length > 2 ? hrefParts[2] : 'N/A';
        }

        final imgElem = linkElem.querySelector('img') ??
            featuredSection.querySelector('.section-body img') ??
            featuredSection.querySelector('img');
        if (imgElem != null) {
          var imageSrc = imgElem.attributes['src'] ?? '';
          if (imageSrc.isNotEmpty) {
            if (imageSrc.startsWith('//')) {
              featuredImageUrl = 'https:$imageSrc';
            } else if (imageSrc.startsWith('http://') ||
                imageSrc.startsWith('https://')) {
              featuredImageUrl = imageSrc;
            } else {
              featuredImageUrl = 'https://www.furaffinity.net$imageSrc';
            }
          }
        }
      }

      final titleElem =
          featuredSection.querySelector('.userpage-featured-title h2 a') ??
              featuredSection.querySelector('.userpage-featured-title h3 a') ??
              featuredSection.querySelector('.userpage-featured-title a') ??
              featuredSection.querySelector('.section-body h2 a') ??
              featuredSection.querySelector('.section-body h3 a');

      if (titleElem != null && titleElem.text.trim().isNotEmpty) {
        featuredImageTitle = titleElem.text.trim();
      }
    }

    if ((featuredImageUrl == null || featuredPostNumber == null) &&
        isClassicMarkup) {
      dom.Element? featuredTable;
      for (dom.Element table in document.querySelectorAll('table.maintable')) {
        final headerElem = table.querySelector('td.cat b');
        if (headerElem != null &&
            headerElem.text.trim() == 'Featured Submission') {
          featuredTable = table;
          break;
        }
      }

      if (featuredTable != null) {
        final contentCell =
            featuredTable.querySelector('td.alt1#featured-submission');
        if (contentCell != null) {
          final anchor = contentCell.querySelector('center a[href^="/view/"]');
          if (anchor != null) {
            final href = anchor.attributes['href'];
            if (href != null) {
              final hrefParts = href.split('/');
              featuredPostNumber = hrefParts.length > 2 ? hrefParts[2] : 'N/A';
            }
            final img = anchor.querySelector('img');
            if (img != null) {
              String? imageSrc = img.attributes['src'];
              if (imageSrc != null) {
                if (imageSrc.startsWith('//')) {
                  featuredImageUrl = 'https:$imageSrc';
                } else if (imageSrc.startsWith('http://') ||
                    imageSrc.startsWith('https://')) {
                  featuredImageUrl = imageSrc;
                } else {
                  featuredImageUrl = 'https://www.furaffinity.net$imageSrc';
                }
              }
            }
          }

          final spanTitle = contentCell.querySelector('center b span');
          featuredImageTitle =
              spanTitle != null && spanTitle.text.trim().isNotEmpty
                  ? spanTitle.text.trim()
                  : featuredImageTitle;
        }
      }
    }

    List<Map<String, String>> contactInformationLinks = [];
    dom.Element? contactInfoSection =
        document.querySelector('#userpage-contact');
    if (contactInfoSection != null) {
      final contactItems =
          contactInfoSection.querySelectorAll('.user-contact-item');
      for (var item in contactItems) {
        final labelElement =
            item.querySelector('.user-contact-user-info .highlight');
        final valueElement = item.querySelector('.user-contact-user-info a');
        String? label = labelElement?.text.trim();
        if (label != null && label.endsWith(':')) {
          label = label.substring(0, label.length - 1);
        }
        String? href = valueElement?.attributes['href'];
        String value = valueElement?.text.trim() ?? 'N/A';
        if (label != null && href != null) {
          if (valueElement!.children.isNotEmpty &&
              valueElement.children.first.localName == 'i') {
            value = valueElement.children.first.text.trim();
          }
          if (value.isNotEmpty && value != 'N/A') {
            contactInformationLinks
                .add({'label': label, 'value': value, 'href': href});
          }
        }
      }
    }

    List<UserLink> recentWatchers = [];
    int recentWatchersCount = 0;
    dom.Element? recentWatchersSection =
        document.querySelector('section.userpage-left-column.watched-by-block');
    if (recentWatchersSection != null) {
      final viewListLink = recentWatchersSection
          .querySelector('.section-header .floatright h3 a');
      if (viewListLink != null) {
        final linkText = viewListLink.text.trim();
        final countMatch = RegExp(r'Watched by (\d+)').firstMatch(linkText);
        if (countMatch != null && countMatch.groupCount >= 1) {
          recentWatchersCount = int.tryParse(countMatch.group(1)!) ?? 0;
        }
      }

      final userElements = recentWatchersSection.querySelectorAll(
          '.section-body span.c-usernameBlockSimple__displayName');
      for (var userElem in userElements) {
        final watcherName = userElem.text.trim();
        final linkElem = userElem.parent;
        final href = linkElem?.attributes['href'] ?? '';
        if (watcherName.isNotEmpty && href.isNotEmpty) {
          final fullUrl = href.startsWith('http')
              ? href
              : 'https://www.furaffinity.net$href';
          recentWatchers.add(UserLink(rawUsername: watcherName, url: fullUrl));
        }
      }
    } else {
      dom.Element? watchersTable;
      for (dom.Element table in document.querySelectorAll('table.maintable')) {
        final headerElem = table.querySelector('td.cat b');
        if (headerElem != null && headerElem.text.trim() == 'Watched By') {
          watchersTable = table;
          break;
        }
      }

      if (watchersTable != null) {
        final watchersCell = watchersTable.querySelector('td#watched-by');
        if (watchersCell != null) {
          final userElements = watchersCell
              .querySelectorAll('span.c-usernameBlockSimple__displayName');
          for (var userElem in userElements) {
            final watcherName = userElem.text.trim();
            final linkElem = userElem.parent;
            final href = linkElem?.attributes['href'] ?? '';
            if (watcherName.isNotEmpty && href.isNotEmpty) {
              final fullUrl = href.startsWith('http')
                  ? href
                  : 'https://www.furaffinity.net$href';
              recentWatchers
                  .add(UserLink(rawUsername: watcherName, url: fullUrl));
            }
          }
        }

        final countLink = watchersTable.querySelector('td.cat a');
        if (countLink != null) {
          final linkText = countLink.text.trim();
          final countMatch = RegExp(r'\((\d+)\)').firstMatch(linkText);
          if (countMatch != null && countMatch.groupCount >= 1) {
            recentWatchersCount = int.tryParse(countMatch.group(1)!) ?? 0;
          }
        }
      }
    }

    List<UserLink> recentlyWatched = [];
    int recentlyWatchedCount = 0;
    dom.Element? recentlyWatchedSection = document
        .querySelector('section.userpage-left-column.is-watching-block');
    if (recentlyWatchedSection != null) {
      final viewListLink = recentlyWatchedSection
          .querySelector('.section-header .floatright h3 a');
      if (viewListLink != null) {
        final linkText = viewListLink.text.trim();
        final countMatch = RegExp(r'Watching (\d+)').firstMatch(linkText);
        if (countMatch != null && countMatch.groupCount >= 1) {
          recentlyWatchedCount = int.tryParse(countMatch.group(1)!) ?? 0;
        }
      }

      final userElements = recentlyWatchedSection.querySelectorAll(
          '.section-body span.c-usernameBlockSimple__displayName');
      for (var userElem in userElements) {
        final watchedName = userElem.text.trim();
        final linkElem = userElem.parent;
        final href = linkElem?.attributes['href'] ?? '';
        if (watchedName.isNotEmpty && href.isNotEmpty) {
          final fullUrl = href.startsWith('http')
              ? href
              : 'https://www.furaffinity.net$href';
          recentlyWatched.add(UserLink(rawUsername: watchedName, url: fullUrl));
        }
      }
    } else {
      dom.Element? watchingTable;
      for (dom.Element table in document.querySelectorAll('table.maintable')) {
        final headerElem = table.querySelector('td.cat b');
        if (headerElem != null && headerElem.text.trim() == 'Is Watching') {
          watchingTable = table;
          break;
        }
      }

      if (watchingTable != null) {
        final watchingCell = watchingTable.querySelector('td#is-watching');
        if (watchingCell != null) {
          final userElements = watchingCell
              .querySelectorAll('span.c-usernameBlockSimple__displayName');
          for (var userElem in userElements) {
            final watchedName = userElem.text.trim();
            final linkElem = userElem.parent;
            final href = linkElem?.attributes['href'] ?? '';
            if (watchedName.isNotEmpty && href.isNotEmpty) {
              final fullUrl = href.startsWith('http')
                  ? href
                  : 'https://www.furaffinity.net$href';
              recentlyWatched
                  .add(UserLink(rawUsername: watchedName, url: fullUrl));
            }
          }
        }

        final countLink = watchingTable.querySelector('td.cat a');
        if (countLink != null) {
          final linkText = countLink.text.trim();
          final countMatch = RegExp(r'\((\d+)\)').firstMatch(linkText);
          if (countMatch != null && countMatch.groupCount >= 1) {
            recentlyWatchedCount = int.tryParse(countMatch.group(1)!) ?? 0;
          }
        }
      }
    }

    List<Shout> shouts = [];
    String? shoutPaginationKey;
    int currentShoutPage = 1;
    int totalShoutPages = 1;

    dom.Element? shoutsSection =
        document.querySelector('.userpage-section-right.no-border');
    if (shoutsSection != null) {
      final shoutContainers =
          shoutsSection.querySelectorAll('div.comment_container');
      for (var container in shoutContainers) {
        final avatarElem = container.querySelector('img.comment_useravatar');
        String avatarUrl = avatarElem != null
            ? (avatarElem.attributes['src']!.startsWith('//')
                ? 'https:${avatarElem.attributes['src']!}'
                : avatarElem.attributes['src']!)
            : 'assets/images/defaultpic.gif';

        final displayNameElem = container
            .querySelector('a.c-usernameBlock__displayName .js-displayName');
        final userNameElem = container.querySelector(
            'a.c-usernameBlock__userName .js-userName-block span');
        final displayNameShout = displayNameElem?.text.trim() ?? 'Unknown';
        final userNamePartShout = userNameElem?.text.trim() ?? '';

        final symbolElemShout = container.querySelector(
            'a.c-usernameBlock__userName .c-usernameBlock__symbol');
        final symbolShout = symbolElemShout?.text.trim() ?? "~";

        final usernameWithoutSymbol =
            userNamePartShout.replaceFirst(symbolShout, '').trim();
        String cmtUsername = (usernameWithoutSymbol.isEmpty ||
                displayNameShout.toLowerCase() ==
                    usernameWithoutSymbol.toLowerCase())
            ? displayNameShout
            : '$displayNameShout\n@$usernameWithoutSymbol';

        final usernameLink = container.querySelector('div.avatar a');
        String? profileNickname = usernameLink?.attributes['href'] != null
            ? usernameLink!.attributes['href']!
                .split('/')
                .where((part) => part.isNotEmpty)
                .last
            : 'Unknown';

        final dateElem = container.querySelector('span.popup_date');
        String relativeDate = dateElem?.text.trim() ?? 'Unknown date';
        String fullDate = dateElem?.attributes['title']?.trim() ?? relativeDate;

        final textElem =
            container.querySelector('comment-user-text.comment_text');
        String text = textElem?.innerHtml.trim() ?? '';

        String shoutId = '';
        final anchor =
            container.querySelector('a.comment_anchor[id^=\"shout-\"]');
        if (anchor != null) {
          final idAttr = anchor.attributes['id'] ?? '';
          if (idAttr.startsWith('shout-')) {
            shoutId = idAttr.substring('shout-'.length);
          }
        }

        List<String> shoutIconBeforeUrls = [];
        List<String> shoutIconAfterUrls = [];
        final shoutUsernameContainer =
            container.querySelector('.c-usernameBlock');
        if (shoutUsernameContainer != null) {
          final beforeIcons = shoutUsernameContainer
              .querySelectorAll('usericon-block-before img');
          shoutIconBeforeUrls = beforeIcons
              .map((imgElem) {
                String? src = imgElem.attributes['src'];
                if (src != null) {
                  if (src.startsWith('//')) return 'https:$src';
                  if (src.startsWith('/'))
                    return 'https://www.furaffinity.net$src';
                  return src;
                }
                return '';
              })
              .where((src) => src.isNotEmpty)
              .toList();

          final afterIcons = shoutUsernameContainer
              .querySelectorAll('usericon-block-after img');
          shoutIconAfterUrls = afterIcons
              .map((imgElem) {
                String? src = imgElem.attributes['src'];
                if (src != null) {
                  if (src.startsWith('//')) return 'https:$src';
                  if (src.startsWith('/'))
                    return 'https://www.furaffinity.net$src';
                  return src;
                }
                return '';
              })
              .where((src) => src.isNotEmpty)
              .toList();
        }

        shouts.add(Shout(
          id: shoutId,
          avatarUrl: avatarUrl,
          username: cmtUsername,
          profileNickname: profileNickname ?? 'Unknown',
          date: relativeDate,
          text: text,
          popupDateFull: fullDate,
          popupDateRelative: relativeDate,
          iconBeforeUrls: shoutIconBeforeUrls,
          iconAfterUrls: shoutIconAfterUrls,
          symbol: symbolShout,
          sourcePage: currentShoutPage,
        ));
      }

      dom.Element? shoutPaginationForm =
          document.querySelector('form.c-shoutPaginationForm');
      if (shoutPaginationForm != null) {
        final keyInput =
            shoutPaginationForm.querySelector('input[name=\"key\"]');
        shoutPaginationKey = keyInput?.attributes['value'];

        final pageSelect =
            shoutPaginationForm.querySelector('select[name=\"shout_page\"]');
        if (pageSelect != null) {
          final options = pageSelect.querySelectorAll('option');
          if (options.isNotEmpty) {
            totalShoutPages = options.length;
          }
          final selectedOption = pageSelect.querySelector('option[selected]');
          if (selectedOption != null) {
            currentShoutPage =
                int.tryParse(selectedOption.attributes['value'] ?? '1') ?? 1;
          }
        }
      }
    }

    var watchLinkElement =
        document.querySelector('a.button.standard.go[href^=\"/watch/\"]') ??
            document.querySelector('a[href^=\"/watch/\"]');

    var unwatchLinkElement =
        document.querySelector('a.button.standard.stop[href^=\"/unwatch/\"]') ??
            document.querySelector('a[href^=\"/unwatch/\"]');

    var blockLinkElement =
        document.querySelector('a.button.standard.stop[href^=\"/block/\"]') ??
            document.querySelector('form[action^=\"/block/\"]');
    String? computedBlockLink;
    bool blockUsesPost = false;
    if (blockLinkElement != null) {
      if (blockLinkElement.localName == 'form') {
        blockUsesPost = true;
        final actionUrl = blockLinkElement.attributes['action'];
        final keyElem = blockLinkElement.querySelector('input[name=\"key\"]') ??
            blockLinkElement.querySelector('button[name=\"key\"]');
        final keyValue = keyElem?.attributes['value'] ?? '';

        if (actionUrl != null && keyValue.isNotEmpty) {
          final actionUri = Uri.parse(actionUrl.startsWith('http')
              ? actionUrl
              : 'https://www.furaffinity.net$actionUrl');
          computedBlockLink =
              actionUri.replace(queryParameters: {'key': keyValue}).toString();
        }
      } else {
        computedBlockLink = blockLinkElement.attributes['href'];
      }
    }

    var unblockLinkElement =
        document.querySelector('a.button.standard.stop[href^=\"/unblock/\"]') ??
            document.querySelector('form[action^=\"/unblock/\"]');
    String? computedUnblockLink;
    bool unblockUsesPost = false;
    if (unblockLinkElement != null) {
      if (unblockLinkElement.localName == 'form') {
        unblockUsesPost = true;
        final actionUrl = unblockLinkElement.attributes['action'];
        final keyElem =
            unblockLinkElement.querySelector('input[name=\"key\"]') ??
                unblockLinkElement.querySelector('button[name=\"key\"]');
        final keyValue = keyElem?.attributes['value'] ?? '';

        if (actionUrl != null && keyValue.isNotEmpty) {
          final actionUri = Uri.parse(actionUrl.startsWith('http')
              ? actionUrl
              : 'https://www.furaffinity.net$actionUrl');
          computedUnblockLink =
              actionUri.replace(queryParameters: {'key': keyValue}).toString();
        }
      } else {
        computedUnblockLink = unblockLinkElement.attributes['href'];
      }
    }

    bool isOwnProfile = watchLinkElement == null &&
        unwatchLinkElement == null &&
        blockLinkElement == null &&
        unblockLinkElement == null;

    if (userProfileTexts != null && userProfileTexts.trim().isEmpty) {
      userProfileTexts = null;
    }

    return UserProfileParsed(
      profileBannerUrl: profileBannerUrl,
      profileImageUrl: profileImageUrl,
      profileDisplayName: displayName,
      profileUserNamePart: profileUserNamePart,
      symbolUsername: symbolUsername,
      username: username,
      userTitle: userTitle,
      registrationDate: registrationDate,
      userDescription: userDescription,
      hasRealUserProfile: hasRealUserProfile,
      isClassicMarkup: isClassicMarkup,
      acceptingTrades: acceptingTrades,
      acceptingCommissions: acceptingCommissions,
      userIconBeforeUrls: userIconBeforeUrls,
      userIconAfterUrls: userIconAfterUrls,
      views: views,
      submissions: submissions,
      favs: favs,
      commentsEarned: commentsEarned,
      commentsMade: commentsMade,
      journals: journals,
      featuredImageUrl: featuredImageUrl,
      featuredImageTitle: featuredImageTitle,
      featuredPostNumber: featuredPostNumber,
      userProfileImageUrl: userProfileImageUrl,
      userProfilePostNumber: userProfilePostNumber,
      userProfileTexts: userProfileTexts,
      contactInformationLinks: contactInformationLinks,
      recentWatchers: recentWatchers,
      recentWatchersCount: recentWatchersCount,
      recentlyWatched: recentlyWatched,
      recentlyWatchedCount: recentlyWatchedCount,
      shouts: shouts,
      shoutPaginationKey: shoutPaginationKey,
      currentShoutPage: currentShoutPage,
      totalShoutPages: totalShoutPages,
      watchLink: watchLinkElement?.attributes['href'],
      unwatchLink: unwatchLinkElement?.attributes['href'],
      blockLink: computedBlockLink,
      unblockLink: computedUnblockLink,
      blockUsesPost: blockUsesPost,
      unblockUsesPost: unblockUsesPost,
      isWatching: unwatchLinkElement != null,
      isBlocked: computedUnblockLink != null,
      isOwnProfile: isOwnProfile,
    );
  }
}
