import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class FaMediaAuth {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accountName: 'flutter_secure_storage_service',
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  static Map<String, String>? _cachedHeaders;
  static Future<Map<String, String>?>? _headersFuture;

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
    if (_cachedHeaders != null) {
      return _cachedHeaders;
    }
    _headersFuture ??= _loadHeaders(url);
    return _headersFuture;
  }

  static void invalidate() {
    _cachedHeaders = null;
    _headersFuture = null;
  }

  static Future<Map<String, String>?> _loadHeaders(String url) async {
    final cookieNames = <String>[
      'a',
      'b',
      'cc',
      'cf_clearance',
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
    await _addWebViewCookies(cookies, 'https://www.furaffinity.net/');
    await _addWebViewCookies(cookies, normalizeUrl(url));

    final headers = <String, String>{
      'Referer': 'https://www.furaffinity.net/',
      'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.9',
    };
    if (cookies.isNotEmpty) {
      headers['Cookie'] =
          cookies.entries.map((entry) => '${entry.key}=${entry.value}').join('; ');
    }
    _cachedHeaders = headers;
    _headersFuture = null;
    return headers;
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
        if (cookie.name.isNotEmpty && cookie.value.isNotEmpty) {
          target[cookie.name] = cookie.value;
        }
      }
    } catch (_) {}
  }
}
