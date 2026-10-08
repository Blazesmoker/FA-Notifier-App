import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:fanotifier/features/auth/domain/cloudflare_check_gateway.dart';
import 'package:fanotifier/core/fa/fa_cookie_helper.dart';
import 'package:fanotifier/core/fa/fa_webview_cookie_service.dart';

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
    int? statusCode,
    Map<String, String>? headers,
  }) {
    return url.contains('/cdn-cgi/challenge-platform') ||
        FaCookieHelper.isCloudflareChallengePage(
          body: body,
          statusCode: statusCode,
          headers: headers,
        );
  }

  Future<void> setStoredCookies() {
    return FAWebViewCookieService(secureStorage: _secureStorage).setCookies(
      applySfwPreference: false,
      preserveExistingSession: true,
    );
  }

  Future<bool> saveCurrentCookies({
    required String url,
    CloudflareJavascriptEvaluator? evaluateJavascript,
    bool Function()? isCancelled,
  }) {
    return FAWebViewCookieService(secureStorage: _secureStorage).captureCookies(
      url: url,
      evaluateJavascript: evaluateJavascript,
      isCancelled: isCancelled,
    );
  }
}
