enum SubmissionActionStatus { missingAuth, success, failure }

class SubmissionActionResult {
  const SubmissionActionResult({
    required this.status,
    this.statusCode,
  });

  final SubmissionActionStatus status;
  final int? statusCode;
}
