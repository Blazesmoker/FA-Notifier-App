import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:fanotifier/features/auth/domain/cloudflare_check_gateway.dart';
import 'package:fanotifier/core/fa/fa_cookie_helper.dart';
import 'package:fanotifier/core/fa/fa_media_auth.dart';

class CloudflareWebViewCookieService {
  const CloudflareWebViewCookieService({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                accountName: 'flutter_secure_storage_service',
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _secureStorage;

  bool isChallengePage({
    required String url,
    required String body,
  }) {
    return url.contains('/cdn-cgi/challenge-platform') ||
        FaCookieHelper.isCloudflareChallengePage(body: body);
  }

  Future<void> setStoredCookies() async {
    final cookieKeys = <String>[
      'a',
      'b',
      'cc',
      'cf_clearance',
      'folder',
      'nodesc',
      'sz',
      'sfw',
    ];

    for (final key in cookieKeys) {
      final value = await _secureStorage.read(key: 'fa_cookie_$key');
      if (value == null || value.isEmpty) continue;
      await CookieManager.instance().setCookie(
        url: WebUri('https://www.furaffinity.net'),
        name: key,
        value: value,
        domain: '.furaffinity.net',
        path: '/',
        isHttpOnly: true,
        isSecure: true,
        expiresDate:
            DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch,
      );
    }
  }

  Future<void> saveCurrentCookies({
    CloudflareJavascriptEvaluator? evaluateJavascript,
  }) async {
    final existingCf = await _secureStorage.read(key: 'fa_cookie_cf_clearance');
    final cookies = await CookieManager.instance().getCookies(
      url: WebUri('https://www.furaffinity.net'),
    );

    String? latestCf;
    for (final cookie in cookies) {
      await _secureStorage.write(
        key: 'fa_cookie_${cookie.name}',
        value: cookie.value,
      );
      if (cookie.name == 'cf_clearance' && cookie.value.isNotEmpty) {
        latestCf = cookie.value;
      }
    }

    if ((latestCf == null || latestCf.isEmpty) &&
        existingCf != null &&
        existingCf.isNotEmpty) {
      await _secureStorage.write(
        key: 'fa_cookie_cf_clearance',
        value: existingCf,
      );
    } else if (latestCf != null && latestCf.isNotEmpty) {
      await FaCookieHelper.writeCfClearance(latestCf);
    }

    if (evaluateJavascript == null) {
      FaMediaAuth.invalidate();
      return;
    }

    try {
      final rawDocumentCookie =
          await evaluateJavascript('document.cookie');
      final documentCookie = rawDocumentCookie?.toString() ?? '';
      final cookiePairs = documentCookie.split(';');
      for (final pair in cookiePairs) {
        final separator = pair.indexOf('=');
        if (separator <= 0) continue;
        final name = pair.substring(0, separator).trim();
        final value = pair.substring(separator + 1).trim();
        if (name.isEmpty || value.isEmpty) continue;
        await _secureStorage.write(key: 'fa_cookie_$name', value: value);
        if (name == 'cf_clearance') {
          await FaCookieHelper.writeCfClearance(value);
        }
      }
    } catch (_) {}

    FaMediaAuth.invalidate();
  }
}
