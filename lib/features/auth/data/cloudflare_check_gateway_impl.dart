import 'package:fanotifier/core/fa/fa_cookie_helper.dart';
import 'package:fanotifier/core/fa/fa_session_access_service.dart';
import 'package:fanotifier/core/network/fa_request_coordinator.dart';
import 'package:fanotifier/features/auth/data/cloudflare_http_access_verifier.dart';
import 'package:fanotifier/features/auth/data/cloudflare_webview_cookie_service.dart';
import 'package:fanotifier/features/auth/data/fa_access_page_classifier.dart';
import 'package:fanotifier/features/auth/domain/cloudflare_check_gateway.dart';
import 'package:fanotifier/features/auth/domain/cloudflare_http_access_result.dart';

class CloudflareCheckGatewayImpl implements CloudflareCheckGateway {
  const CloudflareCheckGatewayImpl({
    this._httpAccessVerifier = const CloudflareHttpAccessVerifier(),
    this._webViewCookieService = const CloudflareWebViewCookieService(),
  });

  final CloudflareHttpAccessVerifier _httpAccessVerifier;
  final CloudflareWebViewCookieService _webViewCookieService;

  @override
  String get userAgent => _httpAccessVerifier.userAgent;

  @override
  Future<void> accessVerified() =>
      FaSessionAccessService.instance.accessVerified();

  @override
  Future<void> waitForSiteRetry({bool Function()? isCancelled}) {
    return FaRequestCoordinator.instance.waitForTurn(
      label: 'FA availability retry',
      isCancelled: isCancelled,
    );
  }

  @override
  bool isFaUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.userInfo.isEmpty &&
        (!uri.hasPort || uri.port == 443) &&
        (uri.host == 'www.furaffinity.net' || uri.host == 'furaffinity.net');
  }

  @override
  Future<void> setStoredCookies() {
    return _webViewCookieService.setStoredCookies();
  }

  @override
  Future<bool> saveCurrentCookies({
    required String url,
    CloudflareJavascriptEvaluator? evaluateJavascript,
    bool Function()? isCancelled,
  }) {
    return _webViewCookieService.saveCurrentCookies(
      url: url,
      evaluateJavascript: evaluateJavascript,
      isCancelled: isCancelled,
    );
  }

  @override
  bool isChallengePage({
    required String url,
    required String body,
    int? statusCode,
    Map<String, String>? headers,
  }) {
    return _webViewCookieService.isChallengePage(
      url: url,
      body: body,
      statusCode: statusCode,
      headers: headers,
    );
  }

  @override
  bool isSuccessfulPage({
    required String url,
    required String body,
    int? statusCode,
    Map<String, String>? headers,
  }) {
    return isFaUrl(url) &&
        FaCookieHelper.isFaDocument(
          body: body,
          statusCode: statusCode,
          headers: headers,
        );
  }

  @override
  CloudflareHttpAccessResult classifyPage({
    required String url,
    required String body,
    int? statusCode,
    Map<String, String>? headers,
  }) {
    final result = classifyFaAccessPage(
      url: url,
      body: body,
      statusCode: statusCode,
      headers: headers,
    );
    recordFaAccessAvailability(result);
    return result;
  }

  @override
  Future<CloudflareHttpAccessResult> verifyHttpAccess({
    required String url,
    bool Function()? isCancelled,
  }) {
    if (!isFaUrl(url)) {
      return Future.value(const CloudflareHttpAccessResult(
        status: CloudflareHttpAccessStatus.denied,
      ));
    }
    return _httpAccessVerifier.verify(
      url: url,
      isCancelled: isCancelled,
    );
  }
}
