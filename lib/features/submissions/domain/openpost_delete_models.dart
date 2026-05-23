class OpenPostDeleteConfirmationData {
  final String confirmValue;
  final String deleteSubmissionsSubmitValue;
  final String submissionIdValue;

  const OpenPostDeleteConfirmationData({
    required this.confirmValue,
    required this.deleteSubmissionsSubmitValue,
    required this.submissionIdValue,
  });
}

class OpenPostDeletePrepareResult {
  final int statusCode;
  final OpenPostDeleteConfirmationData? confirmationData;

  const OpenPostDeletePrepareResult({
    required this.statusCode,
    required this.confirmationData,
  });
}
