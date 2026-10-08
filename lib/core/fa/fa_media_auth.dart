import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:fanotifier/core/network/fa_http.dart';
import 'package:fanotifier/core/fa/fa_cookie_helper.dart';

class FaMediaAuth {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accountName: 'flutter_secure_storage_service',
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  static Map<String, String>? _cachedHeaders;
  static Future<Map<String, String>?>? _headersFuture;
  static String? _cachedClearance;
  static Map<String, dynamic>? _cachedClearanceScope;
  static final ValueNotifier<int> _revision = ValueNotifier<int>(0);
  static final StreamController<int> _sessionChanges =
      StreamController<int>.broadcast();

  static ValueListenable<int> get changes => _revision;
  static Stream<int> get sessionChanges => _sessionChanges.stream;

  static String normalizeUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.startsWith('//')) {
      return 'https:$trimmed';
    }
    if (trimmed.startsWith('/')) {
      return 'https://www.furaffinity.net$trimmed';
    }
    return trimmed;
  }

  static bool isFaUrl(String url) {
    final uri = Uri.tryParse(normalizeUrl(url));
    final host = uri?.host.toLowerCase() ?? '';
    return host == 'furaffinity.net' || host.endsWith('.furaffinity.net');
  }

  static Future<Map<String, String>?> headersForUrl(String url) async {
    if (!isFaUrl(url)) {
      return null;
    }
    final revision = _revision.value;
    final headers = _cachedHeaders ??
        await (_headersFuture ??= _loadHeaders(url, revision));
    if (revision != _revision.value) return headersForUrl(url);
    if (headers == null) return null;
    final clearance = _cachedClearance;
    if (clearance == null ||
        !FaCookieHelper.isClearanceApplicable(
          _cachedClearanceScope,
          uri: Uri.parse(normalizeUrl(url)),
        )) {
      return headers;
    }
    final cookies = headers['Cookie'];
    return Map<String, String>.unmodifiable({
      ...headers,
      'Cookie': cookies == null || cookies.isEmpty
          ? 'cf_clearance=$clearance'
          : '$cookies; cf_clearance=$clearance',
    });
  }

  static void invalidate() {
    _cachedHeaders = null;
    _headersFuture = null;
    _cachedClearance = null;
    _cachedClearanceScope = null;
    _revision.value++;
    _sessionChanges.add(_revision.value);
  }

  static Future<Map<String, String>?> _loadHeaders(
    String url,
    int revision,
  ) async {
    final cookieNames = <String>[
      'a',
      'b',
      'cc',
      'folder',
      'nodesc',
      'sz',
      'sfw',
    ];
    final cookies = <String, String>{};
    for (final name in cookieNames) {
      final value = await _secureStorage.read(key: 'fa_cookie_$name');
      if (value != null && value.isNotEmpty) {
        cookies[name] = value;
      }
    }
    final clearance = await FaCookieHelper.readCfClearance();
    final clearanceScope = await FaCookieHelper.readCfClearanceScope();
    await _addWebViewCookies(cookies, 'https://www.furaffinity.net/');
    await _addWebViewCookies(cookies, normalizeUrl(url));

    final headers = <String, String>{
      'User-Agent': FAHttp.userAgent,
      'Referer': 'https://www.furaffinity.net/',
      'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.9',
    };
    if (cookies.isNotEmpty) {
      headers['Cookie'] =
          cookies.entries.map((entry) => '${entry.key}=${entry.value}').join('; ');
    }
    if (revision != _revision.value) return headersForUrl(url);
    _cachedClearance = clearance;
    _cachedClearanceScope = clearanceScope;
    _cachedHeaders = Map<String, String>.unmodifiable(headers);
    _headersFuture = null;
    return _cachedHeaders;
  }

  static Future<void> _addWebViewCookies(
    Map<String, String> target,
    String url,
  ) async {
    try {
      final cookies = await CookieManager.instance().getCookies(
        url: WebUri(url),
      );
      for (final cookie in cookies) {
        if (cookie.name == 'cf_clearance') {
          continue;
        }
        if (cookie.name.isNotEmpty && cookie.value.isNotEmpty) {
          target[cookie.name] = cookie.value;
        }
      }
    } catch (_) {}
  }
}
