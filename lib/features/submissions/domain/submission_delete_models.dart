class SubmissionDeleteConfirmationData {
  final String confirmValue;
  final String deleteSubmissionsSubmitValue;
  final String submissionIdValue;

  const SubmissionDeleteConfirmationData({
    required this.confirmValue,
    required this.deleteSubmissionsSubmitValue,
    required this.submissionIdValue,
  });
}

class SubmissionDeletePrepareResult {
  final int statusCode;
  final SubmissionDeleteConfirmationData? confirmationData;

  const SubmissionDeletePrepareResult({
    required this.statusCode,
    required this.confirmationData,
  });
}
