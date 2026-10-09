enum CloudflareHttpAccessStatus {
  granted,
  challenged,
  denied,
  siteUnavailable,
  unavailable,
  cancelled,
}

class CloudflareHttpAccessResult {
  const CloudflareHttpAccessResult({
    required this.status,
    this.statusCode,
    this.pageHtml,
    this.finalUrl,
    this.siteUnavailableMessage,
    this.retryAfter,
  });

  final CloudflareHttpAccessStatus status;
  final int? statusCode;
  final String? pageHtml;
  final String? finalUrl;
  final String? siteUnavailableMessage;
  final Duration? retryAfter;

  bool get granted => status == CloudflareHttpAccessStatus.granted;
}
