import 'package:fanotifier/core/preferences/sfw_mode_preference.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class FAWebViewCookieService {
  const FAWebViewCookieService({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                accountName: 'flutter_secure_storage_service',
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _secureStorage;
  final SfwModePreference _sfwModePreference = const SfwModePreference();

  Future<void> setCookies() async {
    final cookieManager = CookieManager.instance();
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
      String value;
      if (key == 'sfw') {
        value = await _getSfwCookieValue();
      } else {
        value = await _secureStorage.read(key: 'fa_cookie_$key') ?? '';
      }

      if (value.isNotEmpty) {
        await cookieManager.setCookie(
          url: WebUri('https://www.furaffinity.net'),
          name: key,
          value: value,
          domain: '.furaffinity.net',
          path: '/',
          isSecure: true,
          isHttpOnly: true,
        );
      }
    }
  }

  Future<String> _getSfwCookieValue() async {
    final sfwEnabled = await _sfwModePreference.loadSfwEnabled();
    return sfwEnabled ? '1' : '0';
  }
}
