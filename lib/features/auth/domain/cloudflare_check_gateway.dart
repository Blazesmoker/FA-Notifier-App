import 'package:fanotifier/features/auth/domain/cloudflare_http_access_result.dart';

typedef CloudflareJavascriptEvaluator =
    Future<Object?> Function(String source);

abstract interface class CloudflareCheckGateway {
  String get userAgent;

  Future<void> accessVerified();

  bool isFaUrl(String url);

  Future<void> setStoredCookies();

  Future<bool> saveCurrentCookies({
    required String url,
    CloudflareJavascriptEvaluator? evaluateJavascript,
    bool Function()? isCancelled,
  });

  bool isChallengePage({
    required String url,
    required String body,
    int? statusCode,
    Map<String, String>? headers,
  });

  bool isSuccessfulPage({
    required String url,
    required String body,
    int? statusCode,
    Map<String, String>? headers,
  });

  Future<CloudflareHttpAccessResult> verifyHttpAccess({
    required String url,
    bool Function()? isCancelled,
  });
}
