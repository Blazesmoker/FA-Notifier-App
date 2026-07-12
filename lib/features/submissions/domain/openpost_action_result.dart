enum OpenPostActionStatus { missingAuth, success, failure }

class OpenPostActionResult {
  const OpenPostActionResult({
    required this.status,
    this.statusCode,
  });

  final OpenPostActionStatus status;
  final int? statusCode;
}
