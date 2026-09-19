enum SubmissionFileDownloadStatus {
  saved,
  cancelled,
  httpFailure,
  failed,
}

class SubmissionFileDownloadResult {
  const SubmissionFileDownloadResult(
    this.status, {
    this.statusCode,
  });

  final SubmissionFileDownloadStatus status;
  final int? statusCode;
}
