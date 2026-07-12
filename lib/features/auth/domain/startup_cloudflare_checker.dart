class StartupCloudflareCheckResult {
  const StartupCloudflareCheckResult({
    required this.needsChallenge,
    this.homeHtml,
  });

  final bool needsChallenge;
  final String? homeHtml;
}

abstract interface class StartupCloudflareChecker {
  Future<StartupCloudflareCheckResult> checkHome({
    String url = 'https://www.furaffinity.net/',
  });
}
