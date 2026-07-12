import 'package:FANotifier/features/auth/data/cloudflare_http_access_verifier.dart';
import 'package:FANotifier/features/auth/data/cloudflare_webview_cookie_service.dart';
import 'package:FANotifier/features/auth/domain/cloudflare_check_gateway.dart';

class CloudflareCheckGatewayImpl implements CloudflareCheckGateway {
  const CloudflareCheckGatewayImpl({
    CloudflareHttpAccessVerifier httpAccessVerifier =
        const CloudflareHttpAccessVerifier(),
    CloudflareWebViewCookieService webViewCookieService =
        const CloudflareWebViewCookieService(),
  })  : _httpAccessVerifier = httpAccessVerifier,
        _webViewCookieService = webViewCookieService;

  final CloudflareHttpAccessVerifier _httpAccessVerifier;
  final CloudflareWebViewCookieService _webViewCookieService;

  @override
  String get userAgent => _httpAccessVerifier.userAgent;

  @override
  bool isFaUrl(String url) {
    return url.contains('furaffinity.net');
  }

  @override
  Future<void> setStoredCookies() {
    return _webViewCookieService.setStoredCookies();
  }

  @override
  Future<void> saveCurrentCookies({
    CloudflareJavascriptEvaluator? evaluateJavascript,
  }) {
    return _webViewCookieService.saveCurrentCookies(
      evaluateJavascript: evaluateJavascript,
    );
  }

  @override
  bool isChallengePage({
    required String url,
    required String body,
  }) {
    return _webViewCookieService.isChallengePage(url: url, body: body);
  }

  @override
  Future<bool> verifyHttpAccess({
    required String url,
    Future<void> Function()? beforeRetryAttempt,
  }) {
    return _httpAccessVerifier.verify(
      url: url,
      beforeRetryAttempt: beforeRetryAttempt,
    );
  }
}
