enum SubmissionMediaExportStatus { permissionDenied, saveFailed, success }

class SubmissionMediaExportResult {
  const SubmissionMediaExportResult(this.status);

  final SubmissionMediaExportStatus status;
}
