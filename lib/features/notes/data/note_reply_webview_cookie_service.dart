import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:webview_flutter/webview_flutter.dart';

class NoteReplyWebViewCookieService {
  const NoteReplyWebViewCookieService({
    required FlutterSecureStorage secureStorage,
  }) : _secureStorage = secureStorage;

  final FlutterSecureStorage _secureStorage;

  Future<bool> setAuthCookies() async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');

    if (cookieA == null || cookieB == null) {
      return false;
    }

    final cookieManager = WebViewCookieManager();
    await cookieManager.setCookie(
      WebViewCookie(
        name: 'a',
        value: cookieA,
        domain: '.furaffinity.net',
        path: '/',
      ),
    );
    await cookieManager.setCookie(
      WebViewCookie(
        name: 'b',
        value: cookieB,
        domain: '.furaffinity.net',
        path: '/',
      ),
    );

    return true;
  }
}
