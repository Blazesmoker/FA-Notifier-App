import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:fanotifier/core/fa/fa_media_auth.dart';
import 'package:fanotifier/core/fa/fa_webview_cookie_service.dart';

class HomeAuthCookieService {
  const HomeAuthCookieService({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                accountName: 'flutter_secure_storage_service',
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _secureStorage;

  Future<bool> hasWebViewAuthCookie() async {
    final cookies = await CookieManager.instance().getCookies(
      url: WebUri("https://www.furaffinity.net"),
    );

    final aCookies = cookies.where((cookie) => cookie.name == 'a');
    return aCookies.any((cookie) => cookie.value.isNotEmpty);
  }

  Future<void> saveCookiesFromWebView() async {
    final cookies = await CookieManager.instance().getCookies(
      url: WebUri("https://www.furaffinity.net"),
    );

    for (final cookie in cookies) {
      if (cookie.name == 'cf_clearance') continue;
      await _secureStorage.write(
        key: 'fa_cookie_${cookie.name}',
        value: cookie.value,
      );
    }
    await FAWebViewCookieService(secureStorage: _secureStorage).captureCookies(
      url: 'https://www.furaffinity.net/',
    );
    FaMediaAuth.invalidate();
  }

  Future<void> setStoredCookies() async {
    final cookieKeys = [
      'a',
      'b',
      'cc',
      'cf_clearance',
      'folder',
      'nodesc',
      'sz',
      'sfw'
    ];
    for (final key in cookieKeys) {
      if (key == 'cf_clearance') {
        await FAWebViewCookieService(secureStorage: _secureStorage)
            .restoreClearance();
        continue;
      }
      final storageKey = 'fa_cookie_$key';
      final cookieValue = await _secureStorage.read(key: storageKey);
      if (cookieValue != null && cookieValue.isNotEmpty) {
        await CookieManager.instance().setCookie(
          url: WebUri('https://www.furaffinity.net'),
          name: key,
          value: cookieValue,
          domain: '.furaffinity.net',
          path: '/',
          isHttpOnly: true,
          isSecure: true,
          expiresDate:
              DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch,
        );
      }
    }
  }

  Future<void> clearStoredCookies() async {
    await _secureStorage.deleteAll();
    FaMediaAuth.invalidate();
  }

  Future<void> clearWebViewCookies() {
    return CookieManager.instance().deleteAllCookies();
  }

  Future<void> setSfwCookieToNsfw() async {
    await _secureStorage.write(key: 'fa_cookie_sfw', value: '0');
    FaMediaAuth.invalidate();
    await CookieManager.instance().setCookie(
      url: WebUri('https://www.furaffinity.net'),
      name: 'sfw',
      value: '0',
      domain: '.furaffinity.net',
      path: '/',
      isHttpOnly: true,
      isSecure: true,
      expiresDate:
          DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch,
    );
  }
}
