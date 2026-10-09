enum SubmissionActionStatus { missingAuth, success, failure }

class SubmissionActionResult {
  const SubmissionActionResult({
    required this.status,
    this.statusCode,
    this.confirmedTagName,
  });

  final SubmissionActionStatus status;
  final int? statusCode;
  final String? confirmedTagName;
}
