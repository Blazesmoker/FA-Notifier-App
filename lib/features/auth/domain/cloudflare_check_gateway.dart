typedef CloudflareJavascriptEvaluator =
    Future<Object?> Function(String source);

abstract interface class CloudflareCheckGateway {
  String get userAgent;

  bool isFaUrl(String url);

  Future<void> setStoredCookies();

  Future<void> saveCurrentCookies({
    CloudflareJavascriptEvaluator? evaluateJavascript,
  });

  bool isChallengePage({
    required String url,
    required String body,
  });

  Future<bool> verifyHttpAccess({
    required String url,
    Future<void> Function()? beforeRetryAttempt,
  });
}
