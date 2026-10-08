enum CloudflareHttpAccessStatus {
  granted,
  challenged,
  denied,
  unavailable,
  cancelled,
}

class CloudflareHttpAccessResult {
  const CloudflareHttpAccessResult({
    required this.status,
    this.statusCode,
    this.pageHtml,
    this.finalUrl,
  });

  final CloudflareHttpAccessStatus status;
  final int? statusCode;
  final String? pageHtml;
  final String? finalUrl;

  bool get granted => status == CloudflareHttpAccessStatus.granted;
}
