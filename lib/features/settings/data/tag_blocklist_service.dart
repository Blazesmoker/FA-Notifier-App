import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart';

import 'package:FANotifier/features/settings/data/tag_blocklist_api_service.dart';
import 'package:FANotifier/features/settings/domain/tag_blocklist_parse_result.dart';
import 'package:FANotifier/shared/fa/fa_cookie_helper.dart';
import 'package:FANotifier/shared/fa/fa_http.dart';
import 'package:FANotifier/shared/fa/parsing_utils.dart';

const tagBlocklistProfileUrl = 'https://www.furaffinity.net/controls/profile/';
const tagBlocklistRouteUrl = 'https://www.furaffinity.net/route/tag_blocking';

Future<TagBlocklistParseResult> fetchTagBlocklist({
  FlutterSecureStorage? secureStorage,
  required bool sfwEnabled,
}) async {
  final storage = secureStorage ?? _defaultSecureStorage();
  final resp = await _getWithCookie(
    tagBlocklistProfileUrl,
    secureStorage: storage,
    sfwEnabled: sfwEnabled,
  );
  if (resp.statusCode != 200) {
    throw Exception('Failed to load profile controls: ${resp.statusCode}');
  }

  final decoded = _decodeBody(resp);
  final doc = await parseHtml(decoded);
  return TagBlocklistApiService.parse(doc, decoded);
}

Future<void> sendTagBlocklistRequest({
  FlutterSecureStorage? secureStorage,
  required bool sfwEnabled,
  required String nonce,
  required String tagName,
  required bool shouldBlock,
}) async {
  final storage = secureStorage ?? _defaultSecureStorage();
  final cookieA = await storage.read(key: 'fa_cookie_a');
  final cookieB = await storage.read(key: 'fa_cookie_b');
  final sfwValue = sfwEnabled ? '1' : '0';

  if (cookieA == null || cookieB == null) {
    throw Exception('Not logged in.');
  }
  if (nonce.isEmpty) {
    throw Exception('Missing tag blocklist nonce.');
  }

  final response = await FAHttp.post(
    Uri.parse(tagBlocklistRouteUrl),
    headers: <String, String>{
      'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
        'a=$cookieA; b=$cookieB; sfw=$sfwValue',
      ),
      'Referer': tagBlocklistProfileUrl,
      'Origin': 'https://www.furaffinity.net',
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: <String, String>{
      'action': shouldBlock ? 'add-tag' : 'remove-tag',
      'key': nonce,
      'tag_name': tagName,
    },
  );

  if (response.statusCode != 200) {
    throw Exception('Tag blocklist request failed: ${response.statusCode}');
  }
}

Future<Response> _getWithCookie(
  String url, {
  required FlutterSecureStorage secureStorage,
  required bool sfwEnabled,
}) async {
  final cookieA = await secureStorage.read(key: 'fa_cookie_a');
  final cookieB = await secureStorage.read(key: 'fa_cookie_b');
  if (cookieA == null || cookieB == null) {
    throw Exception('Not logged in.');
  }

  final sfwValue = sfwEnabled ? '1' : '0';
  return FAHttp.get(
    Uri.parse(url),
    headers: <String, String>{
      'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
        'a=$cookieA; b=$cookieB; sfw=$sfwValue',
      ),
    },
  );
}

String _decodeBody(Response response) {
  try {
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  } catch (_) {
    return latin1.decode(response.bodyBytes, allowInvalid: true);
  }
}

FlutterSecureStorage _defaultSecureStorage() {
  return const FlutterSecureStorage(
    iOptions: IOSOptions(
      accountName: 'flutter_secure_storage_service',
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );
}
