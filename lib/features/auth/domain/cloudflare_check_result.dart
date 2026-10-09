class CloudflareCheckResult {
  final bool passed;
  final String? pageHtml;
  final String? finalUrl;
  final String? siteUnavailableMessage;

  const CloudflareCheckResult({
    required this.passed,
    this.pageHtml,
    this.finalUrl,
    this.siteUnavailableMessage,
  });
}
