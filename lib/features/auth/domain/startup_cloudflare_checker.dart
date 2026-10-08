class StartupCloudflareCheckResult {
  const StartupCloudflareCheckResult({
    required this.needsChallenge,
    this.accessGranted = true,
    this.homeHtml,
  });

  final bool needsChallenge;
  final bool accessGranted;
  final String? homeHtml;
}

abstract interface class StartupCloudflareChecker {
  Future<StartupCloudflareCheckResult> checkHome({
    String url = 'https://www.furaffinity.net/',
  });
}
