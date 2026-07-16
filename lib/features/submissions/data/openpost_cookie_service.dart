import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart';

import 'package:FANotifier/core/fa/fa_cookie_helper.dart';
import 'package:FANotifier/core/network/fa_http.dart';

class OpenPostCookieService {
  const OpenPostCookieService({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                accountName: 'flutter_secure_storage_service',
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _secureStorage;

  Future<bool> hasAuthCookies() async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    return cookieA != null && cookieB != null;
  }

  Future<String> buildCookieHeader({
    required bool sfwEnabled,
    required bool nsfwAllowed,
    bool skipSfw = false,
  }) async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');

    var cookieHeader = '';
    if (cookieA != null && cookieB != null) {
      cookieHeader = 'a=$cookieA; b=$cookieB';
    }

    if (!skipSfw && sfwEnabled && !nsfwAllowed) {
      cookieHeader += '; sfw=1';
    }

    return cookieHeader;
  }

  Future<Response> getWithSfwCookie({
    required String url,
    required bool sfwEnabled,
    required bool nsfwAllowed,
    Map<String, String>? additionalHeaders,
    bool skipSfw = false,
    Duration? timeout,
  }) async {
    final headers = await _buildHeaders(
      sfwEnabled: sfwEnabled,
      nsfwAllowed: nsfwAllowed,
      skipSfw: skipSfw,
      additionalHeaders: additionalHeaders,
    );
    return FAHttp.get(
      Uri.parse(url),
      headers: headers,
      timeout: timeout,
    );
  }

  Future<Response> getMediaWithSfwCookie({
    required String url,
    required bool sfwEnabled,
    required bool nsfwAllowed,
    Map<String, String>? additionalHeaders,
    bool skipSfw = false,
    Duration? timeout,
  }) async {
    final headers = await _buildHeaders(
      sfwEnabled: sfwEnabled,
      nsfwAllowed: nsfwAllowed,
      skipSfw: skipSfw,
      additionalHeaders: additionalHeaders,
    );
    return FAHttp.getMedia(
      Uri.parse(url),
      headers: headers,
      timeout: timeout,
    );
  }

  Future<Map<String, String>> _buildHeaders({
    required bool sfwEnabled,
    required bool nsfwAllowed,
    required bool skipSfw,
    required Map<String, String>? additionalHeaders,
  }) async {
    final cookieHeader = await buildCookieHeader(
      sfwEnabled: sfwEnabled,
      nsfwAllowed: nsfwAllowed,
      skipSfw: skipSfw,
    );
    final headers = <String, String>{
      'Cookie':
          await FaCookieHelper.appendCfClearanceToCookieHeader(cookieHeader),
      'User-Agent': FAHttp.userAgent,
    };
    if (additionalHeaders != null) headers.addAll(additionalHeaders);
    return headers;
  }
}
