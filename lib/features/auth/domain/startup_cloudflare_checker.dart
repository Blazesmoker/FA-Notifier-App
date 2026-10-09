class StartupCloudflareCheckResult {
  const StartupCloudflareCheckResult({
    required this.needsChallenge,
    this.accessGranted = true,
    this.homeHtml,
    this.siteUnavailableMessage,
  });

  final bool needsChallenge;
  final bool accessGranted;
  final String? homeHtml;
  final String? siteUnavailableMessage;
}

abstract interface class StartupCloudflareChecker {
  Future<StartupCloudflareCheckResult> checkHome({
    String url = 'https://www.furaffinity.net/',
    bool Function()? isCancelled,
  });
}
