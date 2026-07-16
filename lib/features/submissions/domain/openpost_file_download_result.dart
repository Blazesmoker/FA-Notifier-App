enum OpenPostFileDownloadStatus {
  saved,
  cancelled,
  httpFailure,
  failed,
}

class OpenPostFileDownloadResult {
  const OpenPostFileDownloadResult(
    this.status, {
    this.statusCode,
  });

  final OpenPostFileDownloadStatus status;
  final int? statusCode;
}
