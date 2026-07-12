enum OpenPostMediaExportStatus { permissionDenied, saveFailed, success }

class OpenPostMediaExportResult {
  const OpenPostMediaExportResult(this.status);

  final OpenPostMediaExportStatus status;
}
