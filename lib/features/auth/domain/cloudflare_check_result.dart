class CloudflareCheckResult {
  final bool passed;
  final String? pageHtml;
  final String? finalUrl;

  const CloudflareCheckResult({
    required this.passed,
    this.pageHtml,
    this.finalUrl,
  });
}
